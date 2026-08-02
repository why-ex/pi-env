#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

flake=flake.nix

# diffutils provides diff and diff3; patch provides patch. Keep them scoped to
# the development shell rather than the packaged runtime closure.
test_grep 'mkDevShellTools = pkgs:' "$flake"
test_grep 'diffutils' "$flake"
test_grep 'patch' "$flake"
test_grep 'packages = (mkRuntime pkgs) ++ (mkDevShellTools pkgs) ++ \[' "$flake"
test_grep 'mkDevShellTools' "$flake"

runtime_block="$(awk '
  /mkRuntime = pkgs:/ { in_runtime = 1 }
  in_runtime { print }
  in_runtime && /^        \];$/ { exit }
' "$flake")"
if printf '%s\n' "$runtime_block" | grep -Eq '^          (diffutils|patch)$'; then
  test_fail 'diffutils/patch were added to mkRuntime instead of devshell-only tooling'
fi

# README documents the smoke command contributors can run from a machine with
# Nix available.
test_grep 'diff diff3 patch' README.md
test_grep "nix develop --command bash -lc 'command -v diff diff3 patch'" README.md

if command -v nix >/dev/null 2>&1; then
  PI_EN_QUIET=1 nix develop --command bash -lc '
    set -euo pipefail
    command -v diff >/dev/null
    command -v diff3 >/dev/null
    command -v patch >/dev/null
  '
else
  test_note 'nix not available; static flake and README checks covered devshell tool declaration'
fi
