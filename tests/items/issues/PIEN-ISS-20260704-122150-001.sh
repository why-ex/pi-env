#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
export PATH="$repo_root/scripts:$PATH"

# User-facing development docs must show repo-scoped coordination issue paths
# while keeping item-matched executable tests in type-scoped project paths.
grep -q 'repos/{repo_id}/issues/{status}' README.md
grep -q '.pi-en/coordination/repos/pi-en/issues/closed/PIEN-ISS-20260607-204155-001.yaml' README.md
grep -q 'tests/items/issues/PIEN-ISS-20260607-204155-001.sh' README.md

if grep -q '.pi-en/coordination/issues/closed/PIEN-ISS-20260607-204155-001.yaml' README.md; then
  printf 'README.md still documents legacy root issue status paths\n' >&2
  exit 1
fi

help_output="$(pi-en-coord-new --help)"
printf '%s\n' "$help_output" | grep -q 'repos/{repo_id}/issues/open/'
printf '%s\n' "$help_output" | grep -q 'requirements, todos,'
if printf '%s\n' "$help_output" | grep -q 'project-root layout only'; then
  printf 'pi-en-coord-new help still says project-root layout only\n' >&2
  exit 1
fi
if printf '%s\n' "$help_output" | grep -q 'root item folders such as issues/'; then
  printf 'pi-en-coord-new help still lists root issues folders as primary layout\n' >&2
  exit 1
fi

printf 'PIEN-ISS-20260704-122150-001 passed\n'
