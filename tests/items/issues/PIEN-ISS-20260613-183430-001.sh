#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

flake=flake.nix
launcher=scripts/pi-en-launcher

test_grep 'PI_EN_ROLE_MANAGER_AUTO' "$launcher"
test_grep 'printf.*--tools.*--continue.*-e.*role_manager_package' "$launcher"
test_grep 'PI_EN_ROLE_MANAGER_PACKAGE:-${roleManagerPackage}' "$flake"
test_grep 'exec_pi_bwrap_default' "$launcher"
test_grep 'PI_EN_BWRAP_DEFAULT_TOOLS' "$launcher"
test_grep 'roleManagerPackage = mkRoleManagerPackage pkgs;' "$flake"

test_grep 'PI_EN_ROLE_MANAGER_AUTO=0' README.md
test_grep 'loads it by' README.md
test_grep 'PI_EN_ROLE_MANAGER_AUTO=0' role-manager/README.md

# The startup script should skip absent package paths by checking existence
# before appending Pi's per-run extension/package flag.
test_grep '\[ -e "$role_manager_package" \]' "$launcher"

echo "pi-en role-manager default tests passed"
