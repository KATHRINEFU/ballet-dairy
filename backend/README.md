# Ballet Diary — Backend

A small FastAPI + SQLite service that stores diary pages, syncs them between devices, computes practice statistics and serves the movement répertoire.

```
backend/
├── app/
│   ├── main.py        API routes (FastAPI)
│   ├── db.py          SQLite storage + sync logic (stdlib only)
│   ├── stats.py       classes, hours, streaks, top movements…
│   ├── catalog.py     loads data/movements.json, search
│   └── schemas.py     request/response models (match the iOS EntryDTO)
├── data/              movements.json, poses.json (generated, don't hand-edit)
├── scripts/           build_movements.py, build_poses.py  ← source of truth
├── tests/             test_core.py (no web deps), test_api.py
└── requirements.txt
```

## Run it locally

You need **Python 3.10 or newer** (`python3 --version`).

```bash
cd backend

# 1. create a virtual environment (once)
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate

# 2. install dependencies (once, or when requirements.txt changes)
pip install -r requirements.txt

# 3. start the server with auto-reload
uvicorn app.main:app --reload --port 8000
```

Then open **http://127.0.0.1:8000/docs**. It's an interactive page where you can try every endpoint.

The database is a single file, `ballet_diary.sqlite3`, created in `backend/` on first start. To start fresh, stop the server and delete that file. To keep it somewhere else:

```bash
BALLET_DB=/path/to/diary.sqlite3 uvicorn app.main:app --reload --port 8000
```

Next time you just need:

```bash
cd backend && source .venv/bin/activate && uvicorn app.main:app --reload --port 8000
```

## Connect the iPhone app

| Where the app runs | Server command | Server address in the app (⚙︎ Settings) |
|---|---|---|
| iOS Simulator on this Mac | `uvicorn app.main:app --reload --port 8000` | `http://127.0.0.1:8000` (the default) |
| A real iPhone on the same Wi-Fi | `uvicorn app.main:app --reload --host 0.0.0.0 --port 8000` | `http://<your Mac's IP>:8000` |

- Find your Mac's IP with `ipconfig getifaddr en0` (or *System Settings → Wi-Fi → Details*).
- `--host 0.0.0.0` lets other devices on your network reach the server. If macOS asks whether Python may accept incoming connections, click **Allow**.
- The first time the iPhone app syncs, iOS asks for *Local Network* permission. Allow it.

Then tap **Sync now** in the app's Settings. You should see something like "Sent 5 · received 0".

## Try it from the terminal

```bash
curl http://127.0.0.1:8000/health
curl "http://127.0.0.1:8000/movements?q=pirouette"
curl "http://127.0.0.1:8000/movements?category=turns&level=2"

# create or update a diary page (pages belong to the X-Device-ID you send)
curl -X PUT http://127.0.0.1:8000/entries/6F9619FF-8B86-D011-B42D-00C04FC964FF \
  -H "Content-Type: application/json" -H "X-Device-ID: my-phone" \
  -d '{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","day":"2026-11-20","text":"Clean double!",
       "class_type":"Class","duration_minutes":90,"energy":4,
       "movement_ids":["double_pirouette","grand_jete"],"updated_at":"2026-11-20T18:00:00Z"}'

curl -H "X-Device-ID: my-phone" http://127.0.0.1:8000/entries
curl -H "X-Device-ID: my-phone" http://127.0.0.1:8000/stats
```

## API

| Method & path | What it does |
|---|---|
| `GET /health` | `{"ok": true}` |
| `GET /categories` | the 9 movement categories |
| `GET /movements?category=&level=&q=` | search the répertoire (ignores accents: `developpe` finds *Développé*) |
| `GET /movements/{id}` | one movement, with cues, muscles and animation keyframes |
| `GET /entries?start=&end=` | your diary pages (dates as `YYYY-MM-DD`) |
| `GET /entries/{id}` | one page |
| `PUT /entries/{id}` | create or update a page (the newer `updated_at` wins) |
| `DELETE /entries/{id}` | delete a page (kept as a deletion so other devices find out) |
| `POST /sync` | send your changes, get everything that changed since `since` |
| `GET /stats?start=&end=` | classes, hours, streaks, top movements, categories, weekly hours |

Every `/entries`, `/sync` and `/stats` call is scoped by the **`X-Device-ID`** header. The app sends a random ID it creates on first launch. This is a stand-in for real accounts: add proper sign-in (e.g. Sign in with Apple) before real users.

## Tests

```bash
cd backend && source .venv/bin/activate
pytest -q
```

`test_core.py` covers storage, sync conflicts, deletions and statistics, and needs nothing beyond Python. `test_api.py` exercises the HTTP endpoints. It's skipped automatically if FastAPI isn't installed.

## Changing movements or poses

`data/movements.json` and `data/poses.json` are generated. Edit the Python scripts, then regenerate. Both scripts write the backend copy **and** the iOS app's copy, so they never drift apart:

```bash
# from the project root (BalletDairy/), with the venv active
pip install numpy scipy matplotlib       # only needed for build_poses.py

python3 backend/scripts/build_poses.py                                    # poses → JSON
python3 backend/scripts/build_poses.py --preview /tmp/p.png retire air_split   # stick-figure check
python3 backend/scripts/build_movements.py                                # validates + writes movements
```

`build_movements.py` refuses to write if a movement uses a pose, muscle or category that doesn't exist.

## Troubleshooting

- **`Address already in use`**: another server is on port 8000. Use `--port 8001` (and update the app's server address), or stop the other process: `lsof -ti :8000 | xargs kill`.
- **`ModuleNotFoundError: app`**: run `uvicorn` from inside `backend/`, not from the project root.
- **The iPhone can't connect**: check that you used `--host 0.0.0.0`, that both devices are on the same Wi-Fi, that the address in the app has `http://` and the port, and that the Mac's firewall allowed Python.
- **Sync says "received 0" on a second device**: both devices must use the same `X-Device-ID` to share a diary. Today each phone gets its own, which will be replaced by real sign-in.
