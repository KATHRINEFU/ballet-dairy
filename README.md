# Ballet Diary 🎀

A ballet practice diary for iPhone: a hand-drawn notebook, a practice calendar with statistics, and a répertoire of 128 movements, each animated on a 3D dancer with the working muscles highlighted.

```
BalletDairy/
├── ios/                      SwiftUI app (iOS 26+, Liquid Glass)
│   ├── BalletDairy.xcodeproj
│   └── BalletDairy/
│       ├── App/              entry point, tab bar
│       ├── Design/           palette, type, hand-drawn shape kit, paper, glass components
│       ├── Models/           SwiftData DiaryEntry, movement catalogue, statistics
│       ├── Features/
│       │   ├── Diary/        home notebook page, week strip, movement picker, PencilKit sketches
│       │   ├── Calendar/     hand-circled month, stats tiles, Swift Charts
│       │   ├── Library/      répertoire grid + movement detail
│       │   ├── Dancer/       skeleton, kinematics, animator, SceneKit stage, 2D pose sketches
│       │   └── Settings/
│       ├── Services/         API client, sync, sample data
│       └── Resources/        movements.json, poses.json (generated, see below)
└── backend/                  FastAPI + SQLite
    ├── app/                  API, storage, sync, stats, catalogue
    ├── data/                 movements.json, poses.json
    ├── scripts/              build_movements.py, build_poses.py  ← source of truth
    └── tests/
```

## Run the app

1. Open `ios/BalletDairy.xcodeproj` in **Xcode 26** or later.
2. Select the *BalletDairy* target → *Signing & Capabilities* → choose your Team.
3. Run on an iPhone simulator or device (iOS 26+).
4. Optional: *Diary → ⚙︎ → Fill the last six weeks with sample practice* to see the calendar and charts come alive.

The project uses Xcode's synchronized folders, so any file you add under `ios/BalletDairy/` is picked up automatically.

## Run the backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
# docs at http://127.0.0.1:8000/docs
pytest
```

In the app, *Settings → Server* defaults to `http://127.0.0.1:8000` (simulator). On a real iPhone, use your Mac's LAN address.

| Endpoint | |
|---|---|
| `GET /movements?category=&level=&q=` | search the répertoire (accent-insensitive) |
| `GET /movements/{id}`, `GET /categories` | |
| `GET/PUT/DELETE /entries/{id}`, `GET /entries?start=&end=` | diary pages (scoped by the `X-Device-ID` header) |
| `POST /sync` | two-way, last-writer-wins sync; deletions propagate |
| `GET /stats?start=&end=` | classes, hours, streaks, top movements, categories, weekly hours |

## Editing movements and poses

The movement library and the dancer's poses are generated from Python, so the app and the server always agree:

```bash
python3 backend/scripts/build_poses.py --preview /tmp/poses.png retire arabesque air_split   # stick-figure check
python3 backend/scripts/build_movements.py      # validates and writes both JSON copies
```

- **Poses** are made of three parts, legs + arms + torso, as joint angles. `build_poses.py` uses the same forward kinematics as `Skeleton.swift`, and solves the tricky shapes (retiré, sur le cou-de-pied) numerically, so the toe really reaches the knee or ankle.
- **Movements** are keyframes of pose parts, plus timing, turns (`yaw`), travel (`dx`/`dz`) and mirroring (`m`). The animator keeps the supporting foot planted, lifts the body for jumps, and never lets a foot pass through the floor.

## Design notes

- **Paper for content, glass for controls.** Liquid Glass is used only on the floating, interactive layer: the tab bar, chips, buttons, the 3D stage controls, the selected day (which morphs between days). Cards are paper, the way Apple intends glass to be used.
- **Hand-drawn, but with restraint.** Pen underlines, circled dates, a bow, hearts for energy and washi-tape stickers are drawn with seeded randomness, so each doodle is imperfect but looks the same every launch. Handwriting (Noteworthy) is for your own words; the serif italic is for titles; script appears once per screen.
- **Ballet-core palette.** Cream paper, plum ink, satin and ribbon pinks, a little lilac and gold. The nine category colours were checked for colour-blind separation on the paper colour.
- The app is always light, because a notebook is paper.
