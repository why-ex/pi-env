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
test_grep 'PI_EN_COORD_REMOTE' "$script"
test_grep '/agent-remotes' "$script"

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
    unset PI_EN_COORD_REMOTE PI_EN_COORD_DIR
    env \
      PATH="$fakebin:$PATH" \
      PI_EN_RUNTIME_PATH="$tmpdir/runtime/bin" \
      PI_EN_BWRAP_BWRAP="$tmpdir/fake-bwrap" \
      PI_EN_TEST_FAKE_BWRAP="$tmpdir/fake-bwrap" \
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

assert_no_grep() {
  local pattern path
  pattern="$1"
  path="$2"
  if grep -q -- "$pattern" "$path"; then
    test_fail "expected $path not to match: $pattern"
  fi
}

remote_capture="$tmpdir/remote-capture"
run_harness "$tmpdir/url-project" "$remote_capture" \
  PI_EN_COORD_REMOTE='https://git.example.invalid/pi-en-coordination.git'

test_grep '^PI_EN_COORD_REMOTE$' "$remote_capture"
test_grep '^https://git.example.invalid/pi-en-coordination.git$' "$remote_capture"
assert_no_grep '^/agent-remotes$' "$remote_capture"
assert_no_grep '^/workspace/agent-remotes$' "$remote_capture"

config_local_project="$tmpdir/config-local-project"
mkdir -p "$config_local_project/.pi-en/agent-remotes"
cat >"$config_local_project/.pi-en-coordination.yaml" <<'YAML'
version: 1
coordination_remote: .pi-en/agent-remotes/config-local-coordination.git
YAML
config_local_capture="$tmpdir/config-local-capture"
run_harness "$config_local_project" "$config_local_capture"
test_grep '^PI_EN_COORD_REMOTE$' "$config_local_capture"
test_grep '^/workspace/.pi-en/agent-remotes/config-local-coordination.git$' "$config_local_capture"

env_remote_parent="$tmpdir/env-remotes"
mkdir -p "$env_remote_parent/env-coordination.git"
env_remote_capture="$tmpdir/env-remote-capture"
run_harness "$tmpdir/env-remote-project" "$env_remote_capture" \
  PI_EN_COORD_REMOTE="$env_remote_parent/env-coordination.git"
test_grep '^PI_EN_COORD_REMOTE$' "$env_remote_capture"
test_grep '^/agent-remotes/env-coordination.git$' "$env_remote_capture"
test_grep "^$env_remote_parent/env-coordination.git$" "$env_remote_capture"
assert_no_grep "^$env_remote_parent$" "$env_remote_capture"

config_external_project="$tmpdir/config-external-project"
mkdir -p "$config_external_project" "$tmpdir/config-external-remotes/config-external.git/objects"
cat >"$config_external_project/.pi-en-coordination.yaml" <<YAML
version: 1
coordination_remote: $tmpdir/config-external-remotes/config-external.git
YAML
config_external_capture="$tmpdir/config-external-capture"
run_harness "$config_external_project" "$config_external_capture"
test_grep '^/workspace/.pi-en/agent-remotes$' "$config_external_capture"
test_grep "^$tmpdir/config-external-remotes/config-external.git$" "$config_external_capture"
assert_no_grep "^$tmpdir/config-external-remotes$" "$config_external_capture"
test_grep '^/workspace/.pi-en/agent-remotes/config-external.git$' "$config_external_capture"

config_external_nonbare_project="$tmpdir/config-external-nonbare-project"
mkdir -p "$config_external_nonbare_project" "$tmpdir/config-external-nonbare-remotes/config-external.git"
cat >"$config_external_nonbare_project/.pi-en-coordination.yaml" <<YAML
version: 1
coordination_remote: $tmpdir/config-external-nonbare-remotes/config-external.git
YAML
config_external_nonbare_capture="$tmpdir/config-external-nonbare-capture"
run_harness "$config_external_nonbare_project" "$config_external_nonbare_capture"
assert_no_grep '^/workspace/.pi-en/agent-remotes$' "$config_external_nonbare_capture"
assert_no_grep "^$tmpdir/config-external-nonbare-remotes$" "$config_external_nonbare_capture"

home_capture="$tmpdir/home-safety-capture"
run_harness "$tmpdir/home-safety-project" "$home_capture" \
  PI_EN_COORD_REMOTE='ssh://git.example.invalid/pi-en.git'
assert_no_grep "^$HOME/.ssh$" "$home_capture"
assert_no_grep '/\.ssh$' "$home_capture"
assert_no_grep 'bind.*\.ssh' "$script"
assert_no_grep 'host_home.*--bind' "$script"

coord_project="$tmpdir/coord-project"
mkdir -p "$coord_project/.pi-en/coordination/.git"
touch "$coord_project/.pi-en/coordination/AGENTS.md"
coord_capture="$tmpdir/coord-capture"
run_harness "$coord_project" "$coord_capture"
test_grep '^PI_EN_COORD_DIR$' "$coord_capture"
test_grep '^/workspace/.pi-en/coordination$' "$coord_capture"

compat_capture="$tmpdir/compat-capture"
run_harness "$tmpdir/compat-project" "$compat_capture"
assert_no_grep '^/workspace/agent-remotes$' "$compat_capture"

modern_coord_project="$tmpdir/modern-coord-project"
mkdir -p "$modern_coord_project/.pi-en/coordination"
modern_coord_capture="$tmpdir/modern-coord-capture"
run_harness "$modern_coord_project" "$modern_coord_capture"
assert_no_grep '^/workspace/agent-remotes$' "$modern_coord_capture"

modern_remotes_project="$tmpdir/modern-remotes-project"
mkdir -p "$modern_remotes_project/.pi-en/agent-remotes"
modern_remotes_capture="$tmpdir/modern-remotes-capture"
run_harness "$modern_remotes_project" "$modern_remotes_capture"
assert_no_grep '^/workspace/agent-remotes$' "$modern_remotes_capture"

root_remotes_project="$tmpdir/root-remotes-project"
mkdir -p "$root_remotes_project/agent-remotes"
root_remotes_capture="$tmpdir/root-remotes-capture"
run_harness "$root_remotes_project" "$root_remotes_capture"
assert_no_grep '^/workspace/agent-remotes$' "$root_remotes_capture"

echo "simple coordination remote mount tests passed"
