#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# Item-matched regression coverage for in-sandbox pienv command boundaries.
# The dispatcher test uses fake lower-level commands, including a fake nix
# command, so these cases do not require an interactive Pi or Nix session.
grep -Fq 'run_sandbox_safe_no_dispatch_case help' tests/pienv-dispatcher.sh
grep -Fq 'run_sandbox_safe_no_dispatch_case help coord' tests/pienv-dispatcher.sh
grep -Fq 'run_sandbox_context_case' tests/pienv-dispatcher.sh
grep -Fq 'coord bootstrap --print-only' tests/pienv-dispatcher.sh
grep -Fq 'run_sandbox_outer_only_case --runtime nix' tests/pienv-dispatcher.sh
grep -Fq 'run_sandbox_outer_only_case shell -- -lc true' tests/pienv-dispatcher.sh
grep -Fq 'run_sandbox_outer_only_case sandbox --help' tests/pienv-dispatcher.sh
grep -Fq 'run_sandbox_outer_only_case install --prefix /tmp/pienv' tests/pienv-dispatcher.sh
grep -Fq 'run_sandbox_outer_only_case uninstall --prefix /tmp/pienv' tests/pienv-dispatcher.sh

# mkPiShell must expose the sandbox-safe pienv entrypoint in the sandbox PATH,
# and coordination helpers must be included only through the option-gated
# coordinationPackages list.
grep -Fq 'pienv = mkPienv pkgs { inherit includeCoordinationHelpers; };' flake.nix
grep -Fq 'coordinationPackages = if includeCoordinationHelpers then agentCoordCommands else [ ];' flake.nix
grep -Fq 'piSandboxCommandPath = pkgs.lib.makeBinPath ([' flake.nix
sandbox_path_block="$(awk '
  /piSandboxCommandPath = pkgs\.lib\.makeBinPath \(\[/ { capture = 1 }
  capture { print }
  capture && /] \+\+ coordinationPackages\);/ { exit }
' flake.nix)"
if ! grep -Fq 'pienv' <<<"$sandbox_path_block"; then
  echo 'pienv missing from mkPiShell sandbox command path' >&2
  exit 1
fi
for forbidden in piBwrap piEnv piEnvShell; do
  if grep -Fq "$forbidden" <<<"$sandbox_path_block"; then
    echo "$forbidden leaked into mkPiShell sandbox command path" >&2
    exit 1
  fi
done

# Re-run the executable dispatcher coverage to prove outer-terminal behavior is
# unchanged when PI_ENV_INSIDE_SANDBOX is absent and sandbox boundaries hold when
# the marker is present.
tests/pienv-dispatcher.sh >/dev/null

printf 'PIENV-ISS-20260725-125516-001 item test passed\n'
