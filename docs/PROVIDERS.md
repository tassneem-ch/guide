# Providers

All providers are selected via `backend/.env` and reported at runtime in
`GET /v1/health` and in every response (`providers` map + `live` flags).
Keys live **only** on the backend — the Flutter app never contains them.

Default (keyless) development stack:

| Concern    | Default         | Key needed | Live in dev |
|------------|-----------------|------------|-------------|
| Prayer     | AlAdhan         | no         | yes         |
| Routing    | OSRM (public)   | no         | yes (fair-use) |
| Mosques    | OSM Overpass    | no         | yes (fair-use) |
| Geocoding  | Nominatim       | no         | yes (policy-bound) |
| Optimization | internal DP solver | no     | yes         |

Any provider can be switched to `fixture` (`PRAYER_PROVIDER=fixture`, ...)
for offline development. Fixture responses are always marked
`source: fixture` and the app displays a permanent banner for them.

## Prayer times — AlAdhan (`prayer_aladhan`)

- Free, no API key.
- Supports calculation methods (MWL, Umm al-Qura, ISNA, Egyptian, Karachi,
  ...) and schools (standard/hanafi); high-latitude rules and manual
  adjustments are applied by our backend on top of raw event times.
- Capabilities are exposed via `/v1/prayers/capabilities` — the app only
  offers settings the active provider supports.
- **Limitations**: no formal published SLA/quota; treat as best-effort and
  keep the `fixture` provider for tests. iqama/congregation times are not
  published by AlAdhan — the app never invents them.

## Routing — Google Routes API (`routing_google`)

- Usage-based pricing per request (route calls + matrix calls); Google Maps
  Platform offers a monthly usage-based billing credit — verify current
  pricing at https://mapsplatform.google.com/pricing before budgeting.
- Best quality: traffic-aware durations, real detours, route matrices.
- **Requirements**: `GOOGLE_MAPS_API_KEY` with Routes API + route matrix
  enabled. Use a separate restricted key.

## Routing — OSRM (`routing_osrm`) — default

- Free public demo server (`router.project-osrm.org`) for development,
  **fair-use only, no SLA**. Self-host OSRM with an appropriate OSM extract
  for production.
- **Limitations**: the public demo server serves the `driving` profile only.
  Walking/cycling requests against it fail honestly (HTTP error surfaced to
  the user, never fabricated) — for those modes use Google routing or a
  self-hosted OSRM with foot/bike profiles. Detour candidates that cannot be
  routed are labeled `great_circle_estimate` in the UI.

## Mosques — Google Places (`mosques_google`)

- Places API (New) pricing is per request (search/text search/place
  details); verify current pricing and free-tier thresholds on the Google
  Maps Platform pricing page.
- Rich data: names, opening hours (Text Search can return them), phone,
  website, accessibility fields.
- **Honesty mapping**: opening hours are shown at their verification level
  (provider-reported → "unverified" in the app unless a second source
  confirms). Absent hours render as "provider does not publish hours".

## Mosques — OSM Overpass (`mosques_osm`) — default

- Free; the public Overpass instance has strict fair-use limits
  (roughly one heavy query per minute) — self-host Overpass for production.
- **Limitations**: amenity=mosque coverage varies widely by region; opening
  hours are sparse and frequently missing (rendered as `unknown`, never
  guessed). No phone/website guarantees.

## Geocoding — Google (`geocoding_google`)

- Per-request pricing (see Google Maps Platform page). Best global coverage.

## Geocoding — Nominatim (`geocoding_nominatim`) — default

- Free, but usage policy is strict: max ~1 request/second, valid
  `User-Agent`, no bulk queries, caching encouraged. For production use,
  host your own Nominatim instance.
- Coverage/quality varies; results are returned as-is with their source.

## Optimization — internal solver (`optimize_google` is experimental)

- Default: bundled dynamic-programming solver (layered over
  (extra time, detour) with 60s granularity) — deterministic, free, fully
  covered by tests.
- `OPTIMIZATION_PROVIDER=google` targets Google's Route Optimization API.
  **Experimental and unverified in this codebase** — treat as a stub for
  future work; the internal solver is the supported path.

## Cost-control notes

- The backend caches routes/matrices (`ROUTE_CACHE_TTL_SECONDS`, default
  15 min) and prayer times (`PRAYER_CACHE_TTL_SECONDS`, default 6 h) where
  provider terms allow.
- `MAX_MATRIX_ELEMENTS` caps matrix size per request to bound Google
  per-request cost.
- Rate limiting (`slowapi`, `RATE_LIMIT_PER_MINUTE`) protects the backend
  itself and, transitively, provider quotas.

## In-app map rendering (client-side, not a backend provider)

| Engine | Key needed | Notes |
|--------|------------|-------|
| Google Maps SDK (default when configured) | yes (client key) | Selected with `--dart-define=USE_GOOGLE_MAPS=true` + platform key config |
| OpenStreetMap via `flutter_map` (fallback) | no | Labeled on-screen; keyless dev path |

- The Maps SDK key is a **client rendering key**: it ships in the app
  bundle. Restrict it per platform (Android package + SHA-1, iOS bundle id)
  in a billing-enabled Google Cloud project. This is a separate key and
  project from any server-side `GOOGLE_MAPS_API_KEY` used by backend
  routing/geocoding providers.
- The OpenStreetMap fallback uses the **public OSM tile servers**, which
  have a strict usage policy (light development use only, proper
  `User-Agent`/attribution — the app shows attribution). For production,
  self-host tiles or use a commercial tile provider and swap the tile URL
  in `app/lib/presentation/widgets/route_map.dart`.

## Switching providers safely

1. Set the env var (`ROUTING_PROVIDER=google`, ...).
2. Restart the backend; check `/v1/health` — it reports the active provider
   and whether it is live.
3. The mobile app displays provider names in **Settings → Backend provider
   status** and per response — so users always see what produced their data.
