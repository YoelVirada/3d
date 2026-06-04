#!/usr/bin/env python3
"""Gaussian Grouping train wrapper."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gg-root", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--iterations", type=int, default=7000)
    args = ap.parse_args()

    root = Path(args.gg_root)
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)

    convert = root / "convert.py"
    if convert.exists():
        subprocess.run([sys.executable, str(convert), "-s", str(args.data)], cwd=str(root), check=False)

    train_sh = root / "script" / "train.sh"
    if train_sh.exists():
        subprocess.run(["bash", str(train_sh), Path(args.data).name, "1"], cwd=str(root), check=False)

    sys.exit(0)


if __name__ == "__main__":
    main()
