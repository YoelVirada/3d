"""Build minimal AR capture zip fixture for smoke tests."""

from __future__ import annotations

import io
import json
import zipfile
from pathlib import Path

import numpy as np


def build_minimal_zip(out_path: Path, num_frames: int = 5) -> Path:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    intrinsics = [[800.0, 0.0, 0.0], [0.0, 800.0, 0.0], [0.0, 0.0, 1.0]]
    poses = []
    buf = io.BytesIO()

    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for i in range(num_frames):
            name = f"frame_{i + 1:05d}.jpg"
            zf.writestr(f"ar/frames/{name}", b"\xff\xd8\xff\xd9")
            m = np.eye(4)
            m[0, 3] = i * 0.05
            poses.append(
                {
                    "frame": name,
                    "timestamp_s": 0.5 * i,
                    "tracking_state": "normal",
                    "transform": m.tolist(),
                    "intrinsics": intrinsics,
                    "width": 640,
                    "height": 480,
                }
            )
        zf.writestr(
            "capture.json",
            json.dumps({"capture_mode": "arkit", "capture_version": "1.0"}),
        )
        zf.writestr("ar/manifest.json", json.dumps({"ar_frame_count": num_frames}))
        zf.writestr("ar/poses.json", json.dumps(poses))

    out_path.write_bytes(buf.getvalue())
    return out_path


if __name__ == "__main__":
    build_minimal_zip(Path(__file__).parent / "fixtures" / "ar_capture_minimal.zip")
