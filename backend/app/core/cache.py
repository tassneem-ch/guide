"""Simple TTL cache used for prayer times, routes and matrices."""
from __future__ import annotations

import asyncio
import time
from typing import Any, Awaitable, Callable, Hashable


class TTLCache:
    def __init__(self, ttl_seconds: int, max_entries: int = 2048) -> None:
        self._ttl = ttl_seconds
        self._max = max_entries
        self._store: dict[Hashable, tuple[float, Any]] = {}
        self._locks: dict[Hashable, asyncio.Lock] = {}
        self._lock_guard = asyncio.Lock()

    def get(self, key: Hashable) -> Any | None:
        item = self._store.get(key)
        if item is None:
            return None
        expires_at, value = item
        if time.monotonic() > expires_at:
            self._store.pop(key, None)
            return None
        return value

    def set(self, key: Hashable, value: Any) -> None:
        if len(self._store) >= self._max:
            # Drop the oldest ~10% to stay bounded.
            oldest = sorted(self._store.items(), key=lambda kv: kv[1][0])
            for k, _ in oldest[: max(1, self._max // 10)]:
                self._store.pop(k, None)
        self._store[key] = (time.monotonic() + self._ttl, value)

    async def get_or_fetch(
        self, key: Hashable, factory: Callable[[], Awaitable[Any]]
    ) -> Any:
        cached = self.get(key)
        if cached is not None:
            return cached
        # Deduplicate concurrent identical requests.
        async with self._lock_guard:
            lock = self._locks.setdefault(key, asyncio.Lock())
        async with lock:
            cached = self.get(key)
            if cached is not None:
                return cached
            value = await factory()
            self.set(key, value)
            return value
