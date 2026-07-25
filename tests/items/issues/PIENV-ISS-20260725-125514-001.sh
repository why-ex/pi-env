#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# The sandbox must carry an explicit marker into Pi and pienv shell payloads.
grep -Fq -- '--setenv PI_ENV_INSIDE_SANDBOX 1' scripts/pi-env-bwrap

# mkPiShell must deliberately pass only the sandbox-aware pienv runtime command
# set through the validated Nix-store extra path, with coordination helpers
# gated by the includeCoordinationHelpers option.  Outer runtime launchers stay
# available in the dev shell but must not be added to PI_ENV_BWRAP_EXTRA_PATH.
grep -Fq 'piSandboxCommandPath = pkgs.lib.makeBinPath' flake.nix
grep -Fq 'export PI_ENV_NIX_SANDBOX_COMMAND_PATH=' flake.nix
grep -Fq 'copy_env PI_ENV_NIX_SANDBOX_COMMAND_PATH' scripts/pi-env-bwrap
grep -Fq 'coordinationPackages = if includeCoordinationHelpers then agentCoordCommands else [ ];' flake.nix
grep -Fq '] ++ coordinationPackages);' flake.nix
extra_path_block="$(awk '
  /extraPackagePath = pkgs\.lib\.makeBinPath/ { capture = 1 }
  capture { print }
  capture && /] \+\+ coordinationPackages\);/ { exit }
' flake.nix)"
for forbidden in piBwrap piEnv piEnvShell; do
  if grep -Fq "$forbidden" <<<"$extra_path_block"; then
    echo "$forbidden leaked into PI_ENV_BWRAP_EXTRA_PATH inputs" >&2
    exit 1
  fi
done
if ! grep -Fq 'pienv' <<<"$extra_path_block"; then
  echo 'pienv missing from PI_ENV_BWRAP_EXTRA_PATH inputs' >&2
  exit 1
fi

# Dispatcher coverage verifies that in-sandbox diagnostics/help/recipe/coord
# paths do not invoke the outer launcher, while outer-only commands are rejected.
tests/pienv-dispatcher.sh >/dev/null

printf 'PIENV-ISS-20260725-125514-001 item test passed\n'
