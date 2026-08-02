#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

output="$tmpdir/requirements.md"
scripts/pi-en-coord-generate-requirements >"$output"

heading='### 3.2 Flake and package requirements'
count="$(grep -F -c "$heading" "$output")"
[ "$count" = 1 ] || test_fail "expected one flake section heading, got $count"

if awk '
  /^### [345]\.[0-9]+ / {
    if (seen[$0]++) {
      printf "duplicate generated section heading: %s\n", $0 > "/dev/stderr"
      exit 1
    }
  }
' "$output"; then
  :
else
  test_fail 'generated requirements reopened a section heading'
fi

uc_line="$(grep -nF '#### UC-024 Serial role automation workflow' "$output" | cut -d: -f1)"
flake_line="$(grep -nF '### 3.2 Flake and package requirements' "$output" | cut -d: -f1)"
[ -n "$uc_line" ] || test_fail 'missing UC-024 in generated requirements'
[ -n "$flake_line" ] || test_fail 'missing 3.2 section in generated requirements'
[ "$uc_line" -lt "$flake_line" ] || \
  test_fail 'UC-024 should remain in the 3.1 section before 3.2 opens'
