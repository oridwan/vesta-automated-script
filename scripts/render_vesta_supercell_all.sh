#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-electride_candidates}"
LOCK_DIR="${TMPDIR:-/tmp}/vesta-supercell-all.lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"; then
  echo "Root directory not found: ${1:-electride_candidates}" >&2
  exit 1
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another VESTA supercell batch is already active: $LOCK_DIR" >&2
  exit 1
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

found_any=0
failures=0
while IFS= read -r parchg_dir; do
  found_any=1
  structure_dir="$(dirname "$parchg_dir")"
  echo "Processing structure: $structure_dir"
  if ! bash "$SCRIPT_DIR/render_vesta_supercell_one.sh" "$structure_dir"; then
    echo "Skipping failed structure: $structure_dir" >&2
    failures=$((failures + 1))
  fi
done < <(find "$ROOT_DIR" -type d -name PARCHG | sort)

if [[ "$found_any" -eq 0 ]]; then
  echo "No PARCHG directories found under: $ROOT_DIR" >&2
  exit 1
fi

if [[ "$failures" -gt 0 ]]; then
  echo "Completed with $failures failed structure(s)." >&2
fi
