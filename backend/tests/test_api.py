"""HTTP layer. Skipped automatically if FastAPI isn't installed."""
import sys
from pathlib import Path
from uuid import uuid4

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
pytest.importorskip("fastapi")
pytest.importorskip("httpx")

from fastapi.testclient import TestClient  # noqa: E402

from app import main  # noqa: E402
from app.db import Store  # noqa: E402


@pytest.fixture()
def client():
    main.app.dependency_overrides[main.get_store] = lambda s=Store(): s
    yield TestClient(main.app, headers={"X-Device-ID": "test-phone"})
    main.app.dependency_overrides.clear()


def page(**kw):
    p = {"id": str(uuid4()).upper(), "day": "2026-11-20", "text": "Pirouettes!", "class_type": "Class",
         "duration_minutes": 90, "energy": 4, "movement_ids": ["pirouette_en_dehors"],
         "updated_at": "2026-11-20T18:00:00.000Z"}
    p.update(kw)
    return p


def test_health_and_movements(client):
    assert client.get("/health").json() == {"ok": True}
    assert len(client.get("/movements").json()) >= 100
    assert client.get("/movements", params={"q": "pas de chat"}).json()[0]["id"] == "pas_de_chat"
    assert client.get("/movements/nope").status_code == 404


def test_entry_crud(client):
    p = page()
    r = client.put(f"/entries/{p['id']}", json=p)
    assert r.status_code == 200 and r.json()["duration_minutes"] == 90
    assert len(client.get("/entries").json()) == 1
    assert client.delete(f"/entries/{p['id']}").status_code == 204
    assert client.get("/entries").json() == []


def test_sync_and_stats(client):
    r = client.post("/sync", json={"since": None, "entries": [page(), page(day="2026-11-19", duration_minutes=60)]})
    assert r.status_code == 200 and r.json()["entries"] == []
    assert r.json()["server_time"].endswith("Z")
    s = client.get("/stats", params={"today": "2026-11-20"}).json()
    assert s["classes"] == 2 and s["hours"] == 2.5 and s["current_streak"] == 2
