#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PI_EN_COORD_TEMPLATE_DIR="$repo_root/pi-skill-templates/agent-coordination"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
git config --global user.name "Coordination Test"
git config --global user.email "coordination-test@example.invalid"
unset PI_EN_COORD_REMOTE PI_EN_COORD_WORKSPACE \
  PI_EN_COORD_DIR PI_EN_COORD_AGENT_ID PI_EN_COORD_PROJECT PI_EN_COORD_PROJECT_KEY PI_EN_COORD_ROLE

print_project="$tmp/print-project"
mkdir -p "$print_project"
git -C "$print_project" init -q
pi-en-bootstrap-coordination \
  --project-root "$print_project" \
  --project print-demo \
  --project-key PRINT \
  --agent-id agent-a \
  --print-only >"$tmp/print-plan.txt"
grep -F "Root:                        $print_project/.pi-en/agent-remotes" \
  "$tmp/print-plan.txt" >/dev/null
grep -F "Coordination clone dir:      $print_project/.pi-en/coordination" \
  "$tmp/print-plan.txt" >/dev/null
test ! -e "$print_project/.pi-en"

init_project="$tmp/init-project"
mkdir -p "$init_project"
git -C "$init_project" init -q
cd "$init_project"
pi-en-coord-init \
  --project init-demo \
  --project-key INIT \
  --agent-id agent-a >/dev/null

test -d "$init_project/.pi-en/agent-remotes/init-demo-coordination.git"
test -f "$init_project/.pi-en/coordination/AGENTS.md"
grep -Fx '/.pi-en/' "$init_project/.git/info/exclude" >/dev/null

pi-en-serial-roles \
  --project-root "$init_project" \
  --agent-id agent-a \
  --sleep 0 \
  --max-idle-polls 1 \
  --dry-run \
  --pi-en true \
  --role-manager "$repo_root/role-manager" >"$tmp/serial.out"
grep -Fx 'selected role=none item=none' "$tmp/serial.out" >/dev/null

mkdir -p "$init_project/.pi-en/coordination/requirements" "$init_project/designs"
cat >"$init_project/.pi-en/coordination/requirements/INIT-FRQ-001.yaml" <<'EOF_REQ'
schema: coordination-item/v1
id: INIT-FRQ-001
type: functional-requirement
status: active
project: init-demo
requirement_key: INIT-001
requirement_class: functional
requirement_kind: detailed-behavior
domain: requirements
render_order: 1
body: |-
  # INIT-001 Default coverage smoke
EOF_REQ
cat >"$init_project/designs/default-coverage.md" <<'EOF_DESIGN'
# Default coverage smoke

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| INIT-001 | INIT-FRQ-001 |
EOF_DESIGN
pi-en-coord-generate-requirements-coverage \
  --project init-demo \
  --designs-dir "$init_project/designs" \
  --output "$tmp/coverage.md"
grep -F '| INIT-001 | INIT-FRQ-001 |' "$tmp/coverage.md" >/dev/null
pi-en-coord-generate-requirements \
  --project init-demo \
  --output "$tmp/requirements.md"
grep -F '# INIT-001 Default coverage smoke' "$tmp/requirements.md" >/dev/null

grep -F 'attached at `.pi-en/coordination` by default.' \
  "$repo_root/pi-skill-templates/agent-coordination/SKILL.md" >/dev/null
! grep -F 'Find it at `./coordination`' \
  "$repo_root/pi-skill-templates/agent-coordination/SKILL.md" >/dev/null
! grep -F 'cd coordination && git pull --rebase' \
  "$repo_root/pi-skill-templates/agent-coordination/SKILL.md" >/dev/null
grep -F 'experiments this is `.pi-en/coordination`' "$repo_root/README.md" >/dev/null
grep -F '.pi-en/coordination' "$repo_root/README.md" >/dev/null

clone_project="$tmp/clone-project"
mkdir -p "$clone_project"
git -C "$clone_project" init -q
cd "$clone_project"
pi-en-coord-clone \
  --remote "$init_project/.pi-en/agent-remotes/init-demo-coordination.git" >/dev/null

test -f "$clone_project/.pi-en/coordination/AGENTS.md"
grep -Fx '/.pi-en/' "$clone_project/.git/info/exclude" >/dev/null

default_project="$tmp/default-project"
mkdir -p "$default_project"
git -C "$default_project" init -q
default_root="$(cd "$default_project" && . "$PI_EN_COORD_LIB" && coord_default_root)"
default_dir="$(cd "$default_project" && . "$PI_EN_COORD_LIB" && coord_default_dir)"
test "$default_root" = "$default_project/.pi-en/agent-remotes"
test "$default_dir" = "$default_project/.pi-en/coordination"

printf 'PIEN-ISS-20260620-113310-001 passed\n'
