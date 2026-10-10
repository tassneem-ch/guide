# Architecture — Guide: Prayer-Aware Travel Planner

Guide is a global, prayer-aware travel planner. It plans road journeys around Islamic
prayer times, discovers real mosques near the route, and schedules feasible stops —
for single-day trips and multi-day, multi-country itineraries.

This document describes the system as implemented in this repository.

---

## 1. High-level overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Flutter app (Android / iOS)                   │
│  presentation → application → domain ← data                          │
│  Riverpod · go_router · flutter_map · intl (en/ar/fr, RTL)           │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ HTTPS JSON (Bearer token optional)
┌───────────────────────────────▼──────────────────────────────────────┐
│                     FastAPI backend (Python 3.12)                    │
│  api → services → domain ← providers                                 │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ Provider layer (replaceable, env-selected)                     │  │
│  │  PrayerTimeProvider  → AlAdhan (live) | fixture                │  │
│  │  RoutingProvider     → Google Routes API | OSRM | fixture      │  │
│  │  MosqueProvider      → Google Places API | OSM Overpass | fixture│ │
│  │  OptimizationProvider → internal solver | Google Route Opt API │  │
│  └────────────────────────────────────────────────────────────────┘  │
│  Scheduling engine (prayer windows, detour evaluation, itinerary)    │
│  PostgreSQL/SQLite (saved itineraries, users, preferences)           │
└──────────────────────────────────────────────────────────────────────┘
```

**Rule:** no privileged key ever ships in the Flutter binary. The app only talks to
this backend. Google/AlAdhan credentials live in backend environment variables.

---

## 2. Repository layout

```
.
├── app/                    Flutter client (clean architecture, Riverpod)
│   ├── lib/
│   │   ├── main.dart               entrypoint, theme, router bootstrap
│   │   ├── app/                    router, theme, localization bootstrap
│   │   ├── core/                   errors, result types, clock, extensions
│   │   ├── domain/                 entities + repository interfaces (pure Dart)
│   │   ├── data/                   DTOs, API client, repositories, mock sources
│   │   ├── application/            Riverpod controllers/notifiers per feature
│   │   └── presentation/           screens + reusable widgets
│   ├── l10n/                       ARB files (en, ar, fr)
│   └── test/                       unit/widget tests
├── backend/
│   ├── app/
│   │   ├── main.py                 FastAPI app factory
│   │   ├── config.py               env-driven settings
│   │   ├── api/                    routers: prayer, routes, mosques, trips, auth
│   │   ├── domain/                 entities: geo, prayer, route, mosque, itinerary
│   │   ├── providers/              interfaces + Google/OSRM/OSM/AlAdhan/fixture
│   │   ├── services/               scheduling + optimization engine
│   │   ├── db/                     SQLAlchemy models/session
│   │   └── security.py             password hashing, JWT (optional auth)
│   ├── tests/                      pytest suite (timezone, scheduling, …)
│   └── .env.example                no real secrets
├── docs/
│   ├── ARCHITECTURE.md             this file
│   ├── SETUP.md                    install/run for app + backend + services
│   └── PROVIDERS.md                provider limits, quotas, estimated costs
└── README.md
```

### Layering rules

- **domain/** — pure Dart / pure Python entities and interfaces. No IO, no framework.
- **application/** (app) and **services/** (backend) — orchestration & business logic.
- **data/** (app) and **providers/** (backend) — implement repository/provider
  interfaces; the only place that knows HTTP, serializers, or vendor SDKs.
- **presentation/** (app) and **api/** (backend) — UI and transport only.
- External APIs sit behind provider-independent interfaces so Google services can be
  swapped (coverage/pricing) without touching the engine or the UI.

---

## 3. Core domain model

| Entity | Meaning |
|---|---|
| `GeoPoint` | latitude/longitude (+ optional IANA time zone, display name) |
| `PrayerEvent` | one of Fajr/Dhuhr/Asr/Maghrib/Isha; UTC instant + local wall time + tz id + method/school used + `source` |
| `PrayerWindow` | prayer instant ± user planning window/buffer used for scheduling |
| `MosqueCandidate` | id, name, coords, per-field verification (`verified`/`unverified`/`absent`), detour estimates, arrival estimate, data quality |
| `TravelLeg` | origin → destination leg: distance, duration, departure/arrival (UTC + local) |
| `ItineraryStop` | typed stop: waypoint / mosque / prayer break / attraction / meal / overnight |
| `RoutePlan` | ordered legs + stops + metrics + `explanation` + uncertainty notes |
| `RouteAlternative` | `fastest` \| `prayer_friendly` \| `balanced` variant of the same query |
| `Trip` | multi-day container: days → schedules, overnight stays, locked stops |

**Time handling convention:** every instant is stored/transmitted as UTC ISO-8601 with
the IANA time-zone id of the *local* place attached. Display always uses the local
zone of that stop; comparison/scheduling always uses UTC. Journey prayer times are
computed per representative location (sampled along the route), never copied from the
departure city.

**Data honesty convention:** every externally derived fact carries `provider`,
`fetchedAt`/`staleness`, and a verification status. Fixture/dev data is labelled
`source=fixture` end-to-end and rendered distinctly in the UI. Absence of mosque data
is reported as `no_data` ≠ `no_mosques`.

---

## 4. Backend services

### 4.1 API surface (all JSON, versioned under `/v1`)

| Endpoint | Purpose |
|---|---|
| `POST /v1/prayer-times` | prayer times for a point/date/method/school/high-lat rules (accepts a UTC instant or a local date) |
| `GET /v1/prayer-times/capabilities` | what the active prayer provider supports |
| `GET /v1/places/autocomplete` | place suggestions (Google Places (New) with a key, keyless otherwise) |
| `GET /v1/places/details` | resolve a selected suggestion to coordinates |
| `POST /v1/routes/alternatives` | fastest / prayer-friendly / balanced route plans |
| `POST /v1/mosques/search` | mosque candidates near a point or polyline |
| `POST /v1/optimize` | re-run stop selection for edited constraints |
| `POST /v1/trips/plan` | multi-day itinerary build/reschedule |
| `GET/PUT /v1/me/preferences` | user scheduling preferences |
| `GET/POST/DELETE /v1/trips` | saved itineraries (auth optional) |
| `POST /v1/auth/register`, `POST /v1/auth/login` | optional accounts/JWT |
| `GET /v1/health` | liveness + provider mode report |

### 4.2 Scheduling & optimization engine

The journey is modelled as **legs** (road-network travel) and **stops** (duration +
time window). The engine runs in four stages:

1. **Route acquisition** — `RoutingProvider` returns 1..n alternatives with real
   road durations (Google Routes API, or OSRM in keyless dev mode). Traffic-aware
   durations used when the provider reports them.
2. **Prayer sampling** — for a future departure, sample N points along the chosen
   geometry; for each sample compute prayer times for its local date and time zone
   via `PrayerTimeProvider`; merge into a journey-wide ordered list of prayer events
   (deduped per city/day, tz-change aware, midnight/date-line safe).
3. **Candidate generation** — `MosqueProvider` finds mosques within a corridor of the
   polyline; each candidate is evaluated with **routed** detour (route matrix calls,
   batched & deduped; haversine only as clearly-labelled fallback) → arrival time at
   the mosque, fit vs. the prayer window (± planning window, + buffer), opening-hours
   check when verified, data freshness, accuracy.
4. **Selection (constraint solver)** — for each journey prayer event choose
   {candidate₁…candidateₙ, skip} subject to hard constraints (max detour, mandatory
   stops, ordering, buffer, opening windows) and minimize a weighted objective:

   ```
   w1·detour_time + w2·waiting_time + w3·backtracking + w4·schedule_conflict_penalty
   ```

   solved by dynamic programming over prayer events (monotone, per-event alternatives),
   with a greedy insertion pass for user-forced stops. This is the built-in solver; a
   `RouteOptimizationProvider` interface also exposes Google's Route Optimization API
   for problems it models well. Both are honest about what they cover: neither knows
   prayer times natively — the prayer constraints are encoded by this layer.

5. **Explanation** — the plan returns why it was chosen (e.g. "Masjid X selected: 4.2
   min detour, arrival 12:38 → 8 min before Dhuhr") and what was traded off.

Recalculation triggers: departure-time change, stop edit, material traffic change, or
>5 min drift in any arrival estimate. The engine re-plans from stage 2.

### 4.3 Multi-day trips

`TripPlannerService` composes day schedules: travel legs between cities, activity
time windows (opening hours when verified), fixed/locked stops, meals, rest, mosque
visits anchored to that city's local prayers, overnight stays. Feasibility is enforced
with the same leg/stop model (no impossible sequences); edits trigger local
re-scheduling of the affected day, then whole-trip repair if boundaries move.

### 4.4 Persistence

SQLAlchemy 2.x; **SQLite by default** (zero-setup dev), **PostgreSQL + PostGIS when
`DATABASE_URL` says so** (geospatial queries documented; haversine-compatible SQL used
otherwise). Tables: `users`, `preferences`, `itineraries`, `trip_days` (JSON itinerary
blob + metadata indexes). Auth is optional: `AUTH_REQUIRED=false` runs anonymous with
local-only storage semantics; with JWT enabled, itineraries are per-user.

---

## 5. Flutter client

- **State:** Riverpod (`AsyncNotifier` per feature: planner, comparison, journey,
  trips, settings). No business logic in widgets.
- **Navigation:** `go_router` with deep-linkable routes:
  `/` (home) → `/routes` (comparison) → `/journey` (details) → `/mosque/:id`;
  `/trips`, `/trips/:id`, `/settings`.
- **Map:** `flutter_map` (OSM tiles) draws route polylines, stop pins, and mosque
  candidates — keyless and identical on Android/iOS; the map source is isolated in
  `presentation/widgets/route_map.dart` so a vendor SDK (e.g. google_maps_flutter)
  can replace it without touching feature code.
- **Data:** `dio` client with timeouts, retries with backoff, and error mapping to a
  typed `Failure` sealed class. Repository interfaces in `domain/`, implementations in
  `data/`. A `devFixture` toggle swaps in clearly-marked fixture repositories.
- **Localization:** `flutter gen-l10n`, ARB files for `en`, `ar`, `fr`; `ar` is RTL
  (`Directionality` driven by `MaterialApp.locale`); dates/numbers via `intl`.
- **Settings & prefs:** non-sensitive prefs in `shared_preferences`; tokens in
  `flutter_secure_storage`.
- **Offline:** saved itineraries + last-fetched prayer/mosque data cached in local
  storage; UI marks anything stale or unavailable; no live-navigation claims offline.

---

## 6. Security & cost controls

- Backend keys only in `.env` (never committed; `.env.example` has placeholders).
- Google keys restricted by API + HTTP referrer/IP at the provider console.
- Per-request validation (pydantic), rate limiting (slowapi), timeouts, retries with
  jitter, request deduplication for identical route/mosque queries, field masks and
  Place `fields` filtering, session caches for prayer times and route matrices where
  provider terms allow.
- JWT (HS256) + bcrypt password hashing when auth is enabled; no location history is
  stored — only explicit user-saved itineraries.
- Structured logging without coordinates of live users.

---

## 7. Testing strategy

| Layer | What | Where |
|---|---|---|
| Backend | time-zone conversion, midnight/date-line boundaries, DST | `backend/tests/test_timezones.py` |
| Backend | prayer window scheduling, buffers, waiting/penalties | `backend/tests/test_prayer_scheduling.py` |
| Backend | route feasibility + detour limits | `backend/tests/test_route_feasibility.py` |
| Backend | candidate ranking & data-quality handling | `backend/tests/test_candidate_selection.py` |
| Backend | rescheduling after departure/stop changes | `backend/tests/test_reschedule.py` |
| Backend | API contracts with fixture providers | `backend/tests/test_api.py` |
| App | domain logic, controller behaviour, l10n/RTL presence | `app/test/` |

Fixture providers are used in tests; live providers are integration-tested manually
and documented in `docs/PROVIDERS.md`.
