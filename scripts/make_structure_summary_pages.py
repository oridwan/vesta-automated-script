#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
from pathlib import Path
from typing import Dict, List


def parse_manifest(manifest_path: Path) -> Dict[str, str]:
    data: Dict[str, str] = {}
    if not manifest_path.is_file():
        return data

    for raw_line in manifest_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip()

    aliases = {
        "spacegroup": "space_group",
        "e_above_hull": "mattersim_e_above_hull",
        "minimum_phonon_freq": "phonon_min_frequency_thz",
        "min_phonon_freq": "phonon_min_frequency_thz",
    }
    for src, dst in aliases.items():
        if dst not in data and src in data:
            data[dst] = data[src]
    return data


def format_manifest_value(value: str | None, suffix: str = "") -> str:
    if value is None or value == "" or value.lower() == "missing":
        return "Missing"
    return f"{value}{suffix}"


def pick_band_image(parchg_dir: Path, band: str, axis: str) -> Path | None:
    candidates = [
        parchg_dir / f"vesta_imgs_{band}_2x2x2" / f"along_{axis}.png",
        parchg_dir / f"vesta_imgs_{band}" / f"along_{axis}.png",
    ]
    for image_path in candidates:
        if image_path.is_file():
            return image_path
    return None


def pick_band_dos_image(plots_dir: Path) -> Path:
    phonon = plots_dir / "phonon_band_dos.png"
    candidates = sorted(plots_dir.glob("*band_dos.png"))
    candidates = [p for p in candidates if p.name != phonon.name]
    if not candidates:
        raise FileNotFoundError(f"No band DOS png found in {plots_dir}")
    return candidates[0]


def discover_struct_dirs(root: Path) -> List[Path]:
    dirs: List[Path] = []
    for p in sorted(root.iterdir()):
        if not p.is_dir():
            continue
        parchg = p / "PARCHG"
        plots = p / "plots"
        if not parchg.is_dir() or not plots.is_dir():
            continue
        dirs.append(p)
    return dirs


def collect_assets(struct_dir: Path) -> Dict[str, Path | None]:
    parchg = struct_dir / "PARCHG"
    plots = struct_dir / "plots"
    manifest = parse_manifest(struct_dir / "MANIFEST.txt")
    try:
        band_dos = pick_band_dos_image(plots)
    except FileNotFoundError:
        band_dos = None
    return {
        "band0_a": pick_band_image(parchg, "band0", "a"),
        "band0_b": pick_band_image(parchg, "band0", "b"),
        "band0_c": pick_band_image(parchg, "band0", "c"),
        "band1_a": pick_band_image(parchg, "band1", "a"),
        "band1_b": pick_band_image(parchg, "band1", "b"),
        "band1_c": pick_band_image(parchg, "band1", "c"),
        "band_dos": band_dos,
        "phonon": (plots / "phonon_band_dos.png") if (plots / "phonon_band_dos.png").is_file() else None,
        "manifest": manifest,
    }


def relpath_str(path: Path, root: Path) -> str:
    return html.escape(path.resolve().relative_to(root.resolve()).as_posix())


def image_or_missing(path: Path | None, root: Path, alt: str, missing_text: str) -> str:
    if path is None:
        return f'<div class="missing-box">{html.escape(missing_text)}</div>'
    return f'<img src="{relpath_str(path, root)}" alt="{html.escape(alt)}">'


def build_html(root: Path, struct_dirs: List[Path]) -> str:
    parts: List[str] = []
    for sd in struct_dirs:
        assets = collect_assets(sd)
        manifest = assets["manifest"]
        metadata_html = f"""
      <dl class="meta-list">
        <div><dt>SPG</dt><dd>{html.escape(format_manifest_value(manifest.get("space_group")))}</dd></div>
        <div><dt>E above hull</dt><dd>{html.escape(format_manifest_value(manifest.get("mattersim_e_above_hull"), " eV/atom"))}</dd></div>
        <div><dt>Min phonon freq</dt><dd>{html.escape(format_manifest_value(manifest.get("phonon_min_frequency_thz"), " THz"))}</dd></div>
      </dl>"""
        if assets["band_dos"] is not None:
            band_dos_html = f'<figure><figcaption>Band DOS</figcaption><img src="{relpath_str(assets["band_dos"], root)}" alt="Band DOS"></figure>'
        else:
            band_dos_html = '<figure class="missing"><figcaption>Band DOS</figcaption><div class="missing-box">Missing band_dos image in plots/</div></figure>'
        if assets["phonon"] is not None:
            phonon_html = f'<figure><figcaption>Phonon Band DOS</figcaption><img src="{relpath_str(assets["phonon"], root)}" alt="Phonon Band DOS"></figure>'
        else:
            phonon_html = '<figure class="missing"><figcaption>Phonon Band DOS</figcaption><div class="missing-box">Missing phonon_band_dos.png in plots/</div></figure>'
        parts.append(
            f"""
<section class="structure">
  <h2>{html.escape(sd.name)}</h2>
  <div class="structure-meta">
    {metadata_html}
  </div>
  <div class="layout">
    <div class="left-panel">
      <h3>Band Charge Density</h3>
      <div class="grid">
        <figure><figcaption>Band0 along a</figcaption>{image_or_missing(assets['band0_a'], root, 'Band0 along a', 'Missing band0 along a image')}</figure>
        <figure><figcaption>Band0 along b</figcaption>{image_or_missing(assets['band0_b'], root, 'Band0 along b', 'Missing band0 along b image')}</figure>
        <figure><figcaption>Band0 along c</figcaption>{image_or_missing(assets['band0_c'], root, 'Band0 along c', 'Missing band0 along c image')}</figure>
        <figure><figcaption>Band1 along a</figcaption>{image_or_missing(assets['band1_a'], root, 'Band1 along a', 'Missing band1 along a image')}</figure>
        <figure><figcaption>Band1 along b</figcaption>{image_or_missing(assets['band1_b'], root, 'Band1 along b', 'Missing band1 along b image')}</figure>
        <figure><figcaption>Band1 along c</figcaption>{image_or_missing(assets['band1_c'], root, 'Band1 along c', 'Missing band1 along c image')}</figure>
      </div>
    </div>
    <div class="right-panel">
      <h3>Electronic + Phonon</h3>
      {band_dos_html}
      {phonon_html}
    </div>
  </div>
</section>
"""
        )

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Structure Report</title>
  <style>
    :root {{
      --bg: #f4f1ea;
      --paper: #fffdf9;
      --ink: #1f2421;
      --muted: #5b645e;
      --line: #d7d2c8;
      --panel: #f8f6f1;
      --accent: #264653;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: Georgia, "Times New Roman", serif;
      color: var(--ink);
      background:
        radial-gradient(circle at top left, #fdf8ee 0, transparent 28rem),
        linear-gradient(180deg, #f2eee6 0%, #ece7de 100%);
    }}
    main {{
      width: min(1600px, calc(100vw - 32px));
      margin: 24px auto 48px;
    }}
    header {{
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 22px;
      padding: 24px 28px;
      margin-bottom: 24px;
      box-shadow: 0 12px 30px rgba(38, 70, 83, 0.08);
    }}
    h1 {{
      margin: 0 0 8px;
      font-size: 2.1rem;
      color: var(--accent);
    }}
    p {{
      margin: 0;
      color: var(--muted);
      font-size: 1rem;
    }}
    .structure {{
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 22px;
      padding: 22px;
      margin-bottom: 24px;
      box-shadow: 0 10px 24px rgba(0, 0, 0, 0.05);
    }}
    .structure h2 {{
      margin: 0 0 16px;
      font-size: 1.65rem;
    }}
    .structure-meta {{
      margin-bottom: 16px;
      padding: 14px 16px;
      background: #fcfaf6;
      border: 1px solid var(--line);
      border-radius: 16px;
    }}
    .meta-list {{
      margin: 0;
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
    }}
    .meta-list div {{
      min-width: 0;
    }}
    .meta-list dt {{
      margin: 0 0 4px;
      font-size: 0.8rem;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--muted);
    }}
    .meta-list dd {{
      margin: 0;
      font-size: 1rem;
      color: var(--ink);
      font-weight: 600;
    }}
    .layout {{
      display: grid;
      grid-template-columns: minmax(0, 2fr) minmax(320px, 1fr);
      gap: 22px;
      align-items: start;
    }}
    .left-panel, .right-panel {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 16px;
    }}
    h3 {{
      margin: 0 0 14px;
      font-size: 1.05rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--accent);
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 14px;
    }}
    figure {{
      margin: 0;
      background: #ffffff;
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 10px;
    }}
    figcaption {{
      margin-bottom: 8px;
      font-size: 0.9rem;
      color: var(--muted);
    }}
    img {{
      display: block;
      width: 100%;
      height: auto;
      border-radius: 10px;
      background: #ffffff;
    }}
    .missing-box {{
      min-height: 260px;
      display: grid;
      place-items: center;
      border: 1px dashed var(--line);
      border-radius: 10px;
      color: var(--muted);
      font-size: 0.95rem;
      padding: 18px;
      background: #fcfaf6;
    }}
    .right-panel {{
      display: grid;
      gap: 14px;
    }}
    @media (max-width: 1100px) {{
      .layout {{
        grid-template-columns: 1fr;
      }}
    }}
    @media (max-width: 800px) {{
      main {{
        width: min(100vw - 18px, 1000px);
        margin: 10px auto 24px;
      }}
      header, .structure {{
        border-radius: 16px;
        padding: 16px;
      }}
      .meta-list {{
        grid-template-columns: 1fr;
      }}
      .grid {{
        grid-template-columns: 1fr;
      }}
    }}
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Structure Report</h1>
      <p>{len(struct_dirs)} structures included</p>
    </header>
    {''.join(parts)}
  </main>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Build one HTML report for all structures")
    parser.add_argument("root", nargs="?", default=".", help="Root folder containing structure directories")
    parser.add_argument("--output", default="all_structures_summary.html", help="Output HTML path (relative to root if not absolute)")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    struct_dirs = discover_struct_dirs(root)
    if not struct_dirs:
        raise SystemExit(f"No structure directories with PARCHG and plots found under {root}")

    out_html = Path(args.output)
    if not out_html.is_absolute():
        out_html = root / out_html
    out_html.parent.mkdir(parents=True, exist_ok=True)

    html_text = build_html(root, struct_dirs)
    out_html.write_text(html_text, encoding="utf-8")

    print(f"Found {len(struct_dirs)} structures")
    print(f"Wrote: {out_html}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
