#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

fixed_grep() {
  local needle path
  needle="$1"
  path="$2"
  grep -F -- "$needle" "$path" >/dev/null \
    || test_fail "missing expected text in $path: $needle"
}

fixed_absent() {
  local needle path
  needle="$1"
  path="$2"
  if grep -F -- "$needle" "$path" >/dev/null; then
    test_fail "unexpected text in $path: $needle"
  fi
}

fixed_grep 'Automatic Pi-en' README.md
fixed_grep 'workflows use the project-local working clone at `.pi-en/coordination`' README.md
fixed_grep 'External coordination working clones are not part of the' README.md
fixed_grep 'Pi-en represents them as derived operational aliases under' README.md
fixed_grep '`.pi-en-coordination.yaml` remains the source of' README.md
fixed_grep '`pi-en-bwrap` does not bind an external clone at `/coordination`' README.md

fixed_grep 'Automatic coordination working clones live' designs/bubblewrap-sandbox.md
fixed_grep 'the source of truth and materializes only derived operational aliases' designs/bubblewrap-sandbox.md
fixed_grep 'does not mount host home directories or broad' designs/bubblewrap-sandbox.md
fixed_grep 'bind-mounts only the selected bare repository' designs/bubblewrap-sandbox.md
fixed_grep 'instead of being mounted at' designs/bubblewrap-sandbox.md

fixed_grep 'project-local coordination working' designs/serial-role-automation.md
fixed_grep 'No external `--coord-dir` or `/coordination` working-clone path as a normal' designs/serial-role-automation.md
fixed_grep 'PI_EN_BWRAP_COORDINATION_DIR="$project_root/.pi-en/coordination"' designs/serial-role-automation.md
fixed_absent 'PI_EN_BWRAP_COORDINATION_DIR="$coordination_dir"' designs/serial-role-automation.md

fixed_grep 'at the project-local `.pi-en/coordination` working clone by default. External' pi-skill-templates/agent-coordination/SKILL.md
fixed_grep 'coordination working clones are not part of the automatic Pi-en workflow' pi-skill-templates/agent-coordination/SKILL.md
fixed_grep '`.pi-en-coordination.yaml` is the source of truth' pi-skill-templates/agent-coordination/SKILL.md
fixed_grep '`.pi-en/agent-remotes/` entries for those' pi-skill-templates/agent-coordination/SKILL.md
fixed_grep 'pi-en-coord-lint --coord-dir .pi-en/coordination --project-root .' pi-skill-templates/agent-coordination/SYNC_PROTOCOL.md

fixed_grep 'For fresh Pi-en projects and automatic workflows' designs/agent-coordination.md
fixed_grep 'find the clone at `<project>/.pi-en/coordination`' designs/agent-coordination.md
fixed_grep 'External coordination working clones are' designs/agent-coordination.md
fixed_grep '`.pi-en/agent-remotes/` entries' designs/agent-coordination.md
fixed_absent 'unless PI_EN_COORD_DIR, the user, or environment says otherwise' designs/agent-coordination.md

fixed_grep 'automatic workflows require' scripts/pi-en-coord-init
fixed_grep '.pi-en-coordination.yaml remains the source of truth' scripts/pi-en-coord-init
fixed_grep 'derived aliases for external local bare remotes' scripts/pi-en-coord-clone
fixed_grep '<project>/.pi-en/coordination' scripts/pi-en-bootstrap-coordination

printf 'PIEN-ISS-20260805-173233-001 passed\n'
