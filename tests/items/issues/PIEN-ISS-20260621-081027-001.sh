#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PATH="$repo_root/scripts:$PATH"

serial_script="$repo_root/scripts/pi-en-serial-roles"
role_manager="$repo_root/role-manager"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
git config --global user.name "Serial UI Contract Test"
git config --global user.email "serial-ui-contract@example.invalid"

assert_no_grep() {
  local pattern path
  pattern="$1"
  path="$2"
  if grep -q -- "$pattern" "$path"; then
    test_fail "expected $path not to match: $pattern"
  fi
}

new_scenario() {
  local scenario project coord remote
  scenario="$tmp/scenario"
  project="$scenario/project"
  coord="$project/.pi-en/coordination"
  remote="$scenario/coordination.git"

  mkdir -p "$project"
  git -C "$project" init -q
  git -C "$project" checkout -q -b main
  git -C "$project" config user.name "Serial UI Project"
  git -C "$project" config user.email "project@example.invalid"
  printf '/.pi-en/\n' >"$project/.gitignore"
  git -C "$project" add .gitignore
  git -C "$project" commit -q -m "Seed project"

  git init --bare -q "$remote"
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  mkdir -p "$coord/issues/open" "$coord/issues/done" \
    "$coord/issues/blocked" "$coord/issues/closed"
  git -C "$coord" init -q
  git -C "$coord" checkout -q -b main
  git -C "$coord" config user.name "Serial UI Coordination"
  git -C "$coord" config user.email "coordination@example.invalid"
  git -C "$coord" remote add origin "$remote"

  printf '# Coordination rules for serial UI tests\n' >"$coord/AGENTS.md"
  printf 'project: pi-en\nitem_key: PIEN\n' >"$coord/PROJECT.md"
  cat >"$coord/issues/done/SERIAL-UI-TESTER.yaml" <<'EOF_ITEM'
schema: coordination-item/v1
id: SERIAL-UI-TESTER
type: issue
status: done
project: pi-en
title: 'Serial UI tester candidate'
owner: null
priority: medium
created: 2026-06-21T08:10:27Z
updated: 2026-06-21T08:10:27Z
done: 2026-06-21T08:10:27Z
closed: null
reviewed: true
verified: false
testable: yes
testability_note: null
current:
  event: evt-0001
  message: msg-0001
events:
  - id: evt-0001
    type: done
    at: 2026-06-21T08:10:27Z
    actor:
      id: serial-ui-test
      role: developer
    message: msg-0001
messages:
  - id: msg-0001
    event: evt-0001
    body: |-
      # Serial UI tester candidate
EOF_ITEM
  git -C "$coord" add .
  git -C "$coord" commit -q -m "Seed coordination"
  git -C "$coord" push -q -u origin main

  SCENARIO_PROJECT="$project"
  SCENARIO_COORD="$coord"
}

run_serial() {
  local out lock
  out="$1"
  lock="$2"
  shift 2
  "$serial_script" \
    --project-root "$SCENARIO_PROJECT" \
    --coord-dir "$SCENARIO_COORD" \
    --agent-id serial-ui-agent \
    --sleep 0 \
    --lock-file "$lock" \
    --pi-en true \
    --role-manager "$role_manager" \
    --dry-run --once \
    "$@" >"$out" 2>&1
}

help_out="$tmp/help.out"
"$serial_script" --help >"$help_out"
test_grep '--ui interactive|json|none' "$help_out"
test_grep 'default: interactive' "$help_out"
assert_no_grep 'watched-auto-exit' "$help_out"

invalid_out="$tmp/watched-auto-invalid.out"
set +e
"$serial_script" --ui watched-auto-exit >"$invalid_out" 2>&1
invalid_status=$?
set -e
[ "$invalid_status" -ne 0 ] || test_fail 'watched-auto-exit was accepted'
test_grep '--ui must be interactive, json, or none' "$invalid_out"

new_scenario

default_out="$tmp/default.out"
run_serial "$default_out" "$tmp/default.lock"
test_grep '^selected role=tester item=SERIAL-UI-TESTER$' "$default_out"
test_grep '^selected ui=interactive$' "$default_out"
test_grep 'PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE=1' "$default_out"
test_grep 'PI_EN_BWRAP_PASS_ENV=.*PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE' \
  "$default_out"
test_grep 'watched auto-exit.*interactive.*session' "$default_out"
assert_no_grep '--print' "$default_out"
assert_no_grep '--mode json' "$default_out"
assert_no_grep ' -p ' "$default_out"

interactive_out="$tmp/interactive.out"
run_serial "$interactive_out" "$tmp/interactive.lock" --ui interactive
test_grep '^selected ui=interactive$' "$interactive_out"
test_grep 'PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE=1' "$interactive_out"
test_grep 'PI_EN_BWRAP_PASS_ENV=.*PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE' \
  "$interactive_out"
assert_no_grep '--print' "$interactive_out"
assert_no_grep '--mode json' "$interactive_out"
assert_no_grep ' -p ' "$interactive_out"

none_out="$tmp/none.out"
run_serial "$none_out" "$tmp/none.lock" --ui none
test_grep '^selected ui=none$' "$none_out"
test_grep '--print' "$none_out"
assert_no_grep 'PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE=1' "$none_out"
assert_no_grep '--mode json' "$none_out"
assert_no_grep ' -p ' "$none_out"

json_out="$tmp/json.out"
run_serial "$json_out" "$tmp/json.lock" --ui json
test_grep '^selected ui=json$' "$json_out"
test_grep '--mode json' "$json_out"
assert_no_grep 'PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE=1' "$json_out"
assert_no_grep '--print' "$json_out"
assert_no_grep ' -p ' "$json_out"

test_grep 'default `--ui interactive` mode' README.md
test_grep 'previous hold-open `interactive` behavior' README.md
test_grep '`--ui interactive` mode runs a watched normal Pi TUI' \
  designs/serial-role-automation.md
test_grep 'old hold-open interactive behavior' designs/serial-role-automation.md

printf 'PIEN-ISS-20260621-081027-001 passed\n'
