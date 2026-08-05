#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
git config --global user.name "Serial Roles Test"
git config --global user.email "serial-roles-test@example.invalid"

serial_script="$repo_root/scripts/pi-en-serial-roles"
role_manager="$repo_root/role-manager"

make_fake_pi_en() {
  local path
  path="$1"
  cat >"$path" <<'FAKE_PI_EN'
#!/usr/bin/env bash
set -euo pipefail
capture="${SERIAL_FAKE_PI_CAPTURE:?}"
{
  printf 'env PI_ACTIVE_ROLE=%s\n' "${PI_ACTIVE_ROLE:-}"
  printf 'env PI_ROLE_MANAGER_ACTIVE_ROLE=%s\n' \
    "${PI_ROLE_MANAGER_ACTIVE_ROLE:-}"
  printf 'env PI_EN_COORD_ROLE=%s\n' "${PI_EN_COORD_ROLE:-}"
  printf 'env PI_EN_COORD_AGENT_ID=%s\n' "${PI_EN_COORD_AGENT_ID:-}"
  printf 'env PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE=%s\n' \
    "${PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE:-}"
  printf 'env PI_EN_BWRAP_PASS_ENV=%s\n' "${PI_EN_BWRAP_PASS_ENV:-}"
  printf 'env PI_EN_BWRAP_EXTRA_PATH=%s\n' "${PI_EN_BWRAP_EXTRA_PATH:-}"
  for arg in "$@"; do
    printf 'arg:%s\n' "$arg"
  done
} >>"$capture"

if [ -n "${SERIAL_EXPECT_CLAIMED_ITEM:-}" ]; then
  coord_dir="${PI_EN_COORD_DIR:?}"
  if [ "$coord_dir" = /workspace/.pi-en/coordination ]; then
    coord_dir="${PI_EN_BWRAP_PROJECT_ROOT:?}/.pi-en/coordination"
  fi
  item_file="$coord_dir/issues/open/${SERIAL_EXPECT_CLAIMED_ITEM}.yaml"
  grep -q '^status: claimed$' "$item_file"
  grep -q "^owner: ${PI_EN_COORD_AGENT_ID:?}$" "$item_file"
fi
FAKE_PI_EN
  chmod +x "$path"
}

new_scenario() {
  local name scenario project coord remote
  name="$1"
  scenario="$tmp/$name"
  project="$scenario/project"
  coord="$project/.pi-en/coordination"
  remote="$scenario/coordination.git"

  mkdir -p "$project"
  git -C "$project" init -q
  git -C "$project" checkout -q -b main
  git -C "$project" config user.name "Serial Project Test"
  git -C "$project" config user.email "project@example.invalid"
  printf '/.pi-en/\n' >"$project/.gitignore"
  git -C "$project" add .gitignore
  git -C "$project" commit -q -m "Seed project"

  git init --bare -q "$remote"
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  mkdir -p "$coord"
  git -C "$coord" init -q
  git -C "$coord" checkout -q -b main
  git -C "$coord" config user.name "Serial Coordination Test"
  git -C "$coord" config user.email "coordination@example.invalid"
  git -C "$coord" remote add origin "$remote"

  mkdir -p \
    "$coord/issues/open" \
    "$coord/issues/done" \
    "$coord/issues/blocked" \
    "$coord/issues/closed"
  printf '# Coordination rules for serial smoke tests\n' >"$coord/AGENTS.md"
  printf 'project: pi-en\nitem_key: PIEN\n' >"$coord/PROJECT.md"

  SCENARIO_DIR="$scenario"
  SCENARIO_PROJECT="$project"
  SCENARIO_COORD="$coord"
}

add_issue() {
  local coord id status reviewed verified title dir done_value event_type
  coord="$1"
  id="$2"
  status="$3"
  reviewed="$4"
  verified="$5"
  title="$6"

  case "$status" in
    done)
      dir="$coord/issues/done"
      done_value="2026-06-15T00:00:00Z"
      event_type="done"
      ;;
    open|claimed)
      dir="$coord/issues/open"
      done_value="null"
      event_type="opened"
      ;;
    *)
      test_fail "unsupported test issue status: $status"
      ;;
  esac

  mkdir -p "$dir"
  cat >"$dir/$id.yaml" <<EOF_ITEM
schema: coordination-item/v1
id: $id
type: issue
status: $status
project: pi-en
title: '$title'
owner: null
priority: medium
created: 2026-06-15T00:00:00Z
updated: 2026-06-15T00:00:00Z
done: $done_value
closed: null
reviewed: $reviewed
verified: $verified
testable: yes
testability_note: null
current:
  event: evt-0001
  message: msg-0001
events:
  - id: evt-0001
    type: $event_type
    at: 2026-06-15T00:00:00Z
    actor:
      id: serial-test
      role: architect
    message: msg-0001
messages:
  - id: msg-0001
    event: evt-0001
    body: |-
      # $title
EOF_ITEM
}

commit_coord() {
  local coord
  coord="$1"
  git -C "$coord" add .
  git -C "$coord" commit -q -m "Seed coordination"
  git -C "$coord" push -q -u origin main
}

run_serial() {
  local project coord lock_file
  project="$1"
  coord="$2"
  lock_file="$3"
  shift 3
  "$serial_script" \
    --project-root "$project" \
    --coord-dir "$coord" \
    --agent-id serial-agent \
    --sleep 0 \
    --lock-file "$lock_file" \
    --pi-en "$FAKE_PI_EN" \
    --role-manager "$role_manager" \
    "$@"
}

assert_no_grep() {
  local pattern path
  pattern="$1"
  path="$2"
  if grep -q -- "$pattern" "$path"; then
    test_fail "expected $path not to match: $pattern"
  fi
}

assert_clean_git() {
  local dir label status
  dir="$1"
  label="$2"
  status="$(git -C "$dir" status --short)"
  test_eq "" "$status" "$label working tree is clean"
}

FAKE_PI_EN="$tmp/fake-pi-en"
make_fake_pi_en "$FAKE_PI_EN"

help_out="$tmp/help.out"
"$serial_script" --help >"$help_out"
test_grep '--ui interactive|json|none' "$help_out"
test_grep 'default: interactive' "$help_out"
assert_no_grep 'watched-auto-exit' "$help_out"

invalid_out="$tmp/invalid-ui.out"
set +e
run_serial "$tmp" "$tmp" "$tmp/invalid.lock" --ui tty >"$invalid_out" 2>&1
invalid_status=$?
set -e
if [ "$invalid_status" -eq 0 ]; then
  test_fail 'invalid --ui unexpectedly succeeded'
fi
test_grep '--ui must be interactive, json, or none' "$invalid_out"

# Tester work is preferred over reviewer and developer queues, and the dry-run
# command shows role activation variables that pi-en-bwrap must pass through.
new_scenario tester-priority
add_issue "$SCENARIO_COORD" SERIAL-TESTER-001 done true false \
  "Tester candidate"
add_issue "$SCENARIO_COORD" SERIAL-REVIEWER-001 done false false \
  "Reviewer candidate"
add_issue "$SCENARIO_COORD" SERIAL-DEVELOPER-001 open false false \
  "Developer candidate"
commit_coord "$SCENARIO_COORD"
priority_out="$SCENARIO_DIR/priority.out"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/lock" \
  --dry-run --once >"$priority_out" 2>&1
test_grep '^selected role=tester item=SERIAL-TESTER-001$' "$priority_out"
test_grep '^selected ui=interactive$' "$priority_out"
test_grep 'would-run: env' "$priority_out"
test_grep 'PI_ACTIVE_ROLE=tester' "$priority_out"
test_grep 'PI_ROLE_MANAGER_ACTIVE_ROLE=tester' "$priority_out"
test_grep 'PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE=1' "$priority_out"
test_grep 'PI_EN_BWRAP_PASS_ENV=.*PI_ACTIVE_ROLE.*PI_ROLE_MANAGER_ACTIVE_ROLE' \
  "$priority_out"
test_grep 'PI_EN_BWRAP_PASS_ENV=.*PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE' \
  "$priority_out"
test_grep '--tools .*role_cycle_done' "$priority_out"
test_grep 'watched auto-exit.*interactive.*session' "$priority_out"
assert_no_grep '--print' "$priority_out"
assert_no_grep '--mode json' "$priority_out"
assert_no_grep ' -p ' "$priority_out"
test_grep 'Role.*cycle.*kickoff' "$priority_out"
test_grep 'Active.*role:.*tester' "$priority_out"
test_grep 'Selected.*item.*ID:.*SERIAL-TESTER-001' "$priority_out"
assert_no_grep '/role-cycle' "$priority_out"
assert_no_grep '--continue' "$priority_out"

json_out="$SCENARIO_DIR/json.out"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/json.lock" \
  --dry-run --once --ui json >"$json_out" 2>&1
test_grep '^selected ui=json$' "$json_out"
test_grep '--mode json' "$json_out"
assert_no_grep '--print' "$json_out"

custom_tools_out="$SCENARIO_DIR/custom-tools.out"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/custom-tools.lock" \
  --dry-run --once --tools read,grep >"$custom_tools_out" 2>&1
test_grep '--tools read.*,grep.*,role_cycle_done' "$custom_tools_out"

interactive_out="$SCENARIO_DIR/interactive.out"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/interactive.lock" \
  --dry-run --once --ui interactive >"$interactive_out" 2>&1
test_grep '^selected ui=interactive$' "$interactive_out"
test_grep 'would-run: env' "$interactive_out"
test_grep 'PI_ACTIVE_ROLE=tester' "$interactive_out"
test_grep '--tools .*role_cycle_done' "$interactive_out"
test_grep 'Role.*cycle.*kickoff' "$interactive_out"
test_grep 'watched auto-exit.*interactive.*session' "$interactive_out"
test_grep 'PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE=1' "$interactive_out"
test_grep 'PI_EN_BWRAP_PASS_ENV=.*PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE' \
  "$interactive_out"
assert_no_grep '--mode json' "$interactive_out"
assert_no_grep ' -p ' "$interactive_out"

watched_auto_out="$SCENARIO_DIR/watched-auto.out"
set +e
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/watched-auto.lock" \
  --dry-run --once --ui watched-auto-exit >"$watched_auto_out" 2>&1
watched_auto_status=$?
set -e
if [ "$watched_auto_status" -eq 0 ]; then
  test_fail 'watched-auto-exit --ui unexpectedly succeeded'
fi
test_grep '--ui must be interactive, json, or none' "$watched_auto_out"

# Reviewer work is selected ahead of open developer work when no tester issue is
# waiting.
new_scenario reviewer-priority
add_issue "$SCENARIO_COORD" SERIAL-REVIEWER-002 done false false \
  "Reviewer candidate"
add_issue "$SCENARIO_COORD" SERIAL-DEVELOPER-002 open false false \
  "Developer candidate"
commit_coord "$SCENARIO_COORD"
reviewer_out="$SCENARIO_DIR/reviewer.out"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/lock" \
  --dry-run --once >"$reviewer_out" 2>&1
test_grep '^selected role=reviewer item=SERIAL-REVIEWER-002$' "$reviewer_out"
test_grep 'Active.*role:.*reviewer' "$reviewer_out"
test_grep 'Selected.*item.*ID:.*SERIAL-REVIEWER-002' "$reviewer_out"
assert_no_grep '/role-cycle' "$reviewer_out"
assert_no_grep '--continue' "$reviewer_out"

# A developer job claims the selected open issue before launching Pi, starts a
# fresh raw session, and names exactly one coordination item in the prompt.
new_scenario developer-claim
add_issue "$SCENARIO_COORD" SERIAL-DEVELOPER-CLAIM open false false \
  "Developer claim candidate"
commit_coord "$SCENARIO_COORD"
dev_capture="$SCENARIO_DIR/fake-pi.capture"
dev_out="$SCENARIO_DIR/developer.out"
SERIAL_FAKE_PI_CAPTURE="$dev_capture" \
SERIAL_EXPECT_CLAIMED_ITEM=SERIAL-DEVELOPER-CLAIM \
  run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/lock" \
    --once >"$dev_out" 2>&1
test_file_exists "$dev_capture"
test_grep '^env PI_ACTIVE_ROLE=developer$' "$dev_capture"
test_grep '^env PI_ROLE_MANAGER_ACTIVE_ROLE=developer$' "$dev_capture"
test_grep '^env PI_EN_COORD_ROLE=developer$' "$dev_capture"
test_grep '^arg:--raw$' "$dev_capture"
test_grep '^arg:--$' "$dev_capture"
test_grep '^arg:--tools$' "$dev_capture"
test_grep '^arg:read,bash,edit,write,grep,find,ls,role_cycle_done$' \
  "$dev_capture"
test_grep '^env PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE=1$' "$dev_capture"
test_grep '^env PI_EN_BWRAP_PASS_ENV=.*PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE' \
  "$dev_capture"
assert_no_grep '^arg:--print$' "$dev_capture"
assert_no_grep '^arg:--mode$' "$dev_capture"
assert_no_grep '^arg:json$' "$dev_capture"
assert_no_grep '^arg:-p$' "$dev_capture"
test_grep '^arg:## Role cycle kickoff$' "$dev_capture"
test_grep '^Active role: developer$' "$dev_capture"
test_grep '^- Selected item ID: SERIAL-DEVELOPER-CLAIM$' "$dev_capture"
test_grep 'Finish by calling `role_cycle_done` as the final action' \
  "$dev_capture"
test_grep 'watched auto-exit serial job starts a fresh Pi interactive session' \
  "$dev_capture"
assert_no_grep '^arg:/role-cycle' "$dev_capture"
assert_no_grep '^arg:--continue$' "$dev_capture"
test_grep '^status: claimed$' \
  "$SCENARIO_COORD/issues/open/SERIAL-DEVELOPER-CLAIM.yaml"
test_grep '^owner: serial-agent$' \
  "$SCENARIO_COORD/issues/open/SERIAL-DEVELOPER-CLAIM.yaml"
assert_clean_git "$SCENARIO_PROJECT" "project"
assert_clean_git "$SCENARIO_COORD" "coordination"

# Explicit none mode keeps the print invocation for headless runs.
new_scenario developer-none
add_issue "$SCENARIO_COORD" SERIAL-DEVELOPER-NONE open false false \
  "Developer none candidate"
commit_coord "$SCENARIO_COORD"
none_capture="$SCENARIO_DIR/fake-pi-none.capture"
SERIAL_FAKE_PI_CAPTURE="$none_capture" \
SERIAL_EXPECT_CLAIMED_ITEM=SERIAL-DEVELOPER-NONE \
  run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/lock" \
    --once --ui none >"$SCENARIO_DIR/developer-none.out" 2>&1
test_file_exists "$none_capture"
test_grep '^env PI_ACTIVE_ROLE=developer$' "$none_capture"
test_grep '^arg:--print$' "$none_capture"
test_grep '^arg:--tools$' "$none_capture"
test_grep '^arg:read,bash,edit,write,grep,find,ls,role_cycle_done$' \
  "$none_capture"
assert_no_grep '^arg:--mode$' "$none_capture"
assert_no_grep '^arg:json$' "$none_capture"
assert_no_grep '^arg:-p$' "$none_capture"
assert_clean_git "$SCENARIO_PROJECT" "project"
assert_clean_git "$SCENARIO_COORD" "coordination"

# JSON mode remains available for structured automation.
new_scenario developer-json
add_issue "$SCENARIO_COORD" SERIAL-DEVELOPER-JSON open false false \
  "Developer json candidate"
commit_coord "$SCENARIO_COORD"
json_capture="$SCENARIO_DIR/fake-pi-json.capture"
SERIAL_FAKE_PI_CAPTURE="$json_capture" \
SERIAL_EXPECT_CLAIMED_ITEM=SERIAL-DEVELOPER-JSON \
  run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/lock" \
    --once --ui json >"$SCENARIO_DIR/developer-json.out" 2>&1
test_file_exists "$json_capture"
test_grep '^env PI_ACTIVE_ROLE=developer$' "$json_capture"
test_grep '^arg:--mode$' "$json_capture"
test_grep '^arg:json$' "$json_capture"
assert_no_grep '^arg:--print$' "$json_capture"
assert_no_grep '^arg:-p$' "$json_capture"
assert_clean_git "$SCENARIO_PROJECT" "project"
assert_clean_git "$SCENARIO_COORD" "coordination"

# Interactive mode is the watched auto-exit TUI and preserves the same
# environment and raw role-manager/tool setup while omitting JSON/print flags.
new_scenario developer-interactive
add_issue "$SCENARIO_COORD" SERIAL-DEVELOPER-TUI open false false \
  "Developer interactive candidate"
commit_coord "$SCENARIO_COORD"
interactive_capture="$SCENARIO_DIR/fake-pi-interactive.capture"
SERIAL_FAKE_PI_CAPTURE="$interactive_capture" \
SERIAL_EXPECT_CLAIMED_ITEM=SERIAL-DEVELOPER-TUI \
  run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/lock" \
    --once --ui interactive >"$SCENARIO_DIR/developer-interactive.out" 2>&1
test_file_exists "$interactive_capture"
test_grep '^env PI_ACTIVE_ROLE=developer$' "$interactive_capture"
test_grep '^env PI_ROLE_MANAGER_ACTIVE_ROLE=developer$' "$interactive_capture"
test_grep '^env PI_EN_COORD_ROLE=developer$' "$interactive_capture"
test_grep '^arg:--raw$' "$interactive_capture"
test_grep '^arg:--$' "$interactive_capture"
test_grep '^arg:-e$' "$interactive_capture"
test_grep '^arg:--tools$' "$interactive_capture"
test_grep '^arg:read,bash,edit,write,grep,find,ls,role_cycle_done$' \
  "$interactive_capture"
assert_no_grep '^arg:--mode$' "$interactive_capture"
assert_no_grep '^arg:json$' "$interactive_capture"
assert_no_grep '^arg:--print$' "$interactive_capture"
assert_no_grep '^arg:-p$' "$interactive_capture"
test_grep '^arg:## Role cycle kickoff$' "$interactive_capture"
test_grep 'watched auto-exit serial job starts a fresh Pi interactive session' \
  "$interactive_capture"
test_grep '^env PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE=1$' \
  "$interactive_capture"
test_grep '^env PI_EN_BWRAP_PASS_ENV=.*PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE' \
  "$interactive_capture"
assert_clean_git "$SCENARIO_PROJECT" "project"
assert_clean_git "$SCENARIO_COORD" "coordination"

test_grep 'ROLE_CYCLE_AUTO_SHUTDOWN_ENV = "PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE"' \
  "$repo_root/role-manager/extensions/role-manager.ts"
test_grep 'requestAutoShutdownAfterRoleCycle(ctx)' \
  "$repo_root/role-manager/extensions/role-manager.ts"
test_grep 'ctx.shutdown()' "$repo_root/role-manager/extensions/role-manager.ts"

# Empty queues exit the bounded loop without invoking Pi.
new_scenario empty-queue
commit_coord "$SCENARIO_COORD"
empty_capture="$SCENARIO_DIR/empty.capture"
empty_out="$SCENARIO_DIR/empty.out"
SERIAL_FAKE_PI_CAPTURE="$empty_capture" \
  run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/lock" \
    --once >"$empty_out" 2>&1
test_grep 'idle poll limit reached (1); exiting' "$empty_out"
if [ -e "$empty_capture" ]; then
  test_fail 'empty queue invoked fake pi-en'
fi

# A live lockfile prevents a second serial orchestrator from starting.
new_scenario lock-contention
commit_coord "$SCENARIO_COORD"
lock_file="$SCENARIO_DIR/lock"
printf '%s\n' "$$" >"$lock_file"
lock_out="$SCENARIO_DIR/lock.out"
set +e
SERIAL_FAKE_PI_CAPTURE="$SCENARIO_DIR/lock.capture" \
  run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$lock_file" \
    --dry-run --once >"$lock_out" 2>&1
lock_status=$?
set -e
if [ "$lock_status" -eq 0 ]; then
  test_fail 'lock contention unexpectedly succeeded'
fi
test_grep 'lock is already held' "$lock_out"

# Dirty project state fails closed before polling or launching, and the dirty
# file is left in place for the user instead of being reset or stashed.
new_scenario dirty-project
add_issue "$SCENARIO_COORD" SERIAL-DIRTY-001 done true false \
  "Dirty project candidate"
commit_coord "$SCENARIO_COORD"
printf 'do not remove me\n' >"$SCENARIO_PROJECT/dirty.txt"
dirty_out="$SCENARIO_DIR/dirty.out"
set +e
SERIAL_FAKE_PI_CAPTURE="$SCENARIO_DIR/dirty.capture" \
  run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/lock" \
    --dry-run --once >"$dirty_out" 2>&1
dirty_status=$?
set -e
if [ "$dirty_status" -eq 0 ]; then
  test_fail 'dirty project state unexpectedly succeeded'
fi
test_grep 'unexpected dirty project working tree' "$dirty_out"
test_file_exists "$SCENARIO_PROJECT/dirty.txt"
test_eq 'do not remove me' "$(cat "$SCENARIO_PROJECT/dirty.txt")" \
  'dirty project file was preserved'
project_dirty_status="$(git -C "$SCENARIO_PROJECT" status --short)"
printf '%s\n' "$project_dirty_status" >"$SCENARIO_DIR/dirty.status"
test_grep '?? dirty.txt' "$SCENARIO_DIR/dirty.status"
if [ -e "$SCENARIO_DIR/dirty.capture" ]; then
  test_fail 'dirty project state invoked fake pi-en'
fi

printf 'serial role automation smoke tests passed\n'
