"""Mosque candidate discovery along a route and routed detour evaluation.

Detours are computed with road-network durations (routing matrix). When the
matrix provider is unavailable, a great-circle estimate is used and clearly
labelled as `great_circle_estimate` so the UI can show the uncertainty.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from ..domain.geo import GeoPoint, haversine_m, point_segment_distance_m
from ..domain.mosque import MosqueCandidate, MosqueSearchResult
from ..domain.route import TravelMode
from ..providers.base import MosqueProvider, RoutingProvider
from ..providers.google_common import ProviderError

CORRIDOR_RADIUS_M = 1500
MATRIX_BATCH = 20  # stays under MAX_MATRIX_ELEMENTS for 12 anchors


@dataclass
class RouteCandidate:
    """A mosque candidate pinned to a route anchor with its routed detour."""

    mosque: MosqueCandidate
    anchor_index: int
    detour_seconds: int
    detour_distance_m: int
    detour_method: str            # "routed" | "great_circle_estimate"
    eta_at_anchor_s: int          # base (stop-free) ETA at the anchor
    leg_seconds: int = 0          # routed anchor -> mosque duration
    return_seconds: int = 0       # routed mosque -> next anchor duration
    leg_distance_m: int = 0
    return_distance_m: int = 0


@dataclass
class CandidateSearchOutcome:
    candidates: list[RouteCandidate] = field(default_factory=list)
    status: str = "ok"            # ok | no_data | provider_error
    notes: list[str] = field(default_factory=list)


async def discover_mosques_along_route(
    mosque_provider: MosqueProvider,
    geometry: list[GeoPoint],
    anchor_indices: list[int],
    corridor_radius_m: int = CORRIDOR_RADIUS_M,
) -> MosqueSearchResult:
    """Search near each anchor; merge and de-duplicate."""
    merged: dict[str, MosqueCandidate] = {}
    statuses: set[str] = set()
    messages: list[str] = []
    for idx in anchor_indices:
        anchor = geometry[idx]
        result = await mosque_provider.search_near(anchor, corridor_radius_m)
        statuses.add(result.status)
        if result.message:
            messages.append(result.message)
        for candidate in result.candidates:
            existing = merged.get(candidate.id)
            if existing is None or haversine_m(candidate.location, anchor) < haversine_m(
                existing.location, anchor
            ):
                candidate.assigned_route_index = idx
                merged[candidate.id] = candidate

    if not merged:
        if "ok" in statuses:
            status = "no_data"
            message = (
                "The places provider was reached but returned no mosques near "
                "this route — this does not confirm there are none; coverage "
                "may be incomplete."
            )
        elif statuses == {"provider_error"}:
            status = "provider_error"
            message = "Mosque provider error: " + " ".join(messages)
        else:
            status = "no_data"
            message = " ".join(messages) or "No mosque data available for this route."
        return MosqueSearchResult(candidates=[], status=status, message=message)

    return MosqueSearchResult(
        candidates=list(merged.values()),
        status="ok",
        message=None,
    )


async def evaluate_detours(
    routing: RoutingProvider,
    geometry: list[GeoPoint],
    base_etas_s: dict[int, int],
    candidates: list[MosqueCandidate],
    mode: TravelMode,
    depart_at,
) -> tuple[list[RouteCandidate], list[str]]:
    """Compute routed detour (seconds/metres) for each candidate.

    detour = d(anchor → mosque) + d(mosque → next_anchor) − d(anchor → next_anchor)
    computed from the routing matrix; falls back to a labelled estimate.
    """
    notes: list[str] = []
    anchors = sorted({c.assigned_route_index for c in candidates if c.assigned_route_index is not None})
    if not anchors:
        return [], notes

    anchor_points = [geometry[i] for i in anchors]
    next_indices = [min(i + 1, len(geometry) - 1) for i in anchors]
    next_points = [geometry[j] for j in next_indices]
    mosque_points = [c.location for c in candidates]

    durations: dict[tuple[int, int], int | None] = {}
    distances: dict[tuple[int, int], int | None] = {}
    routed_ok = False
    try:
        # anchor -> mosque
        d1 = await _batched_matrix(routing, anchor_points, mosque_points, mode, depart_at)
        # mosque -> next anchor
        d2 = await _batched_matrix(routing, mosque_points, next_points, mode, depart_at)
        # anchor -> next anchor (baseline)
        d3 = await _batched_matrix(routing, anchor_points, next_points, mode, depart_at)
        routed_ok = True
        for i, a in enumerate(anchors):
            for j, cand in enumerate(candidates):
                if cand.assigned_route_index == a:
                    durations[(i, j)] = d1.durations_s[i][j]
                    distances[(i, j)] = d1.distances_m[i][j]
        for j, cand in enumerate(candidates):
            i = anchors.index(cand.assigned_route_index) if cand.assigned_route_index in anchors else None
            if i is None:
                continue
            durations[(("m", j), i)] = d2.durations_s[j][i]
            distances[(("m", j), i)] = d2.distances_m[j][i]
            durations[(("base", i), i)] = d3.durations_s[i][i]
            distances[(("base", i), i)] = d3.distances_m[i][i]
    except ProviderError as exc:
        notes.append(
            f"Routing matrix unavailable ({exc}); detour times are great-circle "
            "estimates and marked as uncertain."
        )

    results: list[RouteCandidate] = []
    for j, cand in enumerate(candidates):
        idx = cand.assigned_route_index
        if idx is None:
            continue
        i = anchors.index(idx)
        if routed_ok and durations.get((i, j)) is not None and durations.get((("m", j), i)) is not None:
            leg1 = durations[(i, j)] or 0
            leg2 = durations[(("m", j), i)] or 0
            base = durations.get((("base", i), i)) or 0
            detour_s = max(0, leg1 + leg2 - base)
            dist1 = distances.get((i, j)) or 0
            dist2 = distances.get((("m", j), i)) or 0
            base_d = distances.get((("base", i), i)) or 0
            detour_m = max(0, dist1 + dist2 - base_d)
            method = "routed"
            leg_seconds = leg1
            return_seconds = leg2
            leg_distance_m = dist1
            return_distance_m = dist2
        else:
            # Labelled estimate: dog-leg via the mosque minus along-route span.
            anchor = geometry[idx]
            nxt = geometry[next_indices[i]]
            mosque = cand.location
            est = (
                haversine_m(anchor, mosque)
                + haversine_m(mosque, nxt)
                - haversine_m(anchor, nxt)
            )
            est = max(est * 1.3, 0.0)  # road factor, deliberately conservative
            detour_s = int(est / 13.9) if mode == TravelMode.DRIVING else int(est / 1.4)
            detour_m = int(est)
            method = "great_circle_estimate"
            speed = 13.9 if mode == TravelMode.DRIVING else 1.4
            leg_seconds = int(haversine_m(anchor, mosque) * 1.3 / speed)
            return_seconds = int(haversine_m(mosque, nxt) * 1.3 / speed)
            leg_distance_m = int(haversine_m(anchor, mosque) * 1.3)
            return_distance_m = int(haversine_m(mosque, nxt) * 1.3)

        cand.detour_seconds = detour_s
        cand.detour_distance_m = detour_m
        cand.detour_method = method
        results.append(
            RouteCandidate(
                mosque=cand,
                anchor_index=idx,
                detour_seconds=detour_s,
                detour_distance_m=detour_m,
                detour_method=method,
                eta_at_anchor_s=base_etas_s.get(idx, 0),
                leg_seconds=leg_seconds,
                return_seconds=return_seconds,
                leg_distance_m=leg_distance_m,
                return_distance_m=return_distance_m,
            )
        )
    return results, notes


async def _batched_matrix(routing, origins, destinations, mode, depart_at):
    """Matrix in blocks that stay under the provider's element budget."""
    from ..config import get_settings
    from ..providers.base import MatrixResult

    budget = max(get_settings().max_matrix_elements, 40)
    first: MatrixResult | None = None

    o_block = min(len(origins), max(1, int(budget ** 0.5)))
    d_block = min(len(destinations), max(1, budget // o_block))

    for i in range(0, len(origins), o_block):
        o_chunk = origins[i:i + o_block]
        durs: list[list[int | None]] = []
        dists: list[list[int | None]] = []
        for j in range(0, len(destinations), d_block):
            d_chunk = destinations[j:j + d_block]
            result = await routing.matrix(o_chunk, d_chunk, mode, depart_at)
            durs.extend(result.durations_s)
            dists.extend(result.distances_m)
        if first is None:
            first = MatrixResult(
                durations_s=[], distances_m=[],
                provider=result.provider, live=result.live,
                estimated=result.estimated,
            )
        first.durations_s.extend(durs)
        first.distances_m.extend(dists)
    assert first is not None
    return first
