#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# The sandbox must carry an explicit marker into Pi and pienv shell payloads.
grep -Fq -- '--setenv PI_ENV_INSIDE_SANDBOX 1' scripts/pi-env-bwrap

# mkPiShell must deliberately pass the pienv runtime command set through the
# validated Nix-store extra path, with coordination helpers gated by the
# includeCoordinationHelpers option.
grep -Fq 'piSandboxCommandPath = pkgs.lib.makeBinPath' flake.nix
grep -Fq 'export PI_ENV_NIX_SANDBOX_COMMAND_PATH=' flake.nix
grep -Fq 'coordinationPackages = if includeCoordinationHelpers then agentCoordCommands else [ ];' flake.nix
grep -Fq '] ++ coordinationPackages);' flake.nix

# Dispatcher coverage verifies that in-sandbox diagnostics/help/recipe/coord
# paths do not invoke the outer launcher, while outer-only commands are rejected.
tests/pienv-dispatcher.sh >/dev/null

printf 'PIENV-ISS-20260725-125514-001 item test passed\n'
