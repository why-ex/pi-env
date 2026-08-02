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
git config --global user.name "Serial Dirty Coordination Test"
git config --global user.email "serial-dirty-coord@example.invalid"

make_fake_pi_en() {
  local path
  path="$1"
  cat >"$path" <<'FAKE_PI_EN'
#!/usr/bin/env bash
set -euo pipefail
printf 'fake pi-en should not be invoked\n' >&2
exit 99
FAKE_PI_EN
  chmod +x "$path"
}

init_project_and_coord() {
  local project coord remote
  project="$tmp/project"
  coord="$project/coordination"
  remote="$tmp/coordination.git"

  mkdir -p "$project"
  git -C "$project" init -q
  git -C "$project" checkout -q -b main
  git -C "$project" config user.name "Project Test"
  git -C "$project" config user.email "project@example.invalid"
  printf '/coordination/\n' >"$project/.gitignore"
  git -C "$project" add .gitignore
  git -C "$project" commit -q -m "Seed project"

  git init --bare -q "$remote"
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  mkdir -p "$coord/issues/open" "$coord/issues/done" "$coord/issues/closed"
  git -C "$coord" init -q
  git -C "$coord" checkout -q -b main
  git -C "$coord" config user.name "Coordination Test"
  git -C "$coord" config user.email "coordination@example.invalid"
  git -C "$coord" remote add origin "$remote"
  printf '# Coordination rules\n' >"$coord/AGENTS.md"
  printf 'project: pi-en\nitem_key: PIEN\n' >"$coord/PROJECT.md"
  git -C "$coord" add .
  git -C "$coord" commit -q -m "Seed empty coordination"
  git -C "$coord" push -q -u origin main

  PROJECT_DIR="$project"
  COORD_DIR="$coord"
  REMOTE_DIR="$remote"
}

add_remote_issue_without_pulling() {
  local clone id
  clone="$tmp/remote-writer"
  id="REMOTE-ELIGIBLE-001"
  git clone -q "$REMOTE_DIR" "$clone"
  git -C "$clone" config user.name "Remote Writer"
  git -C "$clone" config user.email "remote@example.invalid"
  mkdir -p "$clone/issues/open"
  cat >"$clone/issues/open/$id.yaml" <<EOF_ITEM
schema: coordination-item/v1
id: $id
type: issue
status: open
project: pi-en
title: 'Remote eligible issue'
owner: null
priority: medium
created: 2026-06-25T00:00:00Z
updated: 2026-06-25T00:00:00Z
done: null
closed: null
reviewed: false
verified: false
testable: yes
testability_note: null
current:
  event: evt-0001
  message: msg-0001
events:
  - id: evt-0001
    type: opened
    at: 2026-06-25T00:00:00Z
    actor:
      id: test
      role: architect
    message: msg-0001
messages:
  - id: msg-0001
    event: evt-0001
    body: |-
      # Remote eligible issue
EOF_ITEM
  git -C "$clone" add .
  git -C "$clone" commit -q -m "Add remote eligible issue"
  git -C "$clone" push -q origin main
}

run_serial() {
  "$serial_script" \
    --project-root "$PROJECT_DIR" \
    --coord-dir "$COORD_DIR" \
    --agent-id serial-agent \
    --sleep 0 \
    --lock-file "$tmp/serial.lock" \
    --pi-en "$FAKE_PI_EN" \
    --role-manager "$role_manager" \
    "$@"
}

FAKE_PI_EN="$tmp/fake-pi-en"
make_fake_pi_en "$FAKE_PI_EN"
init_project_and_coord
add_remote_issue_without_pulling

# Leave an eligible untracked local item in the coordination checkout. A dirty
# pre-selection poll must not pull the remote eligible item and must not select
# from this dirty local tree.
cat >"$COORD_DIR/issues/open/LOCAL-DIRTY-001.yaml" <<'EOF_ITEM'
schema: coordination-item/v1
id: LOCAL-DIRTY-001
type: issue
status: open
project: pi-en
title: 'Dirty local issue'
owner: null
priority: medium
created: 2026-06-25T00:00:00Z
updated: 2026-06-25T00:00:00Z
done: null
closed: null
reviewed: false
verified: false
testable: yes
testability_note: null
current:
  event: evt-0001
  message: msg-0001
events: []
messages: []
EOF_ITEM

out="$tmp/dirty-coordination.out"
run_serial --dry-run --once >"$out" 2>&1

test_grep '^selected role=none item=none$' "$out"
if grep -q 'unexpected dirty coordination working tree' "$out"; then
  test_fail 'dirty pre-selection poll failed instead of reporting no selection'
fi
if grep -q 'REMOTE-ELIGIBLE-001\|LOCAL-DIRTY-001' "$out"; then
  test_fail 'dirty pre-selection poll selected or reported an eligible item'
fi
if git -C "$COORD_DIR" rev-parse --verify -q origin/main >/dev/null; then
  local_origin="$(git -C "$COORD_DIR" rev-parse origin/main)"
  remote_main="$(git --git-dir="$REMOTE_DIR" rev-parse main)"
  if [ "$local_origin" = "$remote_main" ]; then
    test_fail 'dirty pre-selection poll fetched/pulled coordination updates'
  fi
fi

test_file_exists "$COORD_DIR/issues/open/LOCAL-DIRTY-001.yaml"
git -C "$COORD_DIR" status --short >"$tmp/coord.status"
test_grep '^?? issues/' "$tmp/coord.status"

printf 'PIEN-ISS-20260625-203230-001 passed\n'
