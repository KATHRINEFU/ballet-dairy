"""Storage, sync and statistics — no web framework needed."""
import json
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.catalog import load_catalog  # noqa: E402
from app.db import Entry, Store  # noqa: E402
from app import stats  # noqa: E402

T0 = datetime(2026, 11, 1, 12, tzinfo=timezone.utc)


def e(i, day, mins=60, moves=("battement_tendu",), t=T0, **kw):
    return Entry(id=f"ID-{i}", day=day, duration_minutes=mins, movement_ids=list(moves), updated_at=t, **kw)


def test_catalog_is_complete_and_consistent():
    cat = load_catalog()
    assert len(cat.movements) >= 100
    ids = [m["id"] for m in cat.movements]
    assert len(ids) == len(set(ids))
    poses = json.loads((ROOT / "data/poses.json").read_text())
    for m in cat.movements:
        assert m["cues"] and m["muscles"]["primary"]
        for k in m["animation"]["keys"]:
            assert k["l"] in poses["legs"] and k["a"] in poses["arms"] and k["t"] in poses["torso"]


def test_catalog_search_is_accent_insensitive():
    cat = load_catalog()
    assert any(m["id"] == "developpe" for m in cat.search(q="developpe"))
    assert all(m["category"] == "turns" for m in cat.search(category="turns"))
    assert cat.search(q="lame duck")


def test_upsert_last_writer_wins():
    s = Store()
    assert s.upsert("d", e(1, "2026-11-01", mins=60, t=T0))
    assert not s.upsert("d", e(1, "2026-11-01", mins=30, t=T0 - timedelta(minutes=1)))  # older loses
    assert s.get("d", "ID-1").duration_minutes == 60
    assert s.upsert("d", e(1, "2026-11-01", mins=90, t=T0 + timedelta(minutes=1)))
    assert s.get("d", "ID-1").duration_minutes == 90


def test_devices_are_isolated():
    s = Store()
    s.upsert("a", e(1, "2026-11-01"))
    assert s.get("b", "ID-1") is None
    assert s.list("b") == []


def test_soft_delete_propagates_through_sync():
    s = Store()
    s.upsert("d", e(1, "2026-11-01"))
    t, _ = s.sync("d", None, [])
    assert s.delete("d", "ID-1")
    assert s.list("d") == []
    _, changed = s.sync("d", t, [])
    assert [c.id for c in changed] == ["ID-1"] and changed[0].deleted


def test_sync_round_trip_between_two_phones():
    s = Store()
    t_a, out = s.sync("me", None, [e(1, "2026-11-01"), e(2, "2026-11-02")])
    assert out == []  # nothing new for the sender
    t_b, out_b = s.sync("me", None, [])  # a second phone pulls everything
    assert {x.id for x in out_b} == {"ID-1", "ID-2"}
    s.sync("me", t_b, [e(2, "2026-11-02", mins=120, t=T0 + timedelta(hours=1))])  # phone B edits
    _, back = s.sync("me", t_a, [])  # phone A learns about it
    assert [(x.id, x.duration_minutes) for x in back] == [("ID-2", 120)]


def test_streaks():
    d = date(2026, 11, 20)
    days = {d - timedelta(days=i) for i in (0, 1, 2, 5, 6)}
    assert stats.current_run(days, d) == 3
    assert stats.longest_run(days) == 3
    assert stats.current_run({d - timedelta(days=1)}, d) == 1  # yesterday still counts
    assert stats.current_run({d - timedelta(days=2)}, d) == 0


def test_stats_summary():
    cat = load_catalog()
    entries = [
        e(1, "2026-11-18", mins=90, moves=("battement_tendu", "grand_jete")),
        e(2, "2026-11-19", mins=60, moves=("battement_tendu",)),
        e(3, "2026-11-20", mins=0, moves=()),  # blank page: not a class
    ]
    s = stats.compute(entries, cat, today=date(2026, 11, 20))
    assert s["classes"] == 2 and s["minutes"] == 150 and s["hours"] == 2.5
    assert s["top_movements"][0] == {"id": "battement_tendu", "name": "Battement tendu", "count": 2}
    assert {c["id"] for c in s["by_category"]} == {"barre", "grand_allegro"}
    assert s["current_streak"] == 2
    assert len(s["weekly"]) == 8 and s["weekly"][-1]["minutes"] == 150
