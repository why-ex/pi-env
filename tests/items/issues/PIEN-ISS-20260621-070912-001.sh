#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# This item changed the pi-en-bwrap root-level /workspace/agent-remotes
# compatibility behavior. The exercised coverage lives in the pi-en-bwrap item
# suites that were cited by review and verification for this item; keep this
# item-matched entry point so coordination lint can require direct evidence.
./tests/items/issues/PIEN-ISS-20260618-174924-001.sh
./tests/items/issues/PIEN-ISS-20260620-113313-001.sh

printf 'PIEN-ISS-20260621-070912-001 passed\n'
