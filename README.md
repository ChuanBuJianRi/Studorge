# Effstudy

A **local AI learning workspace** built with **FastAPI** and any **OpenAI-compatible API**. Organize study as **topics** and a **tree of Q&A nodes**, add **per-topic RAG** with **ChromaDB**, and use **streaming** replies, **file import**, **speech-to-text**, and **TTS**.

## Features

| Feature | Description |
|--------|----------------|
| Topics & subtopics | Nested themes; spin off a subtopic from any Q&A node |
| Tree-shaped nodes | Parent/child Q&A; short titles for easier navigation |
| RAG | Past Q&A is embedded; new questions retrieve relevant context |
| Streaming | Server-Sent Events (SSE); persisted to SQLite and indexed after completion |
| Multimodal & media | Image (vision) input; PDF/text extraction; Whisper transcription; OpenAI TTS |
| API configuration | Environment variables or in-app settings (secrets stay in local SQLite—**never commit them**) |

## Stack

- **Backend**: Python 3, FastAPI, Uvicorn, SQLite (`data/learning.db`), ChromaDB (`data/chroma_db`)
- **AI**: Official `openai` Python SDK (custom `base_url` and model names supported)
- **Frontend**: Static assets served from `frontend/`

## Quick start

### 1. Clone and install

```bash
git clone https://github.com/ChuanBuJianRi/Effstudy.git
cd Effstudy
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Configure the API (do not commit secrets)

```bash
cp .env.example .env
```

Edit `.env` (or use the in-app **Settings** UI, which stores values in the local database):

- `OPENAI_API_KEY` — your API key  
- `OPENAI_BASE_URL` — e.g. `https://api.openai.com/v1` or another compatible endpoint  
- `OPENAI_MODEL` — e.g. `gpt-4o`  

**Security**

- `.gitignore` excludes `.env`, `data/`, and similar paths. Do not commit real keys or local databases.  
- If a key was ever committed, **rotate it** in the provider dashboard and remove it from Git history (e.g. `git filter-repo`).

### 3. Run

From the repository root:

```bash
python run.py
```

Open <http://127.0.0.1:8000/> in your browser.

## Project layout

```
Effstudy/
├── backend/           # FastAPI app, DB, RAG, AI client
├── frontend/          # Static UI (e.g. index.html)
├── data/              # Generated locally: SQLite + Chroma (gitignored)
├── run.py             # Dev entrypoint
├── requirements.txt
├── .env.example       # Template only (no real secrets)
└── README.md
```

## API overview

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/` | Web UI |
| GET/POST | `/api/topics` | List / create topics |
| POST | `/api/ask`, `/api/ask/stream` | Ask (sync / streaming) |
| GET | `/api/topics/{id}/tree`, `/full-tree` | Topic node trees |
| POST | `/api/upload` | PDF / text upload and extraction |
| POST | `/api/transcribe` | Speech to text |
| POST | `/api/tts` | Text to speech |
| GET/POST | `/api/settings` | Read / update API-related settings |

## License

If no `LICENSE` file is present in the repository, contact the author before redistributing.

## Contributing

Issues and pull requests are welcome. Before pushing, confirm you are not including `.env`, `data/`, or personal API keys.
