#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

coord_dir="$repo_root/.pi-en/coordination"
if [ ! -d "$coord_dir" ]; then
  coord_dir="$repo_root/coordination"
fi

item_id="PIEN-ISS-20260613-103516-001"
item_path="$(scripts/pi-en-coord-cat --coord-dir "$coord_dir" --path "$item_id")"
test -f "$coord_dir/$item_path"

test "$(scripts/pi-en-coord-cat --coord-dir "$coord_dir" "$item_id")" = \
  "$(cat "$coord_dir/$item_path")"
test "$(scripts/pi-en-coord-cat --coord-dir "$coord_dir" --path "$item_path")" = "$item_path"
test "$(scripts/pi-en-coord-cat --coord-dir "$coord_dir" --path "${item_id%-001}")" = "$item_path"

if scripts/pi-en-coord-cat --coord-dir "$coord_dir" MISSING-ITEM \
  >"$tmp/cat-missing.out" 2>"$tmp/cat-missing.err"; then
  printf 'pi-en-coord-cat unexpectedly found missing item\n' >&2
  exit 1
fi
grep -q '^pi-en-coord: item not found: MISSING-ITEM$' "$tmp/cat-missing.err"

printf 'PIEN-ISS-20260613-103516-001 passed\n'
