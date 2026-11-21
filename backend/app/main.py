"""Ballet Diary API.

Run:   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000     (from backend/)
Docs:  http://127.0.0.1:8000/docs
"""
from __future__ import annotations

import os
from datetime import date
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from . import stats as stats_mod
from .catalog import Catalog, load_catalog
from .db import Store
from .schemas import EntryIn, EntryOut, SyncIn, SyncOut

app = FastAPI(title="Ballet Diary", version="1.0.0",
              description="Diary pages, practice statistics and the movement répertoire.")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

_store: Store | None = None


def get_store() -> Store:
    global _store
    if _store is None:
        _store = Store(os.environ.get("BALLET_DB", "ballet_diary.sqlite3"))
    return _store


def get_catalog() -> Catalog:
    return load_catalog()


def device(x_device_id: str = Header("default", alias="X-Device-ID")) -> str:
    """Pages are scoped by device ID (use the same ID on several devices to share a diary)."""
    return x_device_id.strip() or "default"


@app.get("/health")
def health() -> dict:
    return {"ok": True}


# ── movements ──
@app.get("/categories")
def categories(cat: Catalog = Depends(get_catalog)) -> list[dict]:
    return cat.categories


@app.get("/movements")
def movements(category: str | None = None, level: int | None = Query(None, ge=1, le=4), q: str = "",
              cat: Catalog = Depends(get_catalog)) -> list[dict]:
    return cat.search(category, level, q)


@app.get("/movements/{movement_id}")
def movement(movement_id: str, cat: Catalog = Depends(get_catalog)) -> dict:
    m = cat.get(movement_id)
    if not m:
        raise HTTPException(404, "No such movement")
    return m


# ── entries ──
@app.get("/entries", response_model=list[EntryOut])
def list_entries(start: date | None = None, end: date | None = None,
                 store: Store = Depends(get_store), dev: str = Depends(device)):
    return [EntryOut.of(e) for e in store.list(dev, start and start.isoformat(), end and end.isoformat())]


@app.get("/entries/{entry_id}", response_model=EntryOut)
def get_entry(entry_id: UUID, store: Store = Depends(get_store), dev: str = Depends(device)):
    e = store.get(dev, str(entry_id).upper())
    if not e or e.deleted:
        raise HTTPException(404, "No such page")
    return EntryOut.of(e)


@app.put("/entries/{entry_id}", response_model=EntryOut)
def put_entry(entry_id: UUID, body: EntryIn, store: Store = Depends(get_store), dev: str = Depends(device)):
    if body.id != entry_id:
        raise HTTPException(400, "id in path and body differ")
    store.upsert(dev, body.to_entry())
    return EntryOut.of(store.get(dev, str(entry_id).upper()))


@app.delete("/entries/{entry_id}", status_code=204)
def delete_entry(entry_id: UUID, store: Store = Depends(get_store), dev: str = Depends(device)):
    if not store.delete(dev, str(entry_id).upper()):
        raise HTTPException(404, "No such page")


# ── sync & stats ──
@app.post("/sync", response_model=SyncOut)
def sync(body: SyncIn, store: Store = Depends(get_store), dev: str = Depends(device)):
    server_time, changed = store.sync(dev, body.since, [e.to_entry() for e in body.entries])
    return SyncOut(server_time=server_time, entries=[EntryOut.of(e) for e in changed])


@app.get("/stats")
def stats(start: date | None = None, end: date | None = None, today: date | None = None,
          store: Store = Depends(get_store), dev: str = Depends(device), cat: Catalog = Depends(get_catalog)) -> dict:
    return stats_mod.compute(store.list(dev), cat, start, end, today=today)
