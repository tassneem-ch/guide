"""Google-encoded polyline codec (precision 5 and 6)."""
from __future__ import annotations

from ..domain.geo import GeoPoint


def decode_polyline(encoded: str, precision: int = 5) -> list[GeoPoint]:
    factor = 10**precision
    points: list[GeoPoint] = []
    index, lat, lon = 0, 0, 0
    while index < len(encoded):
        result: list[int] = []
        shift = 0
        while True:
            b = ord(encoded[index]) - 63
            index += 1
            result.append(b & 0x1F)
            shift += 5
            if b < 0x20:
                break
        lat += _as_signed(result, shift)

        result = []
        shift = 0
        while True:
            b = ord(encoded[index]) - 63
            index += 1
            result.append(b & 0x1F)
            shift += 5
            if b < 0x20:
                break
        lon += _as_signed(result, shift)

        points.append(GeoPoint(lat=lat / factor, lon=lon / factor))
    return points


def _as_signed(values: list[int], shift: int) -> int:
    payload = 0
    start = 0
    for v in values:
        payload |= (v & 0x1F) << start
        start += 5
    if payload & 1:
        return ~(payload >> 1)
    return payload >> 1
