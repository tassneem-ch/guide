# Setup

## Prerequisites

| Tool       | Version                          |
|------------|----------------------------------|
| Python     | 3.12+                            |
| Flutter    | 3.47+ (Dart 3.13+)               |
| Git        | any recent                        |

Android builds need the Android SDK (via Android Studio); iOS builds need
Xcode on macOS. The repo builds both platforms from one codebase.

## 1. Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
Copy-Item .env.example .env
.\.venv\Scripts\uvicorn app.main:app --reload
```

- API docs: http://localhost:8000/docs
- Health: http://localhost:8000/v1/health (reports active providers, live vs
  fixture, and whether auth is required)
- Database: SQLite by default (`guide.db`, git-ignored). Set `DATABASE_URL`
  to PostgreSQL/PostGIS for production — the same schema is used.

The default `.env` uses **keyless dev providers** (AlAdhan, OSRM, OSM
Overpass, Nominatim). Nothing to sign up for. See
[PROVIDERS.md](PROVIDERS.md) before switching providers.

### Auth (optional)

`AUTH_REQUIRED=false` by default. Setting it to `true` requires JWTs for
saved trips/preferences (`POST /v1/auth/register|login`). Set
`JWT_SECRET` to a long random string in that case.

## 2. App

```powershell
cd app
flutter pub get
```

Run against the backend:

```powershell
# Android emulator (10.0.2.2 is the host loopback alias)
flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8000

# iOS simulator / desktop
flutter run --dart-define=BACKEND_URL=http://127.0.0.1:8000

# Physical device: use your machine's LAN IP
flutter run --dart-define=BACKEND_URL=http://192.168.1.10:8000
```

`BACKEND_URL` is a public endpoint address, not a secret — provider API keys
never appear in the app. The URL can also be changed at runtime in
**Settings → Backend** (persisted on device).

### No backend? Demo mode

**Settings → Demo data** enables fully offline demo data generated on-device.
It is loudly labeled everywhere (persistent banner, `FIXTURE` provider
names) so it can never be mistaken for live data.

### Localization

en / ar (RTL) / fr ship with the app; the locale follows the system by
default and can be overridden in Settings. New keys go in
`app/lib/l10n/app_*.arb`, then:

```powershell
cd app; flutter gen-l10n
```

## 3. Verification (what CI should run)

```powershell
# backend unit + API tests (fixtures only, no network)
cd backend
if (Test-Path guide_test.db) { Remove-Item guide_test.db }
.\.venv\Scripts\python.exe -m pytest -q

# app static analysis + tests
cd app
flutter analyze
flutter test
```

## Platform notes

- **Android**: `INTERNET` + location permissions are declared in
  `app/android/app/src/main/AndroidManifest.xml`. Location is optional and
  only used for "use my location".
- **iOS**: `NSLocationWhenInUseUsageDescription` is set; ATS currently allows
  plain HTTP for the local development backend — **remove
  `NSAllowsArbitraryLoads` and serve HTTPS before a production release**.
- **Notifications**: the reminders preference is stored, but on-device
  notification scheduling is not implemented yet; the UI states this
  explicitly.

## Production checklist

- [ ] Backend behind HTTPS; `APP_ENV=production`, `APP_DEBUG=false`
- [ ] `JWT_SECRET` set to a long random value; `AUTH_REQUIRED=true`
- [ ] PostgreSQL (+ PostGIS if geospatial queries are needed)
- [ ] Provider keys set server-side only (see PROVIDERS.md for quotas/costs)
- [ ] iOS ATS exception removed; `CORS_ORIGINS` narrowed
- [ ] Rate limits reviewed (`RATE_LIMIT_PER_MINUTE`)
