#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PI_EN_COORD_TEMPLATE_DIR="$repo_root/pi-skill-templates/agent-coordination"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
git config --global user.name "Portable Remote Test"
git config --global user.email "portable-remote-test@example.invalid"

unset PI_EN_COORD_REMOTE PI_EN_COORD_WORKSPACE \
  PI_EN_COORD_DIR PI_EN_COORD_AGENT_ID PI_EN_COORD_PROJECT PI_EN_COORD_PROJECT_KEY PI_EN_COORD_ROLE

assert_relative_origin() {
  local repo expected actual label
  repo="$1"
  expected="$2"
  label="$3"
  actual="$(git -C "$repo" remote get-url origin)"
  test_eq "$expected" "$actual" "$label"
  case "$actual" in
    /*) test_fail "$label stored an absolute local origin: $actual" ;;
  esac
}

workspace="$tmp/workspace"
mkdir -p "$workspace"
cd "$workspace"

pi-en-coord-init \
  --root "$tmp/remotes" \
  --project portable-demo \
  --agent-id agent-a \
  --dir .pi-en/coordination >/dev/null

remote="$tmp/remotes/portable-demo-coordination.git"
init_expected="$(realpath -m --relative-to="$workspace/.pi-en/coordination" "$remote")"
assert_relative_origin \
  "$workspace/.pi-en/coordination" \
  "$init_expected" \
  "pi-en-coord-init should store a clone-relative local origin"

cd "$tmp"
pi-en-coord-clone \
  --root "$tmp/remotes" \
  --project portable-demo \
  --dir clone >/dev/null

clone_expected="$(realpath -m --relative-to="$tmp/clone" "$remote")"
assert_relative_origin \
  "$tmp/clone" \
  "$clone_expected" \
  "pi-en-coord-clone should store a clone-relative local origin"

git -C "$tmp/clone" remote remove origin
pi-en-coord-clone \
  --root "$tmp/remotes" \
  --project portable-demo \
  --dir clone >/dev/null

assert_relative_origin \
  "$tmp/clone" \
  "$clone_expected" \
  "pi-en-coord-clone should repair an existing clone without origin"

bootstrap_project="$tmp/bootstrap-project"
mkdir -p "$bootstrap_project"
git -C "$bootstrap_project" init -q
git -C "$bootstrap_project" remote add origin \
  https://example.invalid/org/bootstrap-demo.git

pi-en-bootstrap-coordination \
  --project-root "$bootstrap_project" \
  --root "$tmp/bootstrap-remotes" \
  --agent-id agent-b \
  --no-status >/dev/null

bootstrap_coord="$bootstrap_project/.pi-en/coordination"
bootstrap_remote="$tmp/bootstrap-remotes/bootstrap-demo-coordination.git"
bootstrap_expected="$(realpath -m --relative-to="$bootstrap_coord" "$bootstrap_remote")"
bootstrap_head="$(git -C "$bootstrap_coord" rev-parse HEAD)"
assert_relative_origin \
  "$bootstrap_coord" \
  "$bootstrap_expected" \
  "pi-en-bootstrap-coordination should store a clone-relative local origin"

git -C "$bootstrap_coord" remote remove origin
rm -rf "$bootstrap_remote"
pi-en-bootstrap-coordination \
  --project-root "$bootstrap_project" \
  --root "$tmp/bootstrap-remotes" \
  --agent-id agent-b \
  --no-status >/dev/null

test_dir_exists "$bootstrap_remote/objects"
test_eq \
  "$bootstrap_head" \
  "$(git --git-dir="$bootstrap_remote" rev-parse main)" \
  "pi-en-bootstrap-coordination should restore the missing bare remote from the clone"
assert_relative_origin \
  "$bootstrap_coord" \
  "$bootstrap_expected" \
  "pi-en-bootstrap-coordination should repair a missing origin with a portable URL"

echo "portable local coordination remote URL tests passed"
