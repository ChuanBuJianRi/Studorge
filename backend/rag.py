"""RAG module using ChromaDB for vector storage and retrieval."""
import os
import platform as _platform
import chromadb
from chromadb.config import Settings


def _default_data_dir() -> str:
    system = _platform.system()
    if system == "Windows":
        base = os.environ.get("APPDATA") or os.path.expanduser("~")
        return os.path.join(base, "Studorge", "data")
    elif system == "Darwin":
        return os.path.join(os.path.expanduser("~"), "Library", "Application Support", "Studorge", "data")
    else:
        xdg = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
        return os.path.join(xdg, "Studorge", "data")


_DATA_DIR = os.environ.get("STUDORGE_DATA_DIR") or _default_data_dir()
CHROMA_PATH = os.path.join(_DATA_DIR, "chroma_db")


def get_chroma_client():
    os.makedirs(CHROMA_PATH, exist_ok=True)
    return chromadb.PersistentClient(path=CHROMA_PATH)


def get_collection():
    client = get_chroma_client()
    return client.get_or_create_collection(
        name="learning_nodes",
        metadata={"hnsw:space": "cosine"},
    )


def add_to_rag(node_id: int, topic_id: int, question: str, answer: str):
    """Add a Q&A pair to the vector database."""
    collection = get_collection()
    doc_text = f"问题: {question}\n回答: {answer}"
    collection.upsert(
        ids=[str(node_id)],
        documents=[doc_text],
        metadatas=[{"topic_id": topic_id, "question": question, "node_id": node_id}],
    )


def search_rag(query: str, topic_id: int = None, top_k: int = 5) -> list[dict]:
    """Search the vector database for relevant Q&A pairs."""
    collection = get_collection()
    if collection.count() == 0:
        return []
    where = {"topic_id": topic_id} if topic_id else None
    results = collection.query(
        query_texts=[query],
        n_results=min(top_k, collection.count()),
        where=where if where else None,
    )
    items = []
    for i, doc in enumerate(results["documents"][0]):
        items.append({
            "document": doc,
            "metadata": results["metadatas"][0][i],
            "distance": results["distances"][0][i] if results.get("distances") else None,
        })
    return items
