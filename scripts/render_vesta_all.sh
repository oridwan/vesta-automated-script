#!/usr/bin/env bash
set -euo pipefail

# This script renders VESTA (Visualization for Electronic STructural Analysis) images.
#
# Usage:
#   ./render_vesta_all.sh [ROOT_DIR]
#
# Parameters:
#   ROOT_DIR                    Directory containing VESTA files to export
#                               Default: "VESTA_EXPORT_SELECTED"
#
# Environment Variables (optional):
#   EXPORT_TIMEOUT_SECONDS      Timeout for VESTA export operation in seconds
#                               Default: 30
#   QUIT_TIMEOUT_SECONDS        Timeout for VESTA quit operation in seconds
#                               Default: 10
#   VESTA_IMG_SCALE             Image scale factor for rendering
#                               Default: 2
#   VESTA_WIDTH_ANGSTROM        Width of the rendered structure in Angstroms
#                               Default: 30
#   TRIM_TOLERANCE              Tolerance for image trimming in pixels
#                               Default: 10
#   TRIM_PADDING                Padding to add after trimming in pixels
#                               Default: 36
#   TMPDIR                      Temporary directory for lock files
#                               Default: /tmp
#
# Examples:
#   ./render_vesta_all.sh
#   ./render_vesta_all.sh /path/to/vesta/files
#   EXPORT_TIMEOUT_SECONDS=60 VESTA_IMG_SCALE=3 ./render_vesta_all.sh
ROOT_DIR="${1:-electride_candidates}"
EXPORT_TIMEOUT_SECONDS="${EXPORT_TIMEOUT_SECONDS:-15}"
QUIT_TIMEOUT_SECONDS="${QUIT_TIMEOUT_SECONDS:-10}"
VESTA_IMG_SCALE="${VESTA_IMG_SCALE:-2}"
VESTA_WIDTH_ANGSTROM="${VESTA_WIDTH_ANGSTROM:-30}"
TRIM_TOLERANCE="${TRIM_TOLERANCE:-10}"
TRIM_PADDING="${TRIM_PADDING:-36}"
LOCK_DIR="${TMPDIR:-/tmp}/vesta-render.lock"
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

rotation_args_for_axis() {
  local axis="$1"
  case "$axis" in
    a) printf '%s\n' "-rotate_y" "90" ;;
    b) printf '%s\n' "-rotate_x" "90" ;;
    c) ;;
    *)
      echo "Unsupported axis: $axis" >&2
      return 1
      ;;
  esac
}

render_view() {
  local input_file="$1"
  local output_file="$2"
  local axis="$3"

  mkdir -p "$(dirname "$output_file")"
  rm -f "$output_file"

  local rotation_args=()
  local cmd=()
  while IFS= read -r arg; do
    [[ -n "$arg" ]] && rotation_args+=("$arg")
  done < <(rotation_args_for_axis "$axis")

  cmd=("$VESTA_BIN" -open "$input_file")
  if ((${#rotation_args[@]} > 0)); then
    cmd+=("${rotation_args[@]}")
  fi
  cmd+=(-scale_width_to "$VESTA_WIDTH_ANGSTROM" -flush -export_img "scale=${VESTA_IMG_SCALE}" "$output_file" -close)

  WXSUPPRESS_SIZER_FLAGS_CHECK=1 "${cmd[@]}" >/dev/null 2>&1 &
  local vesta_pid=$!

  for ((i = 0; i < EXPORT_TIMEOUT_SECONDS; i++)); do
    if [[ -f "$output_file" ]]; then
      break
    fi
    sleep 1
  done

  if [[ ! -f "$output_file" ]]; then
    echo "    Export timed out after ${EXPORT_TIMEOUT_SECONDS}s: $output_file" >&2
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
  if [[ "$status" -ne 0 && ! -f "$output_file" ]]; then
    return "$status"
  fi

  local size1=0
  local size2=0
  for ((i = 0; i < 5; i++)); do
    size1=$(stat -f%z "$output_file" 2>/dev/null || echo 0)
    sleep 1
    size2=$(stat -f%z "$output_file" 2>/dev/null || echo 0)
    if [[ "$size1" -gt 0 && "$size1" -eq "$size2" ]]; then
      break
    fi
  done

  python3 "$SCRIPT_DIR/trim_png_whitespace.py" \
    "$output_file" \
    --tolerance "$TRIM_TOLERANCE" \
    --padding "$TRIM_PADDING" \
    >/dev/null 2>&1 || true

  echo "    Wrote: $output_file"
}

if ! ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"; then
  echo "Root directory not found: ${1:-VESTA_EXPORT_SELECTED}" >&2
  exit 1
fi

if ! VESTA_BIN="$(resolve_vesta_cmd)"; then
  echo "Could not find VESTA. Set VESTA_CMD." >&2
  exit 1
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another VESTA render run is already active: $LOCK_DIR" >&2
  exit 1
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

found_any=0
while IFS= read -r parchg_dir; do
  found_any=1
  echo "Processing: $parchg_dir"

  for band in band0 band1; do
    input_file="$parchg_dir/PARCHG-$band"
    if [[ ! -f "$input_file" ]]; then
      echo "  - Skip $band (missing $input_file)"
      continue
    fi

    output_dir="$parchg_dir/vesta_imgs_$band"
    echo "  - Rendering $band -> $output_dir"

    for axis in a b c; do
      output_file="$output_dir/along_${axis}.png"
      echo "    Exporting along_${axis}"
      if ! render_view "$input_file" "$output_file" "$axis"; then
        echo "  - Skip $band (failed on along_${axis})"
        break
      fi
    done
  done
done < <(find "$ROOT_DIR" -type d -name PARCHG | sort)

if [[ "$found_any" -eq 0 ]]; then
  echo "No PARCHG directories found under: $ROOT_DIR" >&2
  exit 1
fi
