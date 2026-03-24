#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/STRUCTURE_DIR" >&2
  exit 1
fi

STRUCTURE_DIR="$1"
EXPORT_TIMEOUT_SECONDS="${EXPORT_TIMEOUT_SECONDS:-45}"
QUIT_TIMEOUT_SECONDS="${QUIT_TIMEOUT_SECONDS:-15}"
VESTA_IMG_SCALE="${VESTA_IMG_SCALE:-2}"
VESTA_WIDTH_ANGSTROM="${VESTA_WIDTH_ANGSTROM:-48}"
TRIM_TOLERANCE="${TRIM_TOLERANCE:-10}"
TRIM_PADDING="${TRIM_PADDING:-72}"
DELETE_SUPERCELL_FILES="${DELETE_SUPERCELL_FILES:-1}"
LOCK_DIR="${TMPDIR:-/tmp}/vesta-supercell-one.lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_vesta_cmd() {
  if [[ -n "${VESTA_CMD:-}" ]]; then
    echo "$VESTA_CMD"
    return 0
  fi

  local candidates=(
    "$(command -v VESTA 2>/dev/null || true)"
    "$(command -v vesta 2>/dev/null || true)"
    "/Applications/VESTA.app/Contents/MacOS/VESTA"
  )

  local c
  for c in "${candidates[@]}"; do
    if [[ -n "$c" && -x "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

wait_for_stable_file() {
  local output_file="$1"
  local size1=0
  local size2=0

  for ((i = 0; i < 5; i++)); do
    size1=$(stat -f%z "$output_file" 2>/dev/null || echo 0)
    sleep 1
    size2=$(stat -f%z "$output_file" 2>/dev/null || echo 0)
    if [[ "$size1" -gt 0 && "$size1" -eq "$size2" ]]; then
      return 0
    fi
  done

  return 1
}

trim_output() {
  local output_file="$1"
  python3 "$SCRIPT_DIR/trim_png_whitespace.py" \
    "$output_file" \
    --tolerance "$TRIM_TOLERANCE" \
    --padding "$TRIM_PADDING" \
    >/dev/null 2>&1 || true
}

render_band_views() {
  local input_file="$1"
  local output_dir="$2"
  local output_c="$output_dir/along_c.png"
  local output_a="$output_dir/along_a.png"
  local output_b="$output_dir/along_b.png"
  local cmd=()

  rm -f "$output_a" "$output_b" "$output_c"

  cmd=(
    "$VESTA_BIN"
    -open "$input_file"
    -scale_width_to "$VESTA_WIDTH_ANGSTROM"
    -flush
    -export_img "scale=${VESTA_IMG_SCALE}" "$output_c"
    -rotate_y 90
    -flush
    -export_img "scale=${VESTA_IMG_SCALE}" "$output_a"
    -rotate_y -90
    -rotate_x 90
    -flush
    -export_img "scale=${VESTA_IMG_SCALE}" "$output_b"
    -close
  )

  WXSUPPRESS_SIZER_FLAGS_CHECK=1 "${cmd[@]}" >/dev/null 2>&1 &
  local vesta_pid=$!

  for ((i = 0; i < EXPORT_TIMEOUT_SECONDS; i++)); do
    if [[ -f "$output_a" && -f "$output_b" && -f "$output_c" ]]; then
      break
    fi
    sleep 1
  done

  if [[ ! -f "$output_a" || ! -f "$output_b" || ! -f "$output_c" ]]; then
    echo "    Export timed out after ${EXPORT_TIMEOUT_SECONDS}s for $input_file" >&2
    kill -TERM "$vesta_pid" 2>/dev/null || true
    wait "$vesta_pid" 2>/dev/null || true
    return 1
  fi

  for ((i = 0; i < QUIT_TIMEOUT_SECONDS; i++)); do
    if ! kill -0 "$vesta_pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done

  if kill -0 "$vesta_pid" 2>/dev/null; then
    echo "    VESTA did not exit after ${QUIT_TIMEOUT_SECONDS}s; asking it to quit." >&2
    kill -TERM "$vesta_pid" 2>/dev/null || true
    sleep 2
  fi

  if kill -0 "$vesta_pid" 2>/dev/null; then
    echo "    VESTA still active; forcing quit." >&2
    kill -KILL "$vesta_pid" 2>/dev/null || true
  fi

  local status=0
  wait "$vesta_pid" 2>/dev/null || status=$?
  if [[ "$status" -ne 0 && ( ! -f "$output_a" || ! -f "$output_b" || ! -f "$output_c" ) ]]; then
    return "$status"
  fi

  for output_file in "$output_a" "$output_b" "$output_c"; do
    wait_for_stable_file "$output_file" || true
    trim_output "$output_file"
    echo "    Wrote: $output_file"
  done
}

if ! STRUCTURE_DIR="$(cd "$STRUCTURE_DIR" && pwd)"; then
  echo "Structure directory not found: $1" >&2
  exit 1
fi

PARCHG_DIR="$STRUCTURE_DIR/PARCHG"
if [[ ! -d "$PARCHG_DIR" ]]; then
  echo "Missing PARCHG directory: $PARCHG_DIR" >&2
  exit 1
fi

if ! VESTA_BIN="$(resolve_vesta_cmd)"; then
  echo "Could not find VESTA. Set VESTA_CMD." >&2
  exit 1
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another VESTA supercell run is already active: $LOCK_DIR" >&2
  exit 1
fi

cleanup() {
  rm -rf "$LOCK_DIR"
}
trap cleanup EXIT

echo "Processing one structure safely: $STRUCTURE_DIR"

for band in band0 band1; do
  input_file="$PARCHG_DIR/PARCHG-$band"
  if [[ ! -f "$input_file" ]]; then
    echo "  - Skip $band (missing $input_file)"
    continue
  fi

  supercell_file="$PARCHG_DIR/PARCHG-$band-2x2x2"
  render_input="$input_file"
  output_dir="$PARCHG_DIR/vesta_imgs_${band}"

  echo "  - Building supercell ($band): $supercell_file"
  if python3 "$SCRIPT_DIR/make_parchg_supercell.py" "$input_file" "$supercell_file"; then
    render_input="$supercell_file"
    output_dir="$PARCHG_DIR/vesta_imgs_${band}_2x2x2"
  else
    echo "  - Supercell build failed for $band; falling back to raw file."
    rm -f "$supercell_file"
  fi

  mkdir -p "$output_dir"

  echo "    Exporting along_c, along_a, along_b in one VESTA run"
  band_failed=0
  if ! render_band_views "$render_input" "$output_dir"; then
    echo "  - Stop $band after export failure"
    band_failed=1
  fi

  if [[ "$DELETE_SUPERCELL_FILES" == "1" ]]; then
    rm -f "$supercell_file"
  fi

  if [[ "$band_failed" -ne 0 ]]; then
    exit 1
  fi
done

echo "Done: $STRUCTURE_DIR"
