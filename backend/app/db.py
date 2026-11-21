"""SQLite storage for diary entries (stdlib only, so it is easy to test and deploy)."""
from __future__ import annotations

import json
import sqlite3
import threading
from contextlib import contextmanager
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

SCHEMA = """
CREATE TABLE IF NOT EXISTS entries (
    id               TEXT PRIMARY KEY,
    device_id        TEXT NOT NULL,
    day              TEXT NOT NULL,          -- yyyy-mm-dd
    text             TEXT NOT NULL DEFAULT '',
    class_type       TEXT NOT NULL DEFAULT 'Class',
    duration_minutes INTEGER NOT NULL DEFAULT 0,
    energy           INTEGER NOT NULL DEFAULT 0,
    movement_ids     TEXT NOT NULL DEFAULT '[]',
    drawing          TEXT,
    updated_at       TEXT NOT NULL,          -- client clock (last-writer-wins)
    changed_at       TEXT NOT NULL,          -- server clock (what changed since?)
    deleted          INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS entries_device_day ON entries(device_id, day);
CREATE INDEX IF NOT EXISTS entries_device_changed ON entries(device_id, changed_at);
"""


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def to_iso(d: datetime) -> str:
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.astimezone(timezone.utc).isoformat(timespec="microseconds")


def from_iso(s: str) -> datetime:
    d = datetime.fromisoformat(s.replace("Z", "+00:00"))
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


@dataclass
class Entry:
    id: str
    day: str
    text: str = ""
    class_type: str = "Class"
    duration_minutes: int = 0
    energy: int = 0
    movement_ids: list[str] = field(default_factory=list)
    drawing: str | None = None
    updated_at: datetime = field(default_factory=utcnow)
    deleted: bool = False

    @property
    def is_practiced(self) -> bool:
        return not self.deleted and (self.duration_minutes > 0 or bool(self.movement_ids))

    def to_dict(self) -> dict:
        d = asdict(self)
        d["updated_at"] = to_iso(self.updated_at)
        return d


class Store:
    def __init__(self, path: str | Path = ":memory:"):
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(str(path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.executescript(SCHEMA)

    @contextmanager
    def _tx(self) -> Iterator[sqlite3.Connection]:
        with self._lock:
            try:
                yield self._conn
                self._conn.commit()
            except Exception:
                self._conn.rollback()
                raise

    @staticmethod
    def _row(r: sqlite3.Row) -> Entry:
        return Entry(
            id=r["id"], day=r["day"], text=r["text"], class_type=r["class_type"],
            duration_minutes=r["duration_minutes"], energy=r["energy"],
            movement_ids=json.loads(r["movement_ids"]), drawing=r["drawing"],
            updated_at=from_iso(r["updated_at"]), deleted=bool(r["deleted"]),
        )

    # ── reads ──
    def get(self, device_id: str, entry_id: str) -> Entry | None:
        with self._tx() as c:
            r = c.execute("SELECT * FROM entries WHERE device_id=? AND id=?", (device_id, entry_id)).fetchone()
        return self._row(r) if r else None

    def list(self, device_id: str, start: str | None = None, end: str | None = None,
             include_deleted: bool = False) -> list[Entry]:
        q = "SELECT * FROM entries WHERE device_id=?"
        args: list = [device_id]
        if start: q += " AND day>=?"; args.append(start)
        if end: q += " AND day<=?"; args.append(end)
        if not include_deleted: q += " AND deleted=0"
        q += " ORDER BY day, updated_at"
        with self._tx() as c:
            return [self._row(r) for r in c.execute(q, args).fetchall()]

    def changed_since(self, device_id: str, since: datetime | None) -> list[Entry]:
        with self._tx() as c:
            if since is None:
                rows = c.execute("SELECT * FROM entries WHERE device_id=? ORDER BY changed_at", (device_id,)).fetchall()
            else:
                rows = c.execute("SELECT * FROM entries WHERE device_id=? AND changed_at>? ORDER BY changed_at",
                                 (device_id, to_iso(since))).fetchall()
        return [self._row(r) for r in rows]

    # ── writes ──
    def upsert(self, device_id: str, e: Entry, *, force: bool = False) -> bool:
        """Write if newer than what we hold (last-writer-wins on updated_at). Returns True if stored."""
        with self._tx() as c:
            cur = c.execute("SELECT updated_at FROM entries WHERE device_id=? AND id=?", (device_id, e.id)).fetchone()
            if cur and not force and from_iso(cur["updated_at"]) >= e.updated_at:
                return False
            c.execute(
                """INSERT INTO entries (id, device_id, day, text, class_type, duration_minutes, energy,
                                        movement_ids, drawing, updated_at, changed_at, deleted)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                   ON CONFLICT(id) DO UPDATE SET
                     day=excluded.day, text=excluded.text, class_type=excluded.class_type,
                     duration_minutes=excluded.duration_minutes, energy=excluded.energy,
                     movement_ids=excluded.movement_ids, drawing=excluded.drawing,
                     updated_at=excluded.updated_at, changed_at=excluded.changed_at, deleted=excluded.deleted""",
                (e.id, device_id, e.day, e.text, e.class_type, e.duration_minutes, e.energy,
                 json.dumps(e.movement_ids), e.drawing, to_iso(e.updated_at), to_iso(utcnow()), int(e.deleted)),
            )
            return True

    def delete(self, device_id: str, entry_id: str) -> bool:
        """Soft delete so other devices learn about it on their next sync."""
        e = self.get(device_id, entry_id)
        if not e or e.deleted:
            return False
        e.deleted = True
        e.updated_at = utcnow()
        return self.upsert(device_id, e, force=True)

    def sync(self, device_id: str, since: datetime | None, incoming: list[Entry]) -> tuple[datetime, list[Entry]]:
        """Apply the client's changes, then return everything that changed on the server since `since`,
        minus the versions the client has just sent us."""
        for e in incoming:
            self.upsert(device_id, e)
        server_time = utcnow()
        sent_versions = {(e.id, to_iso(e.updated_at)) for e in incoming}
        out = [e for e in self.changed_since(device_id, since)
               if (e.id, to_iso(e.updated_at)) not in sent_versions]
        return server_time, out
