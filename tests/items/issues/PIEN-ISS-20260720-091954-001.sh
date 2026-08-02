#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

skill="pi-skill-templates/pi-en-flake-integration/SKILL.md"
test_file_exists "$skill"

test_grep '^# Pi-en Flake Integration' "$skill"
test_grep 'pien recipe flake-agent-shell' "$skill"
test_grep 'pi-en.lib.mkPiShell' "$skill"
test_grep 'not satisfy this request by' "$skill"
test_grep 'merely named `agent`' "$skill"
test_grep 'Preserve the existing flake structure' "$skill"
test_grep 'FHS/container builders' "$skill"
test_grep 'Preserve existing devshells, shell hooks' "$skill"
test_grep 'agent = existingDevShells.default;' "$skill"
test_grep 'avoid replacing project-owned' "$skill"
test_grep 'Ask clarifying questions' "$skill"

test_grep 'cp -R ${./pi-skill-templates} "$out/share/pi-en/pi-skill-templates"' flake.nix
test_grep 'cp -R "$source_root/pi-skill-templates" "$share_dir/pi-skill-templates"' scripts/pi-en-install-non-nix
test_grep 'find "$share_dir/scripts" "$share_dir/role-manager" "$share_dir/pi-skill-templates"' scripts/pi-en-install-non-nix

test_grep 'Use the pi-en-flake-integration skill' README.md
test_grep 'pi-skill-templates/pi-en-flake-integration/' README.md

support_copy="$repo_root/pi-skill-templates"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cp -R "$support_copy" "$tmpdir/pi-skill-templates"
test_file_exists "$tmpdir/pi-skill-templates/pi-en-flake-integration/SKILL.md"

test_note 'pi-en flake integration skill, packaging hooks, and docs are covered'
