# AnythingLLM（繁體中文說明｜Fork）

> 本儲存庫 fork 自上游 **[Mintplex-Labs/anything-llm](https://github.com/Mintplex-Labs/anything-llm)**。原英文說明保留在 [README.en.md](README.en.md)。

## 這是什麼
AnythingLLM 是私有的文件工作區（workspace）與 AI agent 應用，有桌面版也能自架。可以接本機模型或外部模型，提供文件 RAG、agent flows，以及 MCP 工具。

## 與個人 multi-AI 知識庫（ai-kb）的關係
ai-kb（Grok、Claude、Gemini、NotebookLM）目前的分工：
- **Open WebUI**：日常聊天與 Knowledge。
- **ThreadShelf**：原始匯出的封存與語意瀏覽。
- **AnythingLLM（本 fork）**：**目前暫緩**，保留作為之後的選項。要啟用時，可以把 ai-kb `export/md/<來源>/*.md` 上傳到各來源對應的 workspace，例如 grok、claude、gemini、notebooklm。

## 本機執行
- **桌面版**：從 https://anythingllm.com/download 下載安裝。
- **Docker**：
```bash
export STORAGE_LOCATION=$HOME/anythingllm && mkdir -p $STORAGE_LOCATION && touch "$STORAGE_LOCATION/.env"
docker run -d -p 3001:3001 --cap-add SYS_ADMIN \
  -v ${STORAGE_LOCATION}:/app/server/storage -v ${STORAGE_LOCATION}/.env:/app/server/.env \
  -e STORAGE_DIR="/app/server/storage" mintplexlabs/anythingllm
```
開啟 http://localhost:3001。
- **從原始碼開發**：先執行 `yarn setup`，再執行 `yarn dev:server`、`yarn dev:frontend`、`yarn dev:collector`。詳見 README.en.md。

## 授權
依上游 [LICENSE](LICENSE)。
