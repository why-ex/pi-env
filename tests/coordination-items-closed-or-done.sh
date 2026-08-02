#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PATH="$repo_root/scripts:$PATH"

coord_dir="$repo_root/.pi-en/coordination"
if [ ! -d "$coord_dir" ]; then
  coord_dir="$repo_root/coordination"
fi

pi-en-coord-lint \
  --coord-dir "$coord_dir" \
  --project-root "$repo_root" \
  --require-done-or-closed
