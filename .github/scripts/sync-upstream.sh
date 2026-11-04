#!/usr/bin/env bash
# Keep this fork's default branch up to date with its parent repository.
#
# The sync uses GitHub's merge-upstream API: a merge or a fast-forward,
# never a hard reset. `gh repo sync` is not used. Without --force it only
# fast-forwards and fails once this fork has its own commits. With --force
# it hard-resets the branch and would discard files that exist only here.
#
# If merge-upstream refuses the Actions token (HTTP 403), and
# ALLOW_GIT_FALLBACK=1, the script merges with git and pushes that merge
# commit with a normal push. A conflict aborts before any push. The push
# refspec never starts with '+' and the script never passes a force flag.
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${REPO:?REPO is required}"
: "${RUN_URL:?RUN_URL is required}"

ISSUE_TITLE="上游同步發生合併衝突"
BRANCH_PATTERN='^[A-Za-z0-9._/-]+$'
REPO_PATTERN='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'

summary() {
  printf '%s\n' "$1"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$1" >>"$GITHUB_STEP_SUMMARY"
  fi
}

fail() {
  echo "::error::$*"
  summary "$*"
  exit 1
}

require_match() {
  local label="$1"
  local value="$2"
  local pattern="$3"
  # shellcheck disable=SC2254
  if [[ ! "$value" =~ $pattern ]]; then
    fail "${label}不符合預期：${value}"
  fi
}

open_conflict_issue() {
  local method="$1"
  local detail_file="$2"
  local issue_body existing

  summary ""
  summary "### 合併衝突"
  summary "沒有 force-push，也沒有覆寫本 fork 的檔案。方式：${method}。"
  echo "::error::與上游 ${upstream}（${upstream_branch}）合併到 ${fork_branch} 時發生衝突。沒有 force-push。"

  if [[ "$has_issues" != "true" ]]; then
    echo "::warning::此儲存庫目前關閉 Issues，無法自動建立 issue。請看這個 Actions 日誌。"
    summary "此儲存庫目前關閉 Issues，所以沒有自動開 issue。請看 Actions 日誌：${RUN_URL}"
    return 0
  fi

  issue_body="$(mktemp)"
  {
    echo "自動同步無法把上游變更合併進本 fork 的預設分支，因為發生合併衝突。"
    echo
    echo "這個工作流程沒有 force-push，也沒有捨棄本 fork 自己新增的檔案。請手動解決衝突後，再到 Actions 重跑「Sync upstream」。"
    echo
    echo "- Fork：\`${REPO}\`"
    echo "- Fork 預設分支：\`${fork_branch}\`"
    echo "- 上游：https://github.com/${upstream}"
    echo "- 上游預設分支：\`${upstream_branch}\`"
    echo "- 合併方式：${method}"
    echo "- 執行紀錄：${RUN_URL}"
    echo
    echo "### 衝突細節"
    echo
    echo '```'
    if [[ -s "$detail_file" ]]; then
      cat "$detail_file"
    fi
    if [[ -s "$err_file" ]]; then
      echo
      cat "$err_file"
    fi
    echo '```'
  } >"$issue_body"

  existing="$(
    gh issue list \
      --repo "$REPO" \
      --state open \
      --limit 50 \
      --search "in:title ${ISSUE_TITLE}" \
      --json number,title \
      | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.title == $t) | .number][0] // empty'
  )"

  if [[ -n "$existing" ]]; then
    if gh issue comment "$existing" --repo "$REPO" --body-file "$issue_body"; then
      echo "已在既有 issue #${existing} 補充這次衝突。"
      summary "已更新既有 issue #${existing}。"
    else
      echo "::warning::無法在既有 issue #${existing} 留言。工作流程仍會因為衝突而失敗。"
    fi
  elif gh issue create --repo "$REPO" --title "$ISSUE_TITLE" --body-file "$issue_body"; then
    summary "已建立 issue：${ISSUE_TITLE}"
  else
    echo "::warning::無法建立 issue。工作流程仍會因為衝突而失敗。"
  fi
  rm -f "$issue_body"
}

git_fallback() {
  local refspec conflict_files merge_status

  command -v git >/dev/null 2>&1 || fail "找不到 git，無法改走合併後備。"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "目前的目錄不是 git 工作區，無法改走合併後備。"

  if git remote get-url upstream >/dev/null 2>&1; then
    git remote set-url upstream "https://github.com/${upstream}.git"
  else
    git remote add upstream "https://github.com/${upstream}.git"
  fi

  # Explicit refspecs have no leading '+', so this does not force-update
  # remote-tracking refs. The fork branch itself is only moved by the
  # normal push below, after a clean merge.
  git fetch --no-tags origin \
    "${fork_branch}:refs/remotes/origin/${fork_branch}"
  git checkout --detach "refs/remotes/origin/${fork_branch}"
  git fetch --no-tags upstream \
    "${upstream_branch}:refs/remotes/upstream/${upstream_branch}"

  set +e
  git \
    -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    merge --no-edit "refs/remotes/upstream/${upstream_branch}"
  merge_status=$?
  set -e

  if [[ "$merge_status" -ne 0 ]]; then
    conflict_files="$(git diff --name-only --diff-filter=U || true)"
    if [[ -n "$conflict_files" ]]; then
      printf '%s\n' "$conflict_files" >"$body_file"
      echo "衝突檔案："
      printf '%s\n' "$conflict_files"
      open_conflict_issue "git merge" "$body_file"
      git merge --abort || true
      exit 1
    fi
    fail "git merge 失敗（exit ${merge_status}）。沒有 push。"
  fi

  refspec="HEAD:${fork_branch}"
  if [[ "$refspec" == +* ]]; then
    fail "拒絕會覆寫歷史的 push refspec。"
  fi
  if ! git push origin "$refspec"; then
    fail "git push 被拒絕。沒有 force-push。"
  fi
  summary ""
  summary "結果：已用 git merge 同步並以一般 push 更新 \`${fork_branch}\`。本 fork 自己的檔案仍在。"
}

command -v gh >/dev/null 2>&1 || fail "找不到 gh。"
command -v jq >/dev/null 2>&1 || fail "找不到 jq。"

meta="$(gh api "repos/${REPO}")"
is_fork="$(jq -r '.fork' <<<"$meta")"
has_issues="$(jq -r '.has_issues' <<<"$meta")"
fork_branch="$(jq -r '.default_branch' <<<"$meta")"
upstream="$(jq -r '.parent.full_name // empty' <<<"$meta")"
upstream_branch="$(jq -r '.parent.default_branch // empty' <<<"$meta")"

if [[ "$is_fork" != "true" || -z "$upstream" || -z "$upstream_branch" ]]; then
  fail "這個儲存庫不是 fork，或讀不到上游 parent。拒絕同步。"
fi

require_match "fork 預設分支" "$fork_branch" "$BRANCH_PATTERN"
require_match "上游預設分支" "$upstream_branch" "$BRANCH_PATTERN"
require_match "上游儲存庫" "$upstream" "$REPO_PATTERN"

summary "## 上游同步"
summary "- Fork：\`${REPO}\`（\`${fork_branch}\`）"
summary "- 上游：[${upstream}](https://github.com/${upstream})（\`${upstream_branch}\`）"
summary "- 原則：合併上游，不 force-push，也不刪除只存在於本 fork 的檔案。"

echo "上游：https://github.com/${upstream}（${upstream_branch}）"
echo "Fork：https://github.com/${REPO}（${fork_branch}）"

body_file="$(mktemp)"
err_file="$(mktemp)"
trap 'rm -f "$body_file" "$err_file"' EXIT

set +e
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "repos/${REPO}/merge-upstream" \
  -f "branch=${fork_branch}" \
  >"$body_file" \
  2>"$err_file"
api_status=$?
set -e

http_code="$(grep -oE 'HTTP [0-9]{3}' "$err_file" | awk 'END { print $2 }' || true)"
message="$(jq -r '.message // empty' "$body_file" 2>/dev/null || true)"
merge_type="$(jq -r '.merge_type // empty' "$body_file" 2>/dev/null || true)"

echo "merge-upstream exit=${api_status} http=${http_code:-none} merge_type=${merge_type:-none}"
if [[ -s "$body_file" ]]; then
  echo "---- response ----"
  cat "$body_file"
  echo
fi
if [[ -s "$err_file" ]]; then
  echo "---- stderr ----"
  cat "$err_file"
fi

if [[ "$api_status" -eq 0 ]]; then
  summary ""
  summary "結果：成功（merge_type：\`${merge_type:-unknown}\`）。只存在於本 fork 的檔案會保留。"
  exit 0
fi

if [[ "$http_code" == "409" || "$message" == "Merge conflict" ]]; then
  open_conflict_issue "merge-upstream API" "$body_file"
  exit 1
fi

if [[ "$http_code" == "403" && "${ALLOW_GIT_FALLBACK:-}" == "1" ]]; then
  echo "merge-upstream 回 HTTP 403。改以 git merge 後備，仍然不會 force-push。"
  summary ""
  summary "merge-upstream 回 HTTP 403，改走 git merge（一般 push，不是 force-push）。"
  git_fallback
  exit 0
fi

fail "上游同步失敗（HTTP ${http_code:-unknown}，gh exit ${api_status}）。沒有 force-push。訊息：${message:-無}"
