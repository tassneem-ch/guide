# Guide

A prayer-aware travel planner: plan real routes, discover mosques along the
way, and see — honestly — how each option serves (or doesn't serve) your
prayer times.

- **Flutter** client for Android and iOS (single codebase).
- **FastAPI** backend that plans routes with layered prayer scheduling.
- **Global-first**: no hardcoded country, timezone, language, or calculation
  method. UTC instants + local IANA timezones everywhere; English, Arabic
  (RTL), and French.

## What makes it honest

This app never fabricates data. Every screen carries provenance:

- **Fixture vs live**: any response produced by a development fixture is
  labeled (`source: fixture`, provider names starting with `FIXTURE`) and the
  UI shows a persistent banner. Demo mode works fully offline and is
  obviously marked.
- **No invented mosques**: names, opening hours, and phone numbers come from
  the data provider only. Missing stays missing (`no_data` ≠ no mosques).
- **No invented iqama times**: congregation times are displayed only when a
  provider verified them; otherwise the UI explains why they are absent.
- **Uncertainty labels**: detour estimates (vs. routed detours), stale
  cached responses, and infeasible plans are surfaced, not hidden.

## Screens

Home (plan a route + today's prayers) → Route comparison (3 alternatives with
explanations) → Journey details (stop timeline + map) → Mosque details →
Trip planner (multi-day, activities, overnight stays, surfaced conflicts) →
Settings (capabilities-driven prayer methods, language, theme, backend URL).

## Repository layout

| Path         | Contents                                                        |
|--------------|-----------------------------------------------------------------|
| `backend/`   | FastAPI app, provider adapters, scheduling engine, 43 tests      |
| `app/`       | Flutter client, l10n (en/ar/fr), widget tests                    |
| `docs/`      | [Architecture](docs/ARCHITECTURE.md), [Setup](docs/SETUP.md), [Providers](docs/PROVIDERS.md) |

## Quick start

Backend (Python 3.12):

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
Copy-Item .env.example .env   # defaults work for keyless dev providers
.\.venv\Scripts\uvicorn app.main:app --reload
```

App (Flutter 3.47+):

```powershell
cd app
flutter pub get
flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8000   # Android emulator
```

No API keys are needed for development: the backend defaults to AlAdhan
(prayer), OSRM (routing), OpenStreetMap/Overpass (mosques), and Nominatim
(geocoding). See [docs/PROVIDERS.md](docs/PROVIDERS.md) for quotas, costs,
and switching to Google providers — keys live only on the server, never in
the app.

## Tests

```powershell
# backend (no network, fixture providers)
cd backend; .\.venv\Scripts\python.exe -m pytest -q     # 43 passed

# app
cd app; flutter analyze                                  # No issues found
flutter test                                             # widget + contract tests
```

## Status & limitations (honest list)

- Notifications: the "prayer stop reminders" toggle is persisted, but
  on-device scheduling is **not yet implemented** — the UI says so.
- Google Route Optimization adapter is experimental and marked unverified;
  the internal DP solver is the default.
- Trip persistence is local-only in the MVP (`saved trips` are stored on
  device); the backend API supports authenticated persistence when
  `AUTH_REQUIRED=true`.
