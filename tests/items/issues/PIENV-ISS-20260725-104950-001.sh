#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

pienv=scripts/pienv
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

coord_help_out="$tmpdir/pienv-coord-bootstrap.help"
bash "$pienv" coord bootstrap --help >"$coord_help_out"
test_grep '--domain-generated-file PATH' "$coord_help_out"
test_grep 'repos/<repo_id>/REPO.md domain_generated_files' "$coord_help_out"
test_grep 'repeatable, preserving first occurrence order' "$coord_help_out"
test_grep '--generated-requirements-docs' "$coord_help_out"
test_grep '--domain-generated-file REQUIREMENTS.md' "$coord_help_out"
test_grep '--domain-generated-file REQUIREMENTS_COVERAGE.md' "$coord_help_out"

help_coord_out="$tmpdir/pienv-help-coord-bootstrap.help"
bash "$pienv" help coord bootstrap >"$help_coord_out"
test_grep '--domain-generated-file PATH' "$help_coord_out"
test_grep 'repos/<repo_id>/REPO.md domain_generated_files' "$help_coord_out"
test_grep 'repeatable, preserving first occurrence order' "$help_coord_out"
test_grep '--generated-requirements-docs' "$help_coord_out"
test_grep '--domain-generated-file REQUIREMENTS.md' "$help_coord_out"
test_grep '--domain-generated-file REQUIREMENTS_COVERAGE.md' "$help_coord_out"

completion_out="$tmpdir/pienv-completion.bash"
bash "$pienv" completion bash >"$completion_out"
test_grep 'coord\\ bootstrap) option_words=.*--domain-generated-file' "$completion_out"
test_grep 'coord\\ bootstrap) option_words=.*--generated-requirements-docs' "$completion_out"

test_grep 'During `pienv coord bootstrap`, pass repeatable' README.md
test_grep 'implementation repo manifest.*domain_generated_files' README.md
test_grep 'repo-root-relative and must not contain `..` traversal components' README.md
test_grep 'duplicates removed in' README.md
test_grep 'They do' README.md
test_grep 'not imply `--register-repo`' README.md
test_grep 'or change the' README.md
test_grep 'coordination `--project`/`--project-key` domain semantics' README.md

test_note 'pienv coord bootstrap generated-file help, completion, and docs are covered'
