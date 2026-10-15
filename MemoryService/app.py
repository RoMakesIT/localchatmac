from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

import chromadb
from chromadb.config import Settings
from fastapi import FastAPI
from pydantic import BaseModel, Field
from sentence_transformers import SentenceTransformer


APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "Lantern" / "memory"
COLLECTION_NAME = "conversation_memory"
EMBEDDING_MODEL_NAME = "all-MiniLM-L6-v2"


class StoreRequest(BaseModel):
    conversation_id: str = Field(min_length=1)
    project_id: str = Field(default="__global__", min_length=1)
    user_message: str = Field(min_length=1)
    assistant_reply: str = Field(min_length=1)


class SearchRequest(BaseModel):
    query: str = Field(min_length=1)
    top_k: int = Field(default=5, ge=1, le=5)
    project_id: str = Field(default="__global__", min_length=1)


class SearchResult(BaseModel):
    id: str
    conversation_id: str
    timestamp: str
    snippet: str
    user_message: str
    assistant_reply: str
    distance: float | None = None
    project_id: str = "__global__"


class DeleteConversationRequest(BaseModel):
    conversation_id: str = Field(min_length=1)


class MoveConversationRequest(BaseModel):
    conversation_id: str = Field(min_length=1)
    project_id: str = Field(min_length=1)


class MemoryService:
    def __init__(self) -> None:
        APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
        self.client = chromadb.PersistentClient(
            path=str(APP_SUPPORT_DIR / "chroma"),
            settings=Settings(anonymized_telemetry=False),
        )
        self.collection = self.client.get_or_create_collection(name=COLLECTION_NAME)
        self.embedder = SentenceTransformer(EMBEDDING_MODEL_NAME)

    def _embed(self, text: str) -> list[float]:
        return self.embedder.encode(text, normalize_embeddings=True).tolist()

    @staticmethod
    def _document_text(user_message: str, assistant_reply: str) -> str:
        return f"User: {user_message}\nAssistant: {assistant_reply}"

    def store_turn(self, conversation_id: str, project_id: str, user_message: str, assistant_reply: str) -> dict[str, Any]:
        memory_id = str(uuid4())
        timestamp = datetime.now(timezone.utc).isoformat()
        document = self._document_text(user_message, assistant_reply)
        embedding = self._embed(document)

        self.collection.upsert(
            ids=[memory_id],
            documents=[document],
            embeddings=[embedding],
            metadatas=[
                {
                    "conversation_id": conversation_id,
                    "project_id": project_id,
                    "timestamp": timestamp,
                    "user_message": user_message,
                    "assistant_reply": assistant_reply,
                }
            ],
        )
        return {"id": memory_id, "timestamp": timestamp}

    def search(self, query: str, top_k: int, project_id: str) -> list[SearchResult]:
        # Scope candidates before nearest-neighbor retrieval. Filtering a global
        # top-k afterwards lets other projects crowd out relevant local memories.
        if project_id == "__global__":
            # Pre-project memories have no project_id and historically belong to
            # the global workspace. Select those IDs alongside explicit globals
            # rather than dropping them or exposing another project's records.
            scoped = self.collection.get(include=["metadatas"])
            candidate_ids = [
                memory_id
                for memory_id, metadata in zip(scoped.get("ids", []), scoped.get("metadatas", []))
                if str((metadata or {}).get("project_id", "__global__")) == project_id
            ]
            query_scope = {"ids": candidate_ids}
        else:
            query_scope = {"where": {"project_id": project_id}}
            scoped = self.collection.get(where=query_scope["where"], include=[])
            candidate_ids = scoped.get("ids", [])
        available = len(candidate_ids)
        if available == 0:
            return []
        embedding = self._embed(query)
        results = self.collection.query(
            query_embeddings=[embedding],
            n_results=min(available, top_k),
            include=["documents", "metadatas", "distances"],
            **query_scope,
        )

        ids = results.get("ids", [[]])[0]
        metadatas = results.get("metadatas", [[]])[0]
        documents = results.get("documents", [[]])[0]
        distances = results.get("distances", [[]])[0]

        hits: list[SearchResult] = []
        for idx, memory_id in enumerate(ids):
            metadata = metadatas[idx] or {}
            stored_project_id = str(metadata.get("project_id", "__global__"))
            if stored_project_id != project_id:
                continue
            document = documents[idx] or ""
            snippet = document.strip()
            hits.append(
                SearchResult(
                    id=memory_id,
                    conversation_id=str(metadata.get("conversation_id", "")),
                    timestamp=str(metadata.get("timestamp", "")),
                    snippet=snippet,
                    user_message=str(metadata.get("user_message", "")),
                    assistant_reply=str(metadata.get("assistant_reply", "")),
                    distance=float(distances[idx]) if idx < len(distances) and distances[idx] is not None else None,
                    project_id=stored_project_id,
                )
            )
            if len(hits) >= top_k:
                break
        return hits

    def list_recent(self, limit: int = 50) -> list[SearchResult]:
        payload = self.collection.get(include=["documents", "metadatas"], limit=limit)
        ids = payload.get("ids", [])
        metadatas = payload.get("metadatas", [])
        documents = payload.get("documents", [])

        rows: list[SearchResult] = []
        for idx, memory_id in enumerate(ids):
            metadata = metadatas[idx] or {}
            document = documents[idx] or ""
            rows.append(
                SearchResult(
                    id=memory_id,
                    conversation_id=str(metadata.get("conversation_id", "")),
                    timestamp=str(metadata.get("timestamp", "")),
                    snippet=document.strip(),
                    user_message=str(metadata.get("user_message", "")),
                    assistant_reply=str(metadata.get("assistant_reply", "")),
                    distance=None,
                    project_id=str(metadata.get("project_id", "__global__")),
                )
            )

        rows.sort(key=lambda item: item.timestamp, reverse=True)
        return rows[:limit]

    def delete_conversation(self, conversation_id: str) -> int:
        payload = self.collection.get(
            where={"conversation_id": conversation_id},
            include=["metadatas"],
        )
        ids = payload.get("ids", [])
        if not ids:
            return 0
        self.collection.delete(ids=ids)
        return len(ids)

    def move_conversation(self, conversation_id: str, project_id: str) -> int:
        payload = self.collection.get(
            where={"conversation_id": conversation_id},
            include=["metadatas"],
        )
        ids = payload.get("ids", [])
        metadatas = payload.get("metadatas", [])
        if not ids:
            return 0
        updated = []
        for metadata in metadatas:
            row = dict(metadata or {})
            row["project_id"] = project_id
            updated.append(row)
        self.collection.update(ids=ids, metadatas=updated)
        return len(ids)

    def delete_orphan_memories(self) -> int:
        payload = self.collection.get(include=["metadatas"])
        ids = payload.get("ids", [])
        metadatas = payload.get("metadatas", [])

        orphan_ids: list[str] = []
        for idx, memory_id in enumerate(ids):
            metadata = metadatas[idx] or {}
            conversation_id = str(metadata.get("conversation_id", "")).strip()
            if not conversation_id:
                orphan_ids.append(memory_id)

        if not orphan_ids:
            return 0

        self.collection.delete(ids=orphan_ids)
        return len(orphan_ids)

    def health(self) -> dict[str, Any]:
        count = self.collection.count()
        return {
            "status": "ok",
            "collection": COLLECTION_NAME,
            "count": count,
            "embedding_model": EMBEDDING_MODEL_NAME,
            "storage_path": str(APP_SUPPORT_DIR),
        }


memory_service = MemoryService()
app = FastAPI(title="Lantern Memory Service")


@app.get("/health")
def health() -> dict[str, Any]:
    return memory_service.health()


@app.post("/store")
def store(request: StoreRequest) -> dict[str, Any]:
    stored = memory_service.store_turn(
        conversation_id=request.conversation_id.strip(),
        project_id=request.project_id.strip(),
        user_message=request.user_message.strip(),
        assistant_reply=request.assistant_reply.strip(),
    )
    return {"ok": True, **stored}


@app.post("/search")
def search(request: SearchRequest) -> dict[str, Any]:
    results = memory_service.search(
        query=request.query.strip(),
        top_k=request.top_k,
        project_id=request.project_id.strip(),
    )
    return {"ok": True, "results": [result.model_dump() for result in results]}


@app.get("/memories")
def memories(limit: int = 50) -> dict[str, Any]:
    results = memory_service.list_recent(limit=max(1, min(limit, 100)))
    return {"ok": True, "results": [result.model_dump() for result in results]}


@app.post("/delete_conversation")
def delete_conversation(request: DeleteConversationRequest) -> dict[str, Any]:
    deleted = memory_service.delete_conversation(request.conversation_id.strip())
    return {"ok": True, "deleted": deleted}


@app.post("/move_conversation")
def move_conversation(request: MoveConversationRequest) -> dict[str, Any]:
    moved = memory_service.move_conversation(
        request.conversation_id.strip(),
        request.project_id.strip(),
    )
    return {"ok": True, "moved": moved}


@app.post("/delete_orphans")
def delete_orphans() -> dict[str, Any]:
    deleted = memory_service.delete_orphan_memories()
    return {"ok": True, "deleted": deleted}
