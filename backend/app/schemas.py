"""Wire format — matches EntryDTO in ios/BalletDairy/Services/APIClient.swift."""
from __future__ import annotations

from datetime import date, datetime, timezone
from uuid import UUID

from pydantic import BaseModel, Field, field_serializer, field_validator

from .db import Entry


class EntryIn(BaseModel):
    id: UUID
    day: date
    text: str = ""
    class_type: str = "Class"
    duration_minutes: int = Field(0, ge=0, le=24 * 60)
    energy: int = Field(0, ge=0, le=5)
    movement_ids: list[str] = []
    drawing: str | None = None
    updated_at: datetime
    deleted: bool = False

    @field_validator("updated_at")
    @classmethod
    def _aware(cls, v: datetime) -> datetime:
        return v if v.tzinfo else v.replace(tzinfo=timezone.utc)

    def to_entry(self) -> Entry:
        return Entry(id=str(self.id).upper(), day=self.day.isoformat(), text=self.text, class_type=self.class_type,
                     duration_minutes=self.duration_minutes, energy=self.energy,
                     movement_ids=list(dict.fromkeys(self.movement_ids)), drawing=self.drawing,
                     updated_at=self.updated_at, deleted=self.deleted)


def _iso_ms(d: datetime) -> str:
    """Millisecond precision — what Apple's ISO8601DateFormatter parses reliably."""
    return d.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


class EntryOut(EntryIn):
    @field_serializer("updated_at")
    def _ser(self, v: datetime) -> str:
        return _iso_ms(v)

    @classmethod
    def of(cls, e: Entry) -> "EntryOut":
        return cls(id=UUID(e.id), day=date.fromisoformat(e.day), text=e.text, class_type=e.class_type,
                   duration_minutes=e.duration_minutes, energy=e.energy, movement_ids=e.movement_ids,
                   drawing=e.drawing, updated_at=e.updated_at, deleted=e.deleted)


class SyncIn(BaseModel):
    since: datetime | None = None
    entries: list[EntryIn] = []


class SyncOut(BaseModel):
    server_time: datetime
    entries: list[EntryOut]

    @field_serializer("server_time")
    def _ser(self, v: datetime) -> str:
        return _iso_ms(v)
