#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bash scripts/pien recipe flake-agent-shell >"$tmpdir/recipe.out"
skill="pi-skill-templates/pi-en-flake-integration/SKILL.md"

# Recipe guidance covers the selector convention and both accepted patterns.
test_grep 'always expose devShells.<system>.agent' "$tmpdir/recipe.out"
test_grep 'Dedicated agent shell pattern' "$tmpdir/recipe.out"
test_grep 'agent = pi-en.lib.mkPiShell {' "$tmpdir/recipe.out"
test_grep 'Alias pattern when the default shell is already pi-en-aware' "$tmpdir/recipe.out"
test_grep 'agent = existingDevShells.default;' "$tmpdir/recipe.out"
test_grep 'Suggested prompt when asking Pi to modify an external complex flake' "$tmpdir/recipe.out"
test_grep 'do not create a project-native agentProfile' "$tmpdir/recipe.out"

# Skill guidance tells agents to preserve defaults and add/preserve .#agent.
test_grep 'preserve the `.#agent` selector' "$skill"
test_grep 'avoid replacing project-owned' "$skill"
test_grep 'agent = existingDevShells.default;' "$skill"
test_grep 'Suggested user prompt' "$skill"
test_grep 'do not create a project-native agentProfile' "$skill"

# README and design docs describe runtime selection and visible failure.
test_grep 'Nix runtime startup prefers `.#agent`' README.md
test_grep 'falls back to the default shell when `.#agent` is absent' README.md
test_grep 'fails visibly if an existing or explicitly selected `.#agent`' README.md
test_grep 'Suggested prompt for external complex flakes' README.md
test_grep 'do not create a project-native agentProfile' README.md
test_grep 'existing but broken `.#agent`' designs/nix-runtime.md

test_note 'agent shell selector recipe, skill, and docs are covered'
