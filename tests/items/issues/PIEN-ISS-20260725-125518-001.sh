#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# The umbrella documentation item is covered by the two boundary item tests and
# the executable dispatcher test referenced in its verification history.
tests/items/issues/PIEN-ISS-20260725-125514-001.sh
tests/items/issues/PIEN-ISS-20260725-125516-001.sh
tests/pien-dispatcher.sh >/dev/null

grep -Fq 'sandbox-safe subset' README.md
grep -Fq 'pien coord bootstrap --print-only' README.md

printf 'PIEN-ISS-20260725-125518-001 item test passed\n'
