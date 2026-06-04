"""Mask storage helpers."""

from __future__ import annotations

import json
from pathlib import Path


def write_mask_index(masks_dir: Path, entries: list[dict]) -> Path:
    index_path = masks_dir / "index.json"
    index_path.write_text(json.dumps({"masks": entries}, indent=2), encoding="utf-8")
    return index_path
