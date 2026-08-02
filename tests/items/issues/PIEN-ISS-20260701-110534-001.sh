#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

fakebin="$tmpdir/fakebin"
mkdir -p "$fakebin"

cat >"$fakebin/pi" <<'FAKE_PI'
#!/usr/bin/env bash
echo 'fake pi should not run outside bwrap' >&2
exit 99
FAKE_PI
chmod +x "$fakebin/pi"

cat >"$fakebin/bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PI_EN_TEST_BWRAP_ARGS"
FAKE_BWRAP
chmod +x "$fakebin/bwrap"
: >"$tmpdir/host-bash"
: >"$tmpdir/host-env"
chmod +x "$tmpdir/host-bash" "$tmpdir/host-env"

capture="$tmpdir/bwrap-args"
PATH="$fakebin:$PATH" \
  PI_EN_HOST_RUNTIME=1 \
  PI_EN_TEST_BWRAP_ARGS="$capture" \
  PI_EN_BWRAP_BASH="$tmpdir/host-bash" \
  PI_EN_BWRAP_ENV="$tmpdir/host-env" \
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
  PI_EN_BWRAP_HOST_EXTRA_PATH="$fakebin" \
  PI_EN_BWRAP_IMPORT_COMMON=0 \
  PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
  PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
  PI_EN_BWRAP_IMPORT_AUTH=0 \
  PI_EN_BWRAP_IMPORT_SESSIONS=0 \
  ./pi-en --raw -- --help

test_file_exists "$capture"

sandbox_path="$(awk 'prev == "--setenv" && $0 == "PATH" { getline; print; exit } { prev = $0 }' "$capture")"
[ -n "$sandbox_path" ] || test_fail 'fake bwrap capture did not include sandbox PATH'
case "$sandbox_path" in
  :*|*::*|*:)
    test_fail "host runtime sandbox PATH contains an empty entry: $sandbox_path"
    ;;
esac
case "$sandbox_path" in
  *'/nix/store/'*)
    test_fail "host runtime sandbox PATH inherited caller Nix-store entries: $sandbox_path"
    ;;
esac

if grep -qx -- '--symlink' "$capture"; then
  test_fail 'host runtime should use host command directory binds instead of fixed shell symlinks'
fi
if grep -qx 'bash' "$capture"; then
  test_fail 'host runtime used unresolved bash as a bwrap exec target'
fi
if ! grep -qx '/pi-en-tools/bash' "$capture"; then
  test_fail 'host runtime did not mount bash at a non-conflicting sandbox path'
fi
if ! grep -qx '/pi-en-tools/env' "$capture"; then
  test_fail 'host runtime did not mount env at a non-conflicting sandbox path'
fi
for host_tool_dir in /bin /usr/bin; do
  if ! awk -v dir="$host_tool_dir" 'prev == "--ro-bind-try" && $0 == dir { getline; if ($0 == dir) found = 1 } { prev = $0 } END { exit found ? 0 : 1 }' "$capture"; then
    test_fail "host runtime did not bind host command directory read-only: $host_tool_dir"
  fi
done
if awk 'prev == "--ro-bind" && $0 == "/nix/store" { getline; if ($0 == "/nix/store") found = 1 } { prev = $0 } END { exit found ? 0 : 1 }' "$capture"; then
  test_fail 'host runtime still requires a /nix/store bind'
fi

cat >"$fakebin/realpath" <<'FAKE_REALPATH'
#!/usr/bin/env bash
echo 'fake realpath should not run before PI_EN_RUNTIME_PATH tools' >&2
exit 42
FAKE_REALPATH
chmod +x "$fakebin/realpath"

runtime_tool_path="$(dirname "$(command -v realpath)")"
runtime_capture="$tmpdir/runtime-bwrap-args"
PATH="$fakebin:$PATH" \
  PI_EN_RUNTIME_PATH="$runtime_tool_path" \
  PI_EN_TEST_BWRAP_ARGS="$runtime_capture" \
  PI_EN_BWRAP_BASH="$tmpdir/host-bash" \
  PI_EN_BWRAP_ENV="$tmpdir/host-env" \
  PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
  PI_EN_BWRAP_IMPORT_COMMON=0 \
  PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
  PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
  PI_EN_BWRAP_IMPORT_AUTH=0 \
  PI_EN_BWRAP_IMPORT_SESSIONS=0 \
  scripts/pi-en-bwrap -- --help

test_file_exists "$runtime_capture"
runtime_sandbox_path="$(awk 'prev == "--setenv" && $0 == "PATH" { getline; print; exit } { prev = $0 }' "$runtime_capture")"
case "$runtime_sandbox_path" in
  "$runtime_tool_path":*) ;;
  *)
    test_fail "Nix runtime sandbox PATH did not keep PI_EN_RUNTIME_PATH first: $runtime_sandbox_path"
    ;;
esac

echo 'launcher runtime path precedence fake-bwrap test passed'
