#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
serial_script="$repo_root/scripts/pi-en-serial-roles"
role_manager="$repo_root/role-manager"

export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PI_EN_COORD_TEMPLATE_DIR="$repo_root/pi-skill-templates/agent-coordination"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
git config --global user.name "Serial Artifact Test"
git config --global user.email "serial-artifacts-test@example.invalid"
unset PI_EN_COORD_REMOTE PI_EN_COORD_WORKSPACE \
  PI_EN_COORD_DIR PI_EN_COORD_AGENT_ID PI_EN_COORD_PROJECT PI_EN_COORD_PROJECT_KEY PI_EN_COORD_ROLE

fail() {
  printf 'PIEN-ISS-20260620-113316-001: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local needle path
  needle="$1"
  path="$2"
  grep -F -- "$needle" "$path" >/dev/null \
    || fail "expected $path to contain: $needle"
}

assert_no_path() {
  local path
  path="$1"
  [ ! -e "$path" ] || fail "unexpected path exists: $path"
}

assert_clean_git() {
  local dir label status
  dir="$1"
  label="$2"
  status="$(git -C "$dir" status --short --untracked-files=normal)"
  [ -z "$status" ] || fail "$label working tree is dirty: $status"
}

help_out="$tmp/help.out"
"$serial_script" --help >"$help_out"
assert_file_contains '.pi-en/locks/pi-en-serial-roles.lock' "$help_out"
if grep -F 'Git metadata directory' "$help_out" >/dev/null; then
  fail 'help still describes the default lock under Git metadata'
fi

assert_file_contains '.pi-en/locks/pi-en-serial-roles.lock' \
  "$repo_root/designs/serial-role-automation.md"
assert_file_contains '.pi-en/logs' \
  "$repo_root/designs/serial-role-automation.md"
assert_file_contains '.pi-en/locks/pi-en-serial-roles.lock' "$repo_root/README.md"
assert_file_contains '.pi-en/logs' "$repo_root/README.md"

project="$tmp/default-project"
mkdir -p "$project"
git -C "$project" init -q
(
  cd "$project"
  pi-en-coord-init \
    --project serial-artifacts \
    --project-key SERIALART \
    --agent-id agent-a >/dev/null
)
coord="$project/.pi-en/coordination"
default_lock="$project/.pi-en/locks/pi-en-serial-roles.lock"
assert_no_path "$project/.pi-en/locks"
coord_head_before="$(git -C "$coord" rev-parse HEAD)"

serial_out="$tmp/default-project.out"
"$serial_script" \
  --project-root "$project" \
  --agent-id agent-a \
  --sleep 0 \
  --max-idle-polls 1 \
  --dry-run \
  --pi-en true \
  --role-manager "$role_manager" >"$serial_out" 2>&1
assert_file_contains 'selected role=none item=none' "$serial_out"
[ -d "$project/.pi-en/locks" ] \
  || fail 'default run did not create .pi-en/locks'
assert_no_path "$default_lock"
assert_no_path "$project/.pi-en-serial-roles.lock"
assert_no_path "$project/pi-en-serial-roles.lock"
[ "$(git -C "$coord" rev-parse HEAD)" = "$coord_head_before" ] \
  || fail 'default lock run changed coordination HEAD'
assert_clean_git "$coord" 'coordination'
assert_clean_git "$project" 'project'

printf '%s\n' "$$" >"$default_lock"
lock_out="$tmp/default-lock-contention.out"
set +e
"$serial_script" \
  --project-root "$project" \
  --agent-id agent-a \
  --sleep 0 \
  --max-idle-polls 1 \
  --dry-run \
  --pi-en true \
  --role-manager "$role_manager" >"$lock_out" 2>&1
lock_status=$?
set -e
[ "$lock_status" -ne 0 ] || fail 'default lock contention unexpectedly succeeded'
assert_file_contains 'lock is already held' "$lock_out"
rm -f "$default_lock"

legacy_project="$tmp/legacy-project"
legacy_coord="$legacy_project/coordination"
mkdir -p "$legacy_coord"
git -C "$legacy_project" init -q
mkdir -p "$legacy_project/.git/info"
printf '/coordination/\n' >>"$legacy_project/.git/info/exclude"
git -C "$legacy_coord" init -q
printf '# Coordination rules\n' >"$legacy_coord/AGENTS.md"
git -C "$legacy_coord" add AGENTS.md
git -C "$legacy_coord" commit -q -m 'Seed coordination'
if grep -Fx '/.pi-en/' "$legacy_project/.git/info/exclude" >/dev/null; then
  fail 'legacy test fixture unexpectedly ignored .pi-en before serial run'
fi
legacy_head_before="$(git -C "$legacy_coord" rev-parse HEAD)"

legacy_out="$tmp/legacy-project.out"
"$serial_script" \
  --project-root "$legacy_project" \
  --coord-dir "$legacy_coord" \
  --agent-id agent-a \
  --sleep 0 \
  --max-idle-polls 1 \
  --dry-run \
  --pi-en true \
  --role-manager "$role_manager" >"$legacy_out" 2>&1
assert_file_contains 'selected role=none item=none' "$legacy_out"
[ -d "$legacy_project/.pi-en/locks" ] \
  || fail 'legacy run did not create .pi-en/locks'
grep -Fx '/.pi-en/' "$legacy_project/.git/info/exclude" >/dev/null \
  || fail 'serial run did not exclude the .pi-en operational root'
assert_no_path "$legacy_project/.pi-en-serial-roles.lock"
assert_no_path "$legacy_project/pi-en-serial-roles.lock"
[ "$(git -C "$legacy_coord" rev-parse HEAD)" = "$legacy_head_before" ] \
  || fail 'legacy run changed coordination HEAD'
assert_clean_git "$legacy_coord" 'legacy coordination'
assert_clean_git "$legacy_project" 'legacy project'

printf 'PIEN-ISS-20260620-113316-001 passed\n'
