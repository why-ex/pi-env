#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

# Item PIEN-ISS-20260616-171657-001 specifically requires executable
# coverage that serial role launches include the role_cycle_done tool. The
# serial role smoke test asserts both the default allowlist and custom
# --tools paths append role_cycle_done, so delegate to that scenario suite
# from this item-matched entry point.
exec "$repo_root/tests/items/issues/PIEN-ISS-20260615-175845-001.sh"
