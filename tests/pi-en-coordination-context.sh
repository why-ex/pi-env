#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
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

run_bwrap() {
  local project state capture
  project="$1"
  state="$2"
  capture="$3"
  shift 3
  mkdir -p "$project" "$state" "$tmpdir/runtime/bin"
  (
    cd "$project"
    unset PI_EN_COORD_REMOTE PI_EN_COORD_DIR PI_EN_BWRAP_COORDINATION_DIR
    env \
      HOME="$tmpdir/home" \
      PATH="$fakebin:$PATH" \
      PI_EN_BWRAP_BASH=/bin/bash \
      PI_EN_BWRAP_ENV=/usr/bin/env \
      PI_EN_BWRAP_BWRAP="$tmpdir/fake-bwrap" \
      PI_EN_RUNTIME_PATH="$tmpdir/runtime/bin" \
      PI_EN_TEST_CAPTURE="$capture" \
      PI_EN_BWRAP_PROJECT_ROOT="$project" \
      PI_EN_BWRAP_STATE_DIR="$state" \
      PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
      PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
      PI_EN_BWRAP_IMPORT_AUTH=0 \
      PI_EN_BWRAP_IMPORT_SESSIONS=0 \
      "$@" "$script" -- --version
  )
}

assert_contains() {
  local needle path
  needle="$1"
  path="$2"
  grep -Fq -- "$needle" "$path" || test_fail "expected $path to contain: $needle"
}

assert_not_contains() {
  local needle path
  needle="$1"
  path="$2"
  if [ -e "$path" ] && grep -Fq -- "$needle" "$path"; then
    test_fail "expected $path not to contain: $needle"
  fi
}

common_dir="$tmpdir/common-agent"
mkdir -p "$common_dir"
printf '# Common agent rules\n' >"$common_dir/AGENTS.md"

coord_project="$tmpdir/coord-project"
mkdir -p "$coord_project/.pi-en/coordination/.git"
printf '# Domain coordination rules\n' >"$coord_project/.pi-en/coordination/AGENTS.md"
state="$tmpdir/state"
run_bwrap "$coord_project" "$state" "$tmpdir/coord-capture" \
  PI_EN_BWRAP_COMMON_AGENT_DIR="$common_dir"
context_file="$state/agent/AGENTS.md"

test_file_exists "$context_file"
assert_contains '# Common agent rules' "$context_file"
assert_contains '<!-- pi-en generated coordination context: begin -->' "$context_file"
assert_contains 'Pi-en coordination context' "$context_file"
assert_contains 'read and follow' "$context_file"
assert_contains '`/workspace/.pi-en/coordination/AGENTS.md`' "$context_file"
assert_contains 'Prefer the sandbox-safe helper namespace over hand-editing' "$context_file"
assert_contains 'pien coord requirements generate --output REQUIREMENTS.md' "$context_file"
assert_contains 'domain_generated_files' "$context_file"

run_bwrap "$coord_project" "$state" "$tmpdir/coord-capture-2" \
  PI_EN_BWRAP_COMMON_SYNC=missing \
  PI_EN_BWRAP_COMMON_AGENT_DIR="$common_dir"
count="$(grep -Fc '<!-- pi-en generated coordination context: begin -->' "$context_file")"
test_eq 1 "$count" 'generated coordination context should be idempotent'

plain_project="$tmpdir/plain-project"
mkdir -p "$plain_project"
run_bwrap "$plain_project" "$state" "$tmpdir/plain-capture" \
  PI_EN_BWRAP_IMPORT_COMMON=0
assert_not_contains '<!-- pi-en generated coordination context: begin -->' "$context_file"

printf 'pi-en coordination context tests passed\n'
