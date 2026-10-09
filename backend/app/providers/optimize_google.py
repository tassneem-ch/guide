"""Google Route Optimization API (optimalTours) provider — OPTIONAL.

Enabled with OPTIMIZATION_PROVIDER=google. The built-in scheduler is the
default because it models prayer windows natively; the hosted solver models
pure stop-ordering (shipments + one vehicle). Prayer constraints are always
validated by the internal scheduler afterwards, so a hosted answer can never
produce a prayer-infeasible plan.

NOTE: request shapes must be re-verified against the current API reference
before enabling in production (see docs/PROVIDERS.md).
"""
from __future__ import annotations

from ..config import get_settings
from .base import OptimizationContext, OptimizationSolution
from .google_common import ProviderError, make_client


class GoogleRouteOptimizationProvider:
    name = "google"
    live = True

    def __init__(self) -> None:
        settings = get_settings()
        self._key = settings.google_route_optimization_key or settings.google_maps_api_key
        self._client = make_client()

    async def optimize(self, ctx: OptimizationContext) -> OptimizationSolution:
        if not self._key:
            raise ProviderError("GOOGLE_ROUTE_OPTIMIZATION_KEY is not configured")

        def latlng(p) -> dict:
            return {"latitude": p.lat, "longitude": p.lon}

        # Each visit becomes a shipment picked up at the visit and dropped off
        # at the journey end; the solver sequences pickups for one vehicle.
        shipments = []
        for i, visit in enumerate(ctx.visits):
            service = "900s"
            if ctx.service_times_s and i < len(ctx.service_times_s):
                service = f"{ctx.service_times_s[i]}s"
            shipments.append(
                {
                    "pickups": [{"visit": {"arrivalLocation": {"latLng": latlng(visit)},
                                           "duration": service}}],
                    "dropoffs": [{"visit": {"arrivalLocation": {"latLng": latlng(ctx.ends[0])}}}],
                }
            )

        body = {
            "model": {
                "shipments": shipments,
                "vehicles": [
                    {
                        "startLocation": {"latLng": latlng(ctx.starts[0])},
                        "endLocation": {"latLng": latlng(ctx.ends[0])},
                    }
                ],
            },
            "timeout": "20s",
        }

        try:
            response = await self._client.post(
                "https://optimization.googleapis.com/v1/optimizeTours",
                json=body,
                headers={
                    "Content-Type": "application/json",
                    "X-Goog-Api-Key": self._key,
                },
            )
            response.raise_for_status()
            data = response.json()
        except Exception as exc:
            raise ProviderError(f"Route Optimization API failed: {exc}") from exc

        visits = data.get("visits") or []
        # visits[] arrive in solver order; map back to our indices by location.
        order: list[int] = []
        for visit in visits:
            loc = (visit.get("arrivalLocation") or {}).get("latLng") or {}
            for i, p in enumerate(ctx.visits):
                if abs(p.lat - loc.get("latitude", -999)) < 1e-6 and \
                   abs(p.lon - loc.get("longitude", -999)) < 1e-6:
                    order.append(i)
                    break
        total_s = 0
        for route in data.get("routes") or []:
            dur = route.get("totalDuration") or "0s"
            try:
                total_s += int(str(dur).rstrip("s") or 0)
            except ValueError:
                pass
        return OptimizationSolution(
            visit_order=order,
            total_duration_s=total_s,
            provider=self.name,
            live=True,
            raw_notes=[
                "Hosted solver ordering; prayer-window feasibility is re-validated "
                "by the internal scheduler."
            ],
        )

    async def close(self) -> None:
        await self._client.aclose()
