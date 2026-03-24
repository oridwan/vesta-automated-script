#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from pymatgen.io.vasp import Chgcar


def build_supercell(input_path: Path, output_path: Path, dims: tuple[int, int, int]) -> None:
    chgcar = Chgcar.from_file(str(input_path))

    structure = chgcar.structure.copy()
    structure.make_supercell(dims)

    data = {
        key: np.tile(values, dims)
        for key, values in chgcar.data.items()
    }

    out = Chgcar(poscar=chgcar.poscar, data=data)
    out.structure = structure
    out.write_file(str(output_path))


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a temporary supercell PARCHG/CHGCAR file.")
    parser.add_argument("input_file", type=Path)
    parser.add_argument("output_file", type=Path)
    parser.add_argument("--dims", nargs=3, type=int, default=(2, 2, 2), metavar=("NA", "NB", "NC"))
    args = parser.parse_args()

    if not args.input_file.is_file():
        raise SystemExit(f"Input file not found: {args.input_file}")

    args.output_file.parent.mkdir(parents=True, exist_ok=True)
    try:
        build_supercell(args.input_file, args.output_file, tuple(args.dims))
    except Exception as exc:
        raise SystemExit(f"Failed to build supercell from {args.input_file}: {exc}") from exc
    print(f"Wrote: {args.output_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
