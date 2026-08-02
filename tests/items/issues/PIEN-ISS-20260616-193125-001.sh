#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# This item extends the serial role smoke suite with watched-auto-exit
# selector, command-rendering, and role-manager shutdown-hook assertions.
exec tests/items/issues/PIEN-ISS-20260615-175845-001.sh
