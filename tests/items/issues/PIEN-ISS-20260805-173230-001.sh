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
  local project capture
  project="$1"
  capture="$2"
  shift 2
  mkdir -p "$project"
  (
    cd "$project"
    unset PI_EN_COORD_REMOTE PI_EN_COORD_DIR PI_EN_BWRAP_COORDINATION_DIR
    env \
      PATH="$fakebin:$PATH" \
      PI_EN_RUNTIME_PATH="$tmpdir/runtime/bin" \
      PI_EN_BWRAP_BWRAP="$tmpdir/fake-bwrap" \
      PI_EN_TEST_CAPTURE="$capture" \
      PI_EN_BWRAP_PROJECT_ROOT="$project" \
      PI_EN_BWRAP_STATE_DIR="$tmpdir/state-$(basename "$capture")" \
      PI_EN_BWRAP_IMPORT_COMMON=0 \
      PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
      PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
      PI_EN_BWRAP_IMPORT_AUTH=0 \
      PI_EN_BWRAP_IMPORT_SESSIONS=0 \
      "$@" "$script" -- --version
  )
}

assert_arg_triple() {
  local path flag source target
  path="$1"
  flag="$2"
  source="$3"
  target="$4"
  awk -v flag="$flag" -v source="$source" -v target="$target" '
    prev2 == flag && prev1 == source && $0 == target { found = 1 }
    { prev2 = prev1; prev1 = $0 }
    END { exit(found ? 0 : 1) }
  ' "$path" || test_fail "expected $path to contain $flag $source $target"
}

assert_exact_line() {
  local path line
  path="$1"
  line="$2"
  grep -Fxq -- "$line" "$path" || test_fail "expected $path to contain exact line: $line"
}

assert_no_exact_line() {
  local path line
  path="$1"
  line="$2"
  if grep -Fxq -- "$line" "$path"; then
    test_fail "expected $path not to contain exact line: $line"
  fi
}

assert_no_arg_pair() {
  local path flag value
  path="$1"
  flag="$2"
  value="$3"
  if awk -v flag="$flag" -v value="$value" '
    prev == flag && $0 == value { found = 1 }
    { prev = $0 }
    END { exit(found ? 0 : 1) }
  ' "$path"; then
    test_fail "expected $path not to contain $flag $value"
  fi
}

external_parent="$tmpdir/external-remotes"
external_remote="$external_parent/derived.git"
external_sibling="$external_parent/sibling.git"
mkdir -p "$external_remote/objects" "$external_sibling/objects"

symlink_project="$tmpdir/symlink-project"
mkdir -p "$symlink_project/.pi-en/agent-remotes" "$symlink_project/.pi-en/coordination/.git"
ln -s "$external_remote" "$symlink_project/.pi-en/agent-remotes/derived.git"
cat >"$symlink_project/.pi-en-coordination.yaml" <<'YAML'
version: 1
coordination_remote: .pi-en/agent-remotes/derived.git
YAML
symlink_capture="$tmpdir/symlink-capture"
run_harness "$symlink_project" "$symlink_capture"
assert_exact_line "$symlink_capture" --tmpfs
assert_exact_line "$symlink_capture" /workspace/.pi-en/agent-remotes
assert_arg_triple "$symlink_capture" --bind \
  "$external_remote" /workspace/.pi-en/agent-remotes/derived.git
assert_no_exact_line "$symlink_capture" "$external_parent"
assert_no_exact_line "$symlink_capture" "$external_sibling"
assert_arg_triple "$symlink_capture" --setenv \
  PI_EN_COORD_REMOTE /workspace/.pi-en/agent-remotes/derived.git

local_project="$tmpdir/local-project"
mkdir -p "$local_project/.pi-en/agent-remotes/local.git/objects"
cat >"$local_project/.pi-en-coordination.yaml" <<'YAML'
version: 1
coordination_remote: .pi-en/agent-remotes/local.git
YAML
local_capture="$tmpdir/local-capture"
run_harness "$local_project" "$local_capture"
assert_no_arg_pair "$local_capture" --tmpfs /workspace/.pi-en/agent-remotes
assert_no_exact_line "$local_capture" "$local_project/.pi-en/agent-remotes/local.git"
assert_arg_triple "$local_capture" --setenv \
  PI_EN_COORD_REMOTE /workspace/.pi-en/agent-remotes/local.git

absolute_project="$tmpdir/absolute-project"
mkdir -p "$absolute_project"
cat >"$absolute_project/.pi-en-coordination.yaml" <<YAML
version: 1
coordination_remote: $external_remote
YAML
absolute_capture="$tmpdir/absolute-capture"
run_harness "$absolute_project" "$absolute_capture"
assert_arg_triple "$absolute_capture" --bind \
  "$external_remote" /workspace/.pi-en/agent-remotes/derived.git
assert_no_exact_line "$absolute_capture" "$external_parent"
assert_no_exact_line "$absolute_capture" "$external_sibling"

missing_external="$external_parent/missing.git"
missing_capture="$tmpdir/missing-capture"
run_harness "$tmpdir/missing-project" "$missing_capture" \
  PI_EN_COORD_REMOTE="$missing_external"
assert_arg_triple "$missing_capture" --setenv \
  PI_EN_COORD_REMOTE "$missing_external"
assert_no_exact_line "$missing_capture" /agent-remotes/missing.git
assert_no_exact_line "$missing_capture" "$external_parent"
assert_no_exact_line "$missing_capture" "$external_sibling"

printf 'PIEN-ISS-20260805-173230-001 passed\n'
