#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

def check_file(path: Path) -> str:
    if not path.is_file():
        return "missing"
    size_mb = path.stat().st_size / (1024 * 1024)
    if size_mb <= 0:
        return "empty"
    return f"ok ({size_mb:.1f} MB)"


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate PARCHG-band0/band1 files in structure folders")
    parser.add_argument("root", nargs="?", default=".", help="Root directory to scan")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    found = False
    for struct_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        parchg_dir = struct_dir / "PARCHG"
        if not parchg_dir.is_dir():
            continue
        found = True
        band0 = check_file(parchg_dir / "PARCHG-band0")
        band1 = check_file(parchg_dir / "PARCHG-band1")
        print(f"{struct_dir.name}")
        print(f"  band0: {band0}")
        print(f"  band1: {band1}")

    if not found:
        raise SystemExit(f"No PARCHG directories found under {root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
