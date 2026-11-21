"""Practice statistics — mirrors ios/BalletDairy/Models/Stats.swift."""
from __future__ import annotations

from collections import Counter
from datetime import date, timedelta

from .catalog import Catalog
from .db import Entry


def _d(s: str) -> date:
    return date.fromisoformat(s)


def longest_run(days: set[date]) -> int:
    best = 0
    for d in days:
        if d - timedelta(days=1) in days:
            continue
        n = 1
        while d + timedelta(days=n) in days:
            n += 1
        best = max(best, n)
    return best


def current_run(days: set[date], today: date) -> int:
    cur = today
    if cur not in days:
        cur = today - timedelta(days=1)
        if cur not in days:
            return 0
    n = 0
    while cur in days:
        n += 1
        cur -= timedelta(days=1)
    return n


def compute(entries: list[Entry], catalog: Catalog, start: date | None = None, end: date | None = None,
            today: date | None = None, weeks: int = 8) -> dict:
    today = today or date.today()
    practiced = [e for e in entries if e.is_practiced]
    in_range = [e for e in practiced if (start is None or _d(e.day) >= start) and (end is None or _d(e.day) <= end)]

    moves = Counter()
    for e in in_range:
        moves.update(set(e.movement_ids))
    cats = Counter()
    for mid, n in moves.items():
        m = catalog.get(mid)
        if m:
            cats[m["category"]] += n
    types = Counter(e.class_type for e in in_range)

    days = {_d(e.day) for e in practiced}
    week0 = today - timedelta(days=today.weekday())  # Monday
    weekly = []
    for back in reversed(range(weeks)):
        ws = week0 - timedelta(weeks=back)
        we = ws + timedelta(days=7)
        mins = sum(e.duration_minutes for e in practiced if ws <= _d(e.day) < we)
        weekly.append({"week_start": ws.isoformat(), "minutes": mins})

    top = sorted(moves.items(), key=lambda kv: (-kv[1], kv[0]))[:6]
    return {
        "classes": len(in_range),
        "minutes": sum(e.duration_minutes for e in in_range),
        "hours": round(sum(e.duration_minutes for e in in_range) / 60, 1),
        "current_streak": current_run(days, today),
        "longest_streak": longest_run(days),
        "unique_movements": len(moves),
        "top_movements": [{"id": k, "name": (catalog.get(k) or {}).get("name", k), "count": v} for k, v in top],
        "by_category": [{"id": c["id"], "name": c["name"], "count": cats[c["id"]]} for c in catalog.categories if cats[c["id"]]],
        "by_class_type": [{"type": k, "count": v} for k, v in types.most_common()],
        "weekly": weekly,
    }
