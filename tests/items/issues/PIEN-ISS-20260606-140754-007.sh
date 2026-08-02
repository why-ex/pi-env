#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
"$repo_root/tests/pi-en-coord-blackbox.sh"
"$repo_root/tests/role-manager-commands.sh"
printf 'PIEN-ISS-20260606-140754-007 passed\n'
