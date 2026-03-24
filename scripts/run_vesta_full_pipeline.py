#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent


def run_step(cmd: list[str], *, cwd: Path, label: str, env: dict[str, str] | None = None) -> None:
    print(f"[run] {label}")
    print(f"       {' '.join(cmd)}")
    try:
        subprocess.run(cmd, cwd=cwd, check=True, env=env)
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.returncode) from exc


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate inputs and build one HTML summary report from existing rendered images."
    )
    parser.add_argument(
        "root",
        nargs="?",
        default="VESTA_EXPORT_SELECTED",
        help="Root folder containing structure directories",
    )
    parser.add_argument(
        "--output",
        default="all_structures_summary.html",
        help="Output HTML path (relative to root if not absolute)",
    )
    parser.add_argument(
        "--skip-validate",
        action="store_true",
        help="Skip validating PARCHG-band0 and PARCHG-band1 before building the report",
    )
    args = parser.parse_args()

    root = Path(args.root)
    if not root.is_absolute():
        root = (REPO_ROOT / root).resolve()
    else:
        root = root.resolve()

    if not root.is_dir():
        raise SystemExit(f"Root directory not found: {root}")

    if not args.skip_validate:
        run_step(
            [sys.executable, str(SCRIPT_DIR / "validate_parchg_inputs.py"), str(root)],
            cwd=REPO_ROOT,
            label="Validate PARCHG inputs",
        )

    run_step(
        [
            sys.executable,
            str(SCRIPT_DIR / "make_structure_summary_pages.py"),
            str(root),
            "--output",
            args.output,
        ],
        cwd=REPO_ROOT,
        label="Build HTML summary",
    )

    output_path = Path(args.output)
    if not output_path.is_absolute():
        output_path = root / output_path

    print(f"[done] HTML report: {output_path.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
