#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# The sandbox must carry an explicit marker into Pi and pien shell payloads.
grep -Fq -- '--setenv PI_EN_INSIDE_SANDBOX 1' scripts/pi-en-bwrap

# mkPiShell must deliberately pass only the sandbox-aware pien runtime command
# set through the validated Nix-store extra path, with coordination helpers
# gated by the includeCoordinationHelpers option.  Outer runtime launchers stay
# available in the dev shell but must not be added to PI_EN_BWRAP_EXTRA_PATH.
grep -Fq 'piSandboxCommandPath = pkgs.lib.makeBinPath' flake.nix
grep -Fq 'export PI_EN_NIX_SANDBOX_COMMAND_PATH=' flake.nix
grep -Fq 'copy_env PI_EN_NIX_SANDBOX_COMMAND_PATH' scripts/pi-en-bwrap
grep -Fq 'coordinationPackages = if includeCoordinationHelpers then agentCoordCommands else [ ];' flake.nix
grep -Fq '] ++ coordinationPackages);' flake.nix
extra_path_block="$(awk '
  /extraPackagePath = pkgs\.lib\.makeBinPath/ { capture = 1 }
  capture { print }
  capture && /] \+\+ coordinationPackages\);/ { exit }
' flake.nix)"
for forbidden in piBwrap piEn piEnShell; do
  if grep -Fq "$forbidden" <<<"$extra_path_block"; then
    echo "$forbidden leaked into PI_EN_BWRAP_EXTRA_PATH inputs" >&2
    exit 1
  fi
done
if ! grep -Fq 'pien' <<<"$extra_path_block"; then
  echo 'pien missing from PI_EN_BWRAP_EXTRA_PATH inputs' >&2
  exit 1
fi

# Dispatcher coverage verifies that in-sandbox diagnostics/help/recipe/coord
# paths do not invoke the outer launcher, while outer-only commands are rejected.
tests/pien-dispatcher.sh >/dev/null

printf 'PIEN-ISS-20260725-125514-001 item test passed\n'
