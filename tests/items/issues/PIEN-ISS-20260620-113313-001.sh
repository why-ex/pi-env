#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

script="$tmpdir/pi-en-bwrap"
cp scripts/pi-en-bwrap "$script"
chmod +x "$script"

fixed_grep() {
  local needle path
  needle="$1"
  path="$2"
  grep -Fq -- "$needle" "$path" || test_fail "expected $path to contain: $needle"
}

assert_no_line() {
  local line path
  line="$1"
  path="$2"
  if grep -Fxq -- "$line" "$path"; then
    test_fail "expected $path not to contain exact line: $line"
  fi
}

assert_setenv() {
  local path name value
  path="$1"
  name="$2"
  value="$3"
  awk -v name="$name" -v value="$value" '
    prev2 == "--setenv" && prev1 == name && $0 == value { found = 1 }
    { prev2 = prev1; prev1 = $0 }
    END { exit(found ? 0 : 1) }
  ' "$path" || test_fail "expected $path to set $name=$value"
}

assert_bind() {
  local path source target
  path="$1"
  source="$2"
  target="$3"
  awk -v source="$source" -v target="$target" '
    prev2 == "--bind" && prev1 == source && $0 == target { found = 1 }
    { prev2 = prev1; prev1 = $0 }
    END { exit(found ? 0 : 1) }
  ' "$path" || test_fail "expected $path to bind $source at $target"
}

project_hash() {
  printf '%s' "$(realpath -m "$1")" | sha256sum | awk '{print $1}' | cut -c1-16
}

fakebin="$tmpdir/fakebin"
mkdir -p "$fakebin"
cat >"$fakebin/pi" <<'FAKE_PI'
#!/usr/bin/env bash
exit 99
FAKE_PI
chmod +x "$fakebin/pi"

cat >"$tmpdir/fake-bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
set -euo pipefail
: "${PI_EN_TEST_CAPTURE:?}"
: >"$PI_EN_TEST_CAPTURE"
while [ "$#" -gt 0 ]; do
  printf '%s\n' "$1" >>"$PI_EN_TEST_CAPTURE"
  shift
done
FAKE_BWRAP
chmod +x "$tmpdir/fake-bwrap"

run_harness() {
  local project capture cwd
  project="$1"
  capture="$2"
  cwd="$3"
  shift 3
  mkdir -p "$project" "$cwd"
  (
    cd "$cwd"
    unset PI_EN_COORD_REMOTE PI_EN_COORD_DIR \
      PI_EN_BWRAP_COORDINATION_DIR PI_EN_BWRAP_STATE_DIR
    env \
      HOME="$tmpdir/home" \
      XDG_STATE_HOME="$tmpdir/xdg-state" \
      PATH="$fakebin:$PATH" \
      PI_EN_RUNTIME_PATH="$tmpdir/runtime/bin" \
      PI_EN_BWRAP_BWRAP="$tmpdir/fake-bwrap" \
      PI_EN_TEST_FAKE_BWRAP="$tmpdir/fake-bwrap" \
      PI_EN_TEST_CAPTURE="$capture" \
      PI_EN_BWRAP_PROJECT_ROOT="$project" \
      PI_EN_BWRAP_IMPORT_COMMON=0 \
      PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
      PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
      PI_EN_BWRAP_IMPORT_AUTH=0 \
      PI_EN_BWRAP_IMPORT_SESSIONS=0 \
      "$@" "$script" -- --version
  )
}

fixed_grep 'Use $PWD/.pi-en/state only as explicit project-local opt-in' "$script"
fixed_grep 'PI_EN_BWRAP_STATE_DIR=$PWD/.pi-en/state' README.md
fixed_grep 'PI_EN_COORD_REMOTE=remote' "$script"

prefer_project="$tmpdir/prefer-project"
mkdir -p "$prefer_project/.pi-en/coordination/.git"
touch "$prefer_project/.pi-en/coordination/AGENTS.md"
prefer_capture="$tmpdir/prefer-capture"
run_harness "$prefer_project" "$prefer_capture" "$prefer_project"
assert_setenv "$prefer_capture" PI_EN_COORD_DIR /workspace/.pi-en/coordination
assert_no_line /workspace/coordination "$prefer_capture"

local_project="$tmpdir/local-project"
mkdir -p "$local_project/.pi-en/agent-remotes" "$local_project/subdir"
local_capture="$tmpdir/local-capture"
run_harness "$local_project" "$local_capture" "$local_project/subdir" \
  PI_EN_BWRAP_STATE_DIR="$tmpdir/local-state"
assert_bind "$local_capture" "$local_project" /workspace
assert_no_line "$local_project/.pi-en/agent-remotes" "$local_capture"
assert_no_line /agent-remotes "$local_capture"

root_layout_project="$tmpdir/root-layout-project"
mkdir -p "$root_layout_project/agent-remotes" "$root_layout_project/coordination/.git"
touch "$root_layout_project/coordination/AGENTS.md"
root_layout_capture="$tmpdir/root-layout-capture"
run_harness "$root_layout_project" "$root_layout_capture" "$root_layout_project"
assert_no_line PI_EN_COORD_DIR "$root_layout_capture"
assert_no_line /workspace/coordination "$root_layout_capture"
assert_no_line /workspace/agent-remotes "$root_layout_capture"
assert_no_line "$root_layout_project/agent-remotes" "$root_layout_capture"

explicit_project_coord_capture="$tmpdir/explicit-project-coord-capture"
mkdir -p "$root_layout_project/.pi-en/coordination/.git"
run_harness "$root_layout_project" "$explicit_project_coord_capture" "$root_layout_project" \
  PI_EN_COORD_DIR=.pi-en/coordination
assert_setenv "$explicit_project_coord_capture" PI_EN_COORD_DIR /workspace/.pi-en/coordination

workspace_env_capture="$tmpdir/workspace-env-capture"
run_harness "$local_project" "$workspace_env_capture" "$local_project" \
  PI_EN_COORD_WORKSPACE=legacy-workspace
assert_no_line PI_EN_COORD_WORKSPACE "$workspace_env_capture"

if [ -d /workspace/agent-remotes ]; then
  compat_project="$tmpdir/compat-project"
  compat_capture="$tmpdir/compat-capture"
  run_harness "$compat_project" "$compat_capture" "$compat_project"
  assert_no_line /workspace/agent-remotes "$compat_capture"

  modern_project="$tmpdir/modern-project"
  modern_capture="$tmpdir/modern-capture"
  mkdir -p "$modern_project/.pi-en/agent-remotes"
  run_harness "$modern_project" "$modern_capture" "$modern_project"
  assert_no_line /workspace/agent-remotes "$modern_capture"

  modern_coord_project="$tmpdir/modern-coord-project"
  modern_coord_capture="$tmpdir/modern-coord-capture"
  mkdir -p "$modern_coord_project/.pi-en/coordination/.git"
  run_harness "$modern_coord_project" "$modern_coord_capture" "$modern_coord_project"
  assert_no_line /workspace/agent-remotes "$modern_coord_capture"
fi

state_project="$tmpdir/default-state-project"
state_capture="$tmpdir/default-state-capture"
xdg_state="$tmpdir/custom-xdg-state"
run_harness "$state_project" "$state_capture" "$state_project" \
  XDG_STATE_HOME="$xdg_state"
default_state="$xdg_state/pi-en/$(project_hash "$state_project")"
test_dir_exists "$default_state/home/.pi/agent"
assert_bind "$state_capture" "$default_state/home" /home/pi
assert_bind "$state_capture" "$default_state/agent" /home/pi/.pi/agent
assert_no_line "$state_project/.pi-en/state/home" "$state_capture"
[ ! -e "$state_project/.pi-en/state" ] || \
  test_fail "default state unexpectedly used $state_project/.pi-en/state"

fallback_project="$tmpdir/fallback-state-project"
fallback_capture="$tmpdir/fallback-state-capture"
fallback_home="$tmpdir/fallback-home"
run_harness "$fallback_project" "$fallback_capture" "$fallback_project" \
  XDG_STATE_HOME= \
  HOME="$fallback_home"
fallback_state="$fallback_home/.local/state/pi-en/$(project_hash "$fallback_project")"
test_dir_exists "$fallback_state/home/.pi/agent"
assert_bind "$fallback_capture" "$fallback_state/home" /home/pi
assert_no_line "$fallback_project/.pi-en/state/home" "$fallback_capture"

explicit_project="$tmpdir/explicit-state-project"
explicit_capture="$tmpdir/explicit-state-capture"
explicit_state="$explicit_project/.pi-en/state"
run_harness "$explicit_project" "$explicit_capture" "$explicit_project" \
  PI_EN_BWRAP_STATE_DIR="$explicit_state"
test_dir_exists "$explicit_state/home/.pi/agent"
test_dir_exists "$explicit_state/agent/sessions"
assert_bind "$explicit_capture" "$explicit_state/home" /home/pi
assert_bind "$explicit_capture" "$explicit_state/agent" /home/pi/.pi/agent
assert_bind "$explicit_capture" "$explicit_state/cache" /home/pi/.cache

printf 'PIEN-ISS-20260620-113313-001 passed\n'
