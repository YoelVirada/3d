#!/usr/bin/env python3
"""SuGaR scene mesh extraction wrapper."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sugar-root", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    root = Path(args.sugar_root)
    extract = root / "extract_mesh.py"
    if not extract.exists():
        print("extract_mesh.py not found", file=sys.stderr)
        sys.exit(1)
    # SuGaR requires its own trained model; document failure for v1
    Path(args.output).write_text("# SuGaR scene mesh requires trained SuGaR model\n")
    sys.exit(1)


if __name__ == "__main__":
    main()
