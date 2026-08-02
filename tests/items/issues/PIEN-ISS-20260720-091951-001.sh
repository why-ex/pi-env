#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

pien=scripts/pien
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bash "$pien" --help >"$tmpdir/help.out"
test_grep 'pien recipe flake-agent-shell' "$tmpdir/help.out"
test_grep 'recipe              Print non-mutating integration recipes' "$tmpdir/help.out"

bash "$pien" help recipe >"$tmpdir/recipe-help.out"
test_grep 'flake-agent-shell  Print the canonical non-mutating flake .#agent shell recipe' "$tmpdir/recipe-help.out"
test_grep 'Recipes only print guidance. They do not modify project files.' "$tmpdir/recipe-help.out"

bash "$pien" recipe flake-agent-shell >"$tmpdir/recipe.out"
test_grep 'pien recipe flake-agent-shell' "$tmpdir/recipe.out"
test_grep 'does not read, edit, or write project files' "$tmpdir/recipe.out"
test_grep 'pi-en.url = "git+file:///home/me/src/pi-en";' "$tmpdir/recipe.out"
test_grep '# pi-en.url = "github:u2up/pi-en";' "$tmpdir/recipe.out"
test_grep 'outputs = { self, nixpkgs, flake-utils, pi-en, ... }:' "$tmpdir/recipe.out"
test_grep 'keep that expression on' "$tmpdir/recipe.out"
test_grep 'devShells.${system} = {' "$tmpdir/recipe.out"
test_grep '} // {' "$tmpdir/recipe.out"
test_grep 'agent = pi-en.lib.mkPiShell {' "$tmpdir/recipe.out"
test_grep 'agent = existingDevShells.default;' "$tmpdir/recipe.out"
if grep -Fq 'self.devShells.${system}' "$tmpdir/recipe.out"; then
  test_fail 'recipe must not read devShells through self and recurse'
fi
test_grep 'includeCoordinationHelpers = false;' "$tmpdir/recipe.out"
test_grep 'extraPackages = with pkgs; \[' "$tmpdir/recipe.out"
test_grep 'includeCoordinationHelpers = true;' "$tmpdir/recipe.out"
test_grep 'canonical, copyable helper' README.md
test_grep 'pien recipe flake-agent-shell' README.md

completion_output="$(bash "$pien" completion bash)"
grep -q 'recipe' <<< "$completion_output" || test_fail 'expected completion to include recipe namespace'
grep -q 'flake-agent-shell' <<< "$completion_output" || test_fail 'expected completion to include flake-agent-shell recipe'
bash -n <(printf '%s\n' "$completion_output")

test_note 'flake agent-shell recipe command, docs, and completion are covered'
