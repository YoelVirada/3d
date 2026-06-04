#!/usr/bin/env python3
"""Wrapper to invoke SAGA training when SegAnyGAussians repo is present."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--saga-root", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--iterations", type=int, default=5000)
    args = ap.parse_args()

    root = Path(args.saga_root)
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)

    train_scene = root / "train_scene.py"
    if not train_scene.exists():
        print("train_scene.py not found", file=sys.stderr)
        sys.exit(1)

    cmd = [
        sys.executable,
        str(train_scene),
        "-s",
        str(args.data),
        "--iterations",
        str(args.iterations),
    ]
    proc = subprocess.run(cmd, cwd=str(root))
    # Expect user/SAGA to write assignments; placeholder exit
    sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
