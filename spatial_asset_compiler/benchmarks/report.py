"""Benchmark report read/write."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


class BenchmarkReport:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.data: dict[str, Any] = {}
        if path.exists():
            self.data = json.loads(path.read_text(encoding="utf-8"))

    def merge(self, section: str, values: dict[str, Any]) -> None:
        if section not in self.data:
            self.data[section] = {}
        self.data[section].update(values)

    def set(self, key: str, value: Any) -> None:
        self.data[key] = value

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self.data, indent=2), encoding="utf-8")
