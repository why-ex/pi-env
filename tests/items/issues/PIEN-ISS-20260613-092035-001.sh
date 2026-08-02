#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

tests/role-manager-schema.sh
tests/role-manager-package.sh
tests/role-manager-commands.sh

printf 'PIEN-ISS-20260613-092035-001 passed\n'
