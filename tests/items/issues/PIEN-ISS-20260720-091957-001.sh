#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# This documentation item is covered by the flake recipe command test,
# flake integration skill test, and design coverage checks named in its
# verification history.
tests/items/issues/PIEN-ISS-20260720-091951-001.sh
tests/items/issues/PIEN-ISS-20260720-091954-001.sh
tests/design-covers.sh >/dev/null

printf 'PIEN-ISS-20260720-091957-001 item test passed\n'
