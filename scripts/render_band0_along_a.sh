#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 /path/to/PARCHG-band0 /path/to/output.png" >&2
  exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"
EXPORT_TIMEOUT_SECONDS="${EXPORT_TIMEOUT_SECONDS:-30}"
QUIT_TIMEOUT_SECONDS="${QUIT_TIMEOUT_SECONDS:-10}"

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

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Input file not found: $INPUT_FILE" >&2
  exit 1
fi

if ! VESTA_BIN="$(resolve_vesta_cmd)"; then
  echo "Could not find VESTA. Set VESTA_CMD." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
rm -f "$OUTPUT_FILE"

WXSUPPRESS_SIZER_FLAGS_CHECK=1 "$VESTA_BIN" \
  -open "$INPUT_FILE" \
  -rotate_y 90 \
  -flush \
  -export_img "scale=${VESTA_IMG_SCALE:-2}" "$OUTPUT_FILE" \
  -close \
  >/dev/null 2>&1 &
VESTA_PID=$!

for ((i = 0; i < EXPORT_TIMEOUT_SECONDS; i++)); do
  if [[ -f "$OUTPUT_FILE" ]]; then
    break
  fi
  sleep 1
done

if [[ ! -f "$OUTPUT_FILE" ]]; then
  echo "Export timed out after ${EXPORT_TIMEOUT_SECONDS}s: $OUTPUT_FILE" >&2
  kill -TERM "$VESTA_PID" 2>/dev/null || true
  wait "$VESTA_PID" 2>/dev/null || true
  exit 1
fi

if kill -0 "$VESTA_PID" 2>/dev/null; then
  kill -TERM "$VESTA_PID" 2>/dev/null || true
fi

for ((i = 0; i < QUIT_TIMEOUT_SECONDS; i++)); do
  if ! kill -0 "$VESTA_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done

if kill -0 "$VESTA_PID" 2>/dev/null; then
  echo "VESTA did not exit after ${QUIT_TIMEOUT_SECONDS}s; forcing quit." >&2
  kill -KILL "$VESTA_PID" 2>/dev/null || true
fi

wait "$VESTA_PID" 2>/dev/null || status=$?
if [[ "${status:-0}" -ne 0 && ! -f "$OUTPUT_FILE" ]]; then
  exit "$status"
fi

echo "Wrote: $OUTPUT_FILE"
