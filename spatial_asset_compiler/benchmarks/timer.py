"""Stage timing utilities."""

from __future__ import annotations

import time
from contextlib import contextmanager
from typing import Generator


class StageTimer:
    def __init__(self) -> None:
        self._times: dict[str, float] = {}

    @contextmanager
    def stage(self, name: str) -> Generator[None, None, None]:
        start = time.perf_counter()
        try:
            yield
        finally:
            self._times[name] = time.perf_counter() - start

    def get(self, name: str) -> float | None:
        return self._times.get(name)

    def as_dict(self) -> dict[str, float]:
        return dict(self._times)
