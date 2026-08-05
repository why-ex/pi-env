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
git config --global user.name "Serial Batch Test"
git config --global user.email "serial-batch-test@example.invalid"

serial_script="$repo_root/scripts/pi-en-serial-roles"
role_manager="$repo_root/role-manager"

make_fake_pi_en() {
  local path
  path="$1"
  cat >"$path" <<'FAKE_PI_EN'
#!/usr/bin/env bash
set -euo pipefail
capture="${SERIAL_FAKE_PI_CAPTURE:?SERIAL_FAKE_PI_CAPTURE is required}"
{
  printf 'env PI_ACTIVE_ROLE=%s\n' "${PI_ACTIVE_ROLE:-}"
  for arg in "$@"; do
    printf 'arg:%s\n' "$arg"
  done
} >>"$capture"
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
  git -C "$project" config user.name "Serial Batch Project Test"
  git -C "$project" config user.email "project@example.invalid"
  printf '/.pi-en/\n' >"$project/.gitignore"
  git -C "$project" add .gitignore
  git -C "$project" commit -q -m "Seed project"

  git init --bare -q "$remote"
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  mkdir -p "$coord"
  git -C "$coord" init -q
  git -C "$coord" checkout -q -b main
  git -C "$coord" config user.name "Serial Batch Coordination Test"
  git -C "$coord" config user.email "coordination@example.invalid"
  git -C "$coord" remote add origin "$remote"

  mkdir -p \
    "$coord/repos/pi-en/issues/open" \
    "$coord/repos/pi-en/issues/done" \
    "$coord/repos/pi-en/issues/blocked" \
    "$coord/repos/pi-en/issues/closed" \
    "$coord/requirements"
  printf '# Coordination rules for serial batch tests\n' >"$coord/AGENTS.md"
  printf 'project: pi-en\nitem_key: PIEN\n' >"$coord/PROJECT.md"
  cat >"$coord/repos/pi-en/REPO.md" <<'EOF_REPO'
---
repo_id: pi-en
status: active
item_key: PIEN
project: pi-en
---

# pi-en
EOF_REPO

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
      dir="$coord/repos/pi-en/issues/done"
      done_value="2026-07-05T00:00:00Z"
      event_type="done"
      ;;
    open)
      dir="$coord/repos/pi-en/issues/open"
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
created: 2026-07-05T00:00:00Z
updated: 2026-07-05T00:00:00Z
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
    at: 2026-07-05T00:00:00Z
    actor:
      id: serial-batch-test
      role: architect
    message: msg-0001
messages:
  - id: msg-0001
    event: evt-0001
    body: |-
      # $title
EOF_ITEM
}

add_requirement() {
  local coord id
  coord="$1"
  id="$2"
  cat >"$coord/requirements/$id.yaml" <<EOF_REQ
schema: coordination-item/v1
id: $id
type: functional-requirement
status: active
project: pi-en
title: 'Non-issue item'
created: 2026-07-05T00:00:00Z
updated: 2026-07-05T00:00:00Z
testable: no
testability_note: 'Fixture requirement.'
body: |-
  Non-issue fixture.
EOF_REQ
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

assert_no_file() {
  local path
  path="$1"
  if [ -e "$path" ]; then
    test_fail "unexpected file exists: $path"
  fi
}

FAKE_PI_EN="$tmp/fake-pi-en"
make_fake_pi_en "$FAKE_PI_EN"

help_out="$tmp/help.out"
"$serial_script" --help >"$help_out"
test_grep '--issue ID' "$help_out"
test_grep 'ordered issue batch' "$help_out"

duplicate_out="$tmp/duplicate.out"
set +e
"$serial_script" --issue BATCH-DUP --issue BATCH-DUP >"$duplicate_out" 2>&1
duplicate_status=$?
set -e
if [ "$duplicate_status" -eq 0 ]; then
  test_fail 'duplicate --issue unexpectedly succeeded'
fi
test_grep 'duplicate --issue ID: BATCH-DUP' "$duplicate_out"

# Without an explicit batch, the normal all-eligible queue still chooses the
# highest role priority item even when it is not the item used below.
new_scenario default-all-eligible
add_issue "$SCENARIO_COORD" BATCH-UNLISTED-TESTER done true false \
  "Unlisted tester candidate"
add_issue "$SCENARIO_COORD" BATCH-DEVELOPER-001 open false false \
  "Developer candidate"
commit_coord "$SCENARIO_COORD"
default_out="$SCENARIO_DIR/default.out"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/default.lock" \
  --dry-run --once >"$default_out" 2>&1
test_grep '^selected role=tester item=BATCH-UNLISTED-TESTER$' "$default_out"

# With --issue, unlisted higher-priority work is ignored and dry-run remains a
# non-mutating bounded selection preview.
filtered_out="$SCENARIO_DIR/filtered.out"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/filtered.lock" \
  --dry-run --once --issue BATCH-DEVELOPER-001 >"$filtered_out" 2>&1
test_grep '^selected role=developer item=BATCH-DEVELOPER-001$' "$filtered_out"
test_grep '^would-claim: .*BATCH-DEVELOPER-001' "$filtered_out"
assert_no_grep 'BATCH-UNLISTED-TESTER' "$filtered_out"
test_grep '^status: open$' \
  "$SCENARIO_COORD/repos/pi-en/issues/open/BATCH-DEVELOPER-001.yaml"

# Role priority is preserved across the requested set.
new_scenario requested-role-priority
add_issue "$SCENARIO_COORD" BATCH-DEVELOPER-002 open false false \
  "Developer candidate"
add_issue "$SCENARIO_COORD" BATCH-REVIEWER-001 done false false \
  "Reviewer candidate"
commit_coord "$SCENARIO_COORD"
role_priority_out="$SCENARIO_DIR/role-priority.out"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/role.lock" \
  --dry-run --once \
  --issue BATCH-DEVELOPER-002 \
  --issue BATCH-REVIEWER-001 >"$role_priority_out" 2>&1
test_grep '^selected role=reviewer item=BATCH-REVIEWER-001$' \
  "$role_priority_out"

# Requested issues in the same role tier use caller-provided order.
new_scenario requested-order
add_issue "$SCENARIO_COORD" BATCH-DEVELOPER-A open false false \
  "Developer A"
add_issue "$SCENARIO_COORD" BATCH-DEVELOPER-B open false false \
  "Developer B"
commit_coord "$SCENARIO_COORD"
order_out="$SCENARIO_DIR/order.out"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/order.lock" \
  --dry-run --once \
  --issue BATCH-DEVELOPER-B \
  --issue BATCH-DEVELOPER-A >"$order_out" 2>&1
test_grep '^selected role=developer item=BATCH-DEVELOPER-B$' "$order_out"

# Unknown issue IDs fail before Pi is invoked.
new_scenario invalid-unknown
commit_coord "$SCENARIO_COORD"
unknown_out="$SCENARIO_DIR/unknown.out"
unknown_capture="$SCENARIO_DIR/unknown.capture"
set +e
SERIAL_FAKE_PI_CAPTURE="$unknown_capture" \
  run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/unknown.lock" \
    --issue BATCH-DOES-NOT-EXIST --once >"$unknown_out" 2>&1
unknown_status=$?
set -e
if [ "$unknown_status" -eq 0 ]; then
  test_fail 'unknown --issue unexpectedly succeeded'
fi
test_grep 'requested issue not found: BATCH-DOES-NOT-EXIST' "$unknown_out"
assert_no_file "$unknown_capture"

# IDs that resolve to non-issue items also fail before Pi is invoked.
new_scenario invalid-non-issue
add_requirement "$SCENARIO_COORD" BATCH-FRQ-001
commit_coord "$SCENARIO_COORD"
non_issue_out="$SCENARIO_DIR/non-issue.out"
non_issue_capture="$SCENARIO_DIR/non-issue.capture"
set +e
SERIAL_FAKE_PI_CAPTURE="$non_issue_capture" \
  run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/non-issue.lock" \
    --issue BATCH-FRQ-001 --once >"$non_issue_out" 2>&1
non_issue_status=$?
set -e
if [ "$non_issue_status" -eq 0 ]; then
  test_fail 'non-issue --issue unexpectedly succeeded'
fi
test_grep 'requested item is not an issue: BATCH-FRQ-001' "$non_issue_out"
assert_no_file "$non_issue_capture"

# An explicit batch exits successfully once the requested issues are currently
# ineligible, even when unrelated work remains and no idle bound is supplied.
new_scenario exhausted-requested-batch
add_issue "$SCENARIO_COORD" BATCH-ALREADY-VERIFIED done true true \
  "Already verified"
add_issue "$SCENARIO_COORD" BATCH-UNRELATED-DEVELOPER open false false \
  "Unrelated developer"
commit_coord "$SCENARIO_COORD"
exhausted_out="$SCENARIO_DIR/exhausted.out"
exhausted_capture="$SCENARIO_DIR/exhausted.capture"
set +e
SERIAL_FAKE_PI_CAPTURE="$exhausted_capture" \
  timeout 5 "$serial_script" \
    --project-root "$SCENARIO_PROJECT" \
    --coord-dir "$SCENARIO_COORD" \
    --agent-id serial-agent \
    --sleep 0 \
    --lock-file "$SCENARIO_DIR/exhausted.lock" \
    --pi-en "$FAKE_PI_EN" \
    --role-manager "$role_manager" \
    --issue BATCH-ALREADY-VERIFIED >"$exhausted_out" 2>&1
exhausted_status=$?
set -e
if [ "$exhausted_status" -ne 0 ]; then
  test_fail "exhausted explicit batch exited with status $exhausted_status"
fi
test_grep 'requested issue batch has no eligible work; exiting' "$exhausted_out"
assert_no_file "$exhausted_capture"

printf 'explicit serial issue batch tests passed\n'
