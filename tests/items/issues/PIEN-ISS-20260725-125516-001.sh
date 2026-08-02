#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# Item-matched regression coverage for in-sandbox pien command boundaries.
# The dispatcher test uses fake lower-level commands, including a fake nix
# command, so these cases do not require an interactive Pi or Nix session.
grep -Fq 'run_sandbox_safe_no_dispatch_case help' tests/pien-dispatcher.sh
grep -Fq 'run_sandbox_safe_no_dispatch_case help coord' tests/pien-dispatcher.sh
grep -Fq 'run_sandbox_context_case' tests/pien-dispatcher.sh
grep -Fq 'coord bootstrap --print-only' tests/pien-dispatcher.sh
grep -Fq 'run_sandbox_outer_only_case --runtime nix' tests/pien-dispatcher.sh
grep -Fq 'run_sandbox_outer_only_case shell -- -lc true' tests/pien-dispatcher.sh
grep -Fq 'run_sandbox_outer_only_case sandbox --help' tests/pien-dispatcher.sh
grep -Fq 'run_sandbox_outer_only_case install --prefix /tmp/pien' tests/pien-dispatcher.sh
grep -Fq 'run_sandbox_outer_only_case uninstall --prefix /tmp/pien' tests/pien-dispatcher.sh

# mkPiShell must expose the sandbox-safe pien entrypoint in the sandbox PATH,
# and coordination helpers must be included only through the option-gated
# coordinationPackages list.
grep -Fq 'pien = mkPien pkgs { inherit includeCoordinationHelpers; };' flake.nix
grep -Fq 'coordinationPackages = if includeCoordinationHelpers then agentCoordCommands else [ ];' flake.nix
grep -Fq 'piSandboxCommandPath = pkgs.lib.makeBinPath ([' flake.nix
sandbox_path_block="$(awk '
  /piSandboxCommandPath = pkgs\.lib\.makeBinPath \(\[/ { capture = 1 }
  capture { print }
  capture && /] \+\+ coordinationPackages\);/ { exit }
' flake.nix)"
if ! grep -Fq 'pien' <<<"$sandbox_path_block"; then
  echo 'pien missing from mkPiShell sandbox command path' >&2
  exit 1
fi
for forbidden in piBwrap piEn piEnShell; do
  if grep -Fq "$forbidden" <<<"$sandbox_path_block"; then
    echo "$forbidden leaked into mkPiShell sandbox command path" >&2
    exit 1
  fi
done

# Re-run the executable dispatcher coverage to prove outer-terminal behavior is
# unchanged when PI_EN_INSIDE_SANDBOX is absent and sandbox boundaries hold when
# the marker is present.
tests/pien-dispatcher.sh >/dev/null

printf 'PIEN-ISS-20260725-125516-001 item test passed\n'
