#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PI_EN_COORD_TEMPLATE_DIR="$repo_root/pi-skill-templates/agent-coordination"
export PATH="$repo_root/scripts:$PATH"
unset PI_EN_COORD_PROJECT_ROOT PI_EN_COORD_DIR PI_EN_BWRAP_COORDINATION_DIR PI_EN_COORD_REMOTE

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
git config --global user.name "Coordination Test"
git config --global user.email "coordination-test@example.invalid"

project="$tmp/project"
external="$tmp/external-coordination"
mkdir -p "$project"
git -C "$project" init -q

assert_rejects_project_local() {
  local err="$tmp/reject.err"
  if "$@" >"$tmp/reject.out" 2>"$err"; then
    printf 'expected command to reject external coordination dir: %s\n' "$*" >&2
    exit 1
  fi
  grep -F "$project/.pi-en/coordination" "$err" >/dev/null
}

(
  cd "$project"
  pi-en-coord-init --project local-demo --repo-id local-demo --dir .pi-en/coordination >/dev/null
  test -d "$project/.pi-en/coordination/.git"
)

(
  cd "$project"
  assert_rejects_project_local \
    env PI_EN_COORD_DIR="$external" \
    pi-en-coord-init --project local-demo --repo-id local-demo
)

(
  cd "$project"
  assert_rejects_project_local \
    pi-en-coord-clone --remote "$project/.pi-en/agent-remotes/local-demo-coordination.git" --dir "$external"
)

(
  cd "$project"
  assert_rejects_project_local \
    pi-en-bootstrap-coordination --print-only --dir "$external"
)

(
  cd "$project"
  assert_rejects_project_local \
    env PI_EN_COORD_DIR="$external" \
    pi-en-serial-roles --dry-run --once --ui none
)

grep -F 'PI_EN_BWRAP_COORDINATION_DIR' "$repo_root/scripts/pi-en-bwrap" >/dev/null
grep -F 'must use the project-local coordination checkout' "$repo_root/scripts/pi-en-bwrap" >/dev/null
if grep -F -- '--bind "$host_coord_dir" /coordination' "$repo_root/scripts/pi-en-bwrap" >/dev/null; then
  printf 'pi-en-bwrap still binds an external coordination clone at /coordination\n' >&2
  exit 1
fi

printf 'project-local coordination dir tests passed\n'
