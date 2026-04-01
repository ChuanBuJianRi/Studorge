"""FastAPI application for the intelligent learning system."""
from fastapi import FastAPI, HTTPException, File, UploadFile
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, StreamingResponse, Response
from pydantic import BaseModel
from backend.database import (
    get_db, init_db, dict_from_row, dict_from_rows,
    get_setting, set_setting, delete_setting,
)
from backend.rag import add_to_rag, search_rag
from backend.ai_client import chat_with_ai, chat_with_rag, stream_chat_with_rag, get_ai_client, generate_title
import os
import json
import tempfile

app = FastAPI(title="Studorge")

FRONTEND_DIR = os.path.join(os.path.dirname(__file__), "..", "frontend")
app.mount("/static", StaticFiles(directory=FRONTEND_DIR), name="static")


@app.on_event("startup")
def startup():
    init_db()


@app.get("/")
def index():
    return FileResponse(os.path.join(FRONTEND_DIR, "index.html"))


# ──────────────────────────── Topic APIs ────────────────────────────

class TopicCreate(BaseModel):
    name: str
    parent_id: int | None = None
    source_node_id: int | None = None   # Q&A node that triggered this deep-dive topic


@app.post("/api/topics")
def create_topic(body: TopicCreate):
    conn = get_db()
    cursor = conn.execute(
        "INSERT INTO topics (name, parent_id, source_node_id) VALUES (?, ?, ?)",
        (body.name, body.parent_id, body.source_node_id),
    )
    conn.commit()
    topic = dict_from_row(
        conn.execute("SELECT * FROM topics WHERE id = ?", (cursor.lastrowid,)).fetchone()
    )
    conn.close()
    return topic


@app.get("/api/topics")
def list_topics():
    conn = get_db()
    topics = dict_from_rows(
        conn.execute("SELECT * FROM topics ORDER BY created_at DESC").fetchall()
    )
    conn.close()
    return topics


@app.delete("/api/topics/{topic_id}")
def delete_topic(topic_id: int):
    conn = get_db()
    conn.execute("DELETE FROM topics WHERE id = ?", (topic_id,))
    conn.commit()
    conn.close()
    return {"ok": True}


# ──────────────────────────── Node APIs ─────────────────────────────

class GenerateTitleRequest(BaseModel):
    text: str


@app.post("/api/generate-title")
def api_generate_title(body: GenerateTitleRequest):
    return {"title": generate_title(body.text)}


class AskQuestion(BaseModel):
    topic_id: int
    parent_id: int | None = None
    question: str
    node_type: str = "question"
    image_data_url: str | None = None  # base64 data URL for vision input
    response_length: str = "extend"    # normal | extend | extend_longer


@app.post("/api/ask")
def ask_question(body: AskQuestion):
    """Ask AI a question and save the Q&A as a learning node (non-streaming)."""
    rag_results = search_rag(body.question, topic_id=body.topic_id)
    answer = chat_with_rag(body.question, rag_results, body.image_data_url, body.response_length)
    conn = get_db()
    cursor = conn.execute(
        "INSERT INTO nodes (topic_id, parent_id, question, answer, node_type) VALUES (?, ?, ?, ?, ?)",
        (body.topic_id, body.parent_id, body.question, answer, body.node_type),
    )
    conn.commit()
    node_id = cursor.lastrowid
    node = dict_from_row(conn.execute("SELECT * FROM nodes WHERE id = ?", (node_id,)).fetchone())
    conn.close()
    add_to_rag(node_id, body.topic_id, body.question, answer)
    return node


@app.post("/api/ask/stream")
def ask_question_stream(body: AskQuestion):
    """Stream AI response as Server-Sent Events, then persist to DB."""
    rag_results = search_rag(body.question, topic_id=body.topic_id)

    # If this topic was spawned from a specific Q&A node, fetch that node's
    # question + answer and inject it as explicit context so the AI always
    # has the parent knowledge as grounding (not just RAG probabilistic recall).
    parent_context = ""
    conn = get_db()
    topic_row = conn.execute("SELECT source_node_id FROM topics WHERE id = ?", (body.topic_id,)).fetchone()
    if topic_row and topic_row[0]:
        src_node = conn.execute("SELECT question, answer FROM nodes WHERE id = ?", (topic_row[0],)).fetchone()
        if src_node:
            q, a = src_node[0], src_node[1]
            # Truncate answer to ~1200 chars to keep context manageable
            a_preview = a[:1200] + ("…" if len(a) > 1200 else "")
            parent_context = f"问题：{q}\n\n回答：{a_preview}"
    conn.close()

    def generate():
        full_answer = ""
        try:
            for token in stream_chat_with_rag(
                body.question, rag_results, body.image_data_url,
                body.response_length, parent_context=parent_context,
            ):
                full_answer += token
                yield f"data: {json.dumps({'token': token})}\n\n"
        except Exception as exc:
            yield f"data: {json.dumps({'error': str(exc)})}\n\n"
            return

        # Generate concise title for tree display
        # For image inputs, use vision to summarize the image content
        title = generate_title(body.question, image_data_url=body.image_data_url)

        # Persist to database after streaming completes
        conn = get_db()
        cursor = conn.execute(
            "INSERT INTO nodes (topic_id, parent_id, question, answer, node_type, title) VALUES (?, ?, ?, ?, ?, ?)",
            (body.topic_id, body.parent_id, body.question, full_answer, body.node_type, title),
        )
        conn.commit()
        node_id = cursor.lastrowid
        node = dict_from_row(conn.execute("SELECT * FROM nodes WHERE id = ?", (node_id,)).fetchone())
        conn.close()
        add_to_rag(node_id, body.topic_id, body.question, full_answer)
        yield f"data: {json.dumps({'done': True, 'node': node})}\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.get("/api/topics/{topic_id}/tree")
def get_topic_tree(topic_id: int):
    conn = get_db()
    topic = dict_from_row(conn.execute("SELECT * FROM topics WHERE id = ?", (topic_id,)).fetchone())
    if not topic:
        conn.close()
        raise HTTPException(status_code=404, detail="Topic not found")
    nodes = dict_from_rows(
        conn.execute(
            "SELECT * FROM nodes WHERE topic_id = ? ORDER BY created_at ASC", (topic_id,)
        ).fetchall()
    )
    conn.close()
    return {"topic": topic, "nodes": nodes}


@app.get("/api/topics/{topic_id}/full-tree")
def get_full_tree(topic_id: int):
    """Return the complete tree: topic nodes + all nested sub-topics recursively."""
    conn = get_db()

    def build(tid):
        topic = dict_from_row(conn.execute("SELECT * FROM topics WHERE id = ?", (tid,)).fetchone())
        if not topic:
            return None
        nodes = dict_from_rows(
            conn.execute(
                "SELECT * FROM nodes WHERE topic_id = ? ORDER BY created_at ASC", (tid,)
            ).fetchall()
        )
        sub_rows = dict_from_rows(
            conn.execute(
                "SELECT * FROM topics WHERE parent_id = ? ORDER BY created_at DESC", (tid,)
            ).fetchall()
        )
        subtopics = [s for s in (build(r["id"]) for r in sub_rows) if s]
        return {"topic": topic, "nodes": nodes, "subtopics": subtopics}

    result = build(topic_id)
    conn.close()
    if not result:
        raise HTTPException(status_code=404, detail="Topic not found")
    return result


@app.get("/api/nodes/{node_id}")
def get_node(node_id: int):
    conn = get_db()
    node = dict_from_row(conn.execute("SELECT * FROM nodes WHERE id = ?", (node_id,)).fetchone())
    conn.close()
    if not node:
        raise HTTPException(status_code=404, detail="Node not found")
    return node


# ──────────────────────────── RAG Search ────────────────────────────

class RagQuery(BaseModel):
    query: str
    topic_id: int | None = None


@app.post("/api/rag/search")
def rag_search(body: RagQuery):
    results = search_rag(body.query, topic_id=body.topic_id)
    if results:
        answer = chat_with_rag(body.query, results)
        return {"results": results, "answer": answer}
    return {"results": [], "answer": "暂无相关学习记录。请先在专题中提问学习。"}


# ──────────────────────────── File Upload ───────────────────────────

@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    """Extract plain text from an uploaded file (PDF / txt / md)."""
    filename = file.filename or "file"
    try:
        if filename.lower().endswith(".pdf"):
            import io
            from pypdf import PdfReader
            data = await file.read()
            reader = PdfReader(io.BytesIO(data))
            text = "\n\n".join(
                p.extract_text() for p in reader.pages if p.extract_text()
            )
        else:
            data = await file.read()
            text = data.decode("utf-8", errors="replace")

        if len(text) > 15000:
            text = text[:15000] + "\n\n...[文件内容已截断，仅使用前 15000 字符]"

        return {"text": text, "filename": filename}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"文件解析失败: {exc}")


# ──────────────────────────── Transcription ─────────────────────────

@app.post("/api/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    """Transcribe speech audio to text via OpenAI Whisper."""
    data = await file.read()
    suffix = os.path.splitext(file.filename or "audio.webm")[1] or ".webm"

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(data)
        tmp_path = tmp.name

    try:
        client = get_ai_client()
        with open(tmp_path, "rb") as f:
            transcript = client.audio.transcriptions.create(model="whisper-1", file=f)
        return {"text": transcript.text}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"语音识别失败: {exc}")
    finally:
        os.unlink(tmp_path)


# ──────────────────────────── TTS ───────────────────────────────────

class TTSRequest(BaseModel):
    text: str
    voice: str = "nova"


@app.post("/api/tts")
def text_to_speech(body: TTSRequest):
    """Convert text to speech (MP3) using OpenAI TTS."""
    try:
        client = get_ai_client()
        clean = body.text[:4096]
        audio = client.audio.speech.create(model="tts-1", voice=body.voice, input=clean)
        return Response(content=audio.read(), media_type="audio/mpeg")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"TTS 失败: {exc}")


# ──────────────────────────── Settings ──────────────────────────────

SETTINGS_KEYS = ["api_provider", "api_base_url", "api_key", "api_model"]


def mask_key(key: str | None) -> str:
    if not key:
        return ""
    if len(key) <= 8:
        return "****"
    return key[:3] + "..." + key[-4:]


@app.get("/api/settings")
def get_settings():
    result = {}
    for k in SETTINGS_KEYS:
        val = get_setting(k) or ""
        if k == "api_key":
            result[k] = mask_key(val)
            result["has_custom_key"] = bool(val)
        else:
            result[k] = val
    result["effective_base_url"] = get_setting("api_base_url") or os.getenv(
        "OPENAI_BASE_URL", "https://api.openai.com/v1"
    )
    result["effective_model"] = get_setting("api_model") or os.getenv("OPENAI_MODEL", "gpt-4o")
    result["has_env_key"] = bool(os.getenv("OPENAI_API_KEY"))
    return result


class SettingsUpdate(BaseModel):
    api_provider: str = ""
    api_base_url: str = ""
    api_key: str = ""
    api_model: str = ""


@app.post("/api/settings")
def update_settings(body: SettingsUpdate):
    if body.api_provider:
        set_setting("api_provider", body.api_provider)
    else:
        delete_setting("api_provider")
    if body.api_base_url:
        set_setting("api_base_url", body.api_base_url)
    else:
        delete_setting("api_base_url")
    if body.api_key:
        set_setting("api_key", body.api_key)
    if body.api_model:
        set_setting("api_model", body.api_model)
    else:
        delete_setting("api_model")
    return {"ok": True}


@app.post("/api/settings/reset")
def reset_settings():
    for k in SETTINGS_KEYS:
        delete_setting(k)
    return {"ok": True}
