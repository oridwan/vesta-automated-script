#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image
from PIL import UnidentifiedImageError


def close_enough(p: tuple[int, int, int], b: tuple[int, int, int], tol: int) -> bool:
    return abs(p[0] - b[0]) <= tol and abs(p[1] - b[1]) <= tol and abs(p[2] - b[2]) <= tol


def trim_image(path: Path, tol: int, pad: int) -> bool:
    img = Image.open(path).convert("RGB")
    w, h = img.size
    px = img.load()

    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    bg = max(set(corners), key=corners.count)

    min_x, min_y = w, h
    max_x, max_y = -1, -1

    for y in range(h):
        for x in range(w):
            if not close_enough(px[x, y], bg, tol):
                if x < min_x:
                    min_x = x
                if y < min_y:
                    min_y = y
                if x > max_x:
                    max_x = x
                if y > max_y:
                    max_y = y

    if max_x < min_x or max_y < min_y:
        return False

    min_x = max(0, min_x - pad)
    min_y = max(0, min_y - pad)
    max_x = min(w - 1, max_x + pad)
    max_y = min(h - 1, max_y + pad)

    cropped = img.crop((min_x, min_y, max_x + 1, max_y + 1))
    cropped.save(path)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Trim uniform background margins from PNG")
    parser.add_argument("image", type=Path)
    parser.add_argument("--tolerance", type=int, default=10)
    parser.add_argument("--padding", type=int, default=18)
    args = parser.parse_args()

    if not args.image.is_file():
        raise SystemExit(f"Image not found: {args.image}")

    try:
        changed = trim_image(args.image, args.tolerance, args.padding)
    except (OSError, UnidentifiedImageError) as exc:
        print(f"trimmed=False file={args.image} reason={exc}")
        return 0

    print(f"trimmed={changed} file={args.image}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
