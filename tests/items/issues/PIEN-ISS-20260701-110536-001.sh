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

original_path="$PATH"
fakebin="$tmpdir/fakebin"
mkdir -p "$fakebin"
export PI_EN_BWRAP_HOST_EXTRA_PATH="$fakebin"

cat >"$fakebin/nix" <<'FAKE_NIX'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PI_EN_TEST_NIX_ARGS"
FAKE_NIX
chmod +x "$fakebin/nix"

cat >"$fakebin/pi" <<'FAKE_PI'
#!/usr/bin/env bash
exit 0
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

host_capture="$tmpdir/default-host-bwrap-args"
nix_capture="$tmpdir/default-host-nix-args"
PATH="$fakebin:$original_path" \
  PI_EN_TEST_BWRAP_ARGS="$host_capture" \
  PI_EN_TEST_NIX_ARGS="$nix_capture" \
  PI_EN_BWRAP_BASH="$tmpdir/host-bash" \
  PI_EN_BWRAP_ENV="$tmpdir/host-env" \
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
  PI_EN_BWRAP_IMPORT_COMMON=0 \
  PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
  PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
  PI_EN_BWRAP_IMPORT_AUTH=0 \
  PI_EN_BWRAP_IMPORT_SESSIONS=0 \
  ./pi-en --raw -- --help

test_file_exists "$host_capture"
if [ -e "$nix_capture" ]; then
  test_fail 'direct checkout default runtime invoked nix develop'
fi

stale_default_host_capture="$tmpdir/stale-default-host-bwrap-args"
stale_default_nix_capture="$tmpdir/stale-default-nix-args"
PATH="$fakebin:$original_path" \
  PI_EN_RUNTIME_PATH="$tmpdir/stale-nix-runtime/bin" \
  PI_EN_TEST_BWRAP_ARGS="$stale_default_host_capture" \
  PI_EN_TEST_NIX_ARGS="$stale_default_nix_capture" \
  PI_EN_BWRAP_BASH="$tmpdir/host-bash" \
  PI_EN_BWRAP_ENV="$tmpdir/host-env" \
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
  PI_EN_BWRAP_IMPORT_COMMON=0 \
  PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
  PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
  PI_EN_BWRAP_IMPORT_AUTH=0 \
  PI_EN_BWRAP_IMPORT_SESSIONS=0 \
  ./pi-en --raw -- --help

test_file_exists "$stale_default_host_capture"
if [ -e "$stale_default_nix_capture" ]; then
  test_fail 'direct checkout default runtime with stale runtime path invoked nix develop'
fi
if grep -F -- '/nix/store' "$stale_default_host_capture" >/dev/null 2>&1; then
  test_fail 'direct checkout default runtime used stale Nix runtime bind arguments'
fi

explicit_host_capture="$tmpdir/explicit-host-bwrap-args"
PI_EN_RUNTIME_PATH="$tmpdir/fake-nix-runtime/bin"
PATH="$fakebin:$original_path" \
  PI_EN_RUNTIME=host \
  PI_EN_RUNTIME_PATH="$PI_EN_RUNTIME_PATH" \
  PI_EN_TEST_BWRAP_ARGS="$explicit_host_capture" \
  PI_EN_BWRAP_BASH="$tmpdir/host-bash" \
  PI_EN_BWRAP_ENV="$tmpdir/host-env" \
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
  PI_EN_BWRAP_IMPORT_COMMON=0 \
  PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
  PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
  PI_EN_BWRAP_IMPORT_AUTH=0 \
  PI_EN_BWRAP_IMPORT_SESSIONS=0 \
  ./pi-en --raw -- --help

test_file_exists "$explicit_host_capture"
if grep -F -- '/nix/store' "$explicit_host_capture" >/dev/null 2>&1; then
  test_fail 'explicit host runtime used Nix runtime bind arguments'
fi

explicit_nix_capture="$tmpdir/explicit-nix-args"
PATH="$fakebin:$original_path" \
  PI_EN_TEST_NIX_ARGS="$explicit_nix_capture" \
  ./pi-en --runtime nix --raw -- --help

test_file_exists "$explicit_nix_capture"
expected_nix="$(printf '%s\n' develop "$repo_root" -c pi-en --raw -- --help)"
actual_nix="$(<"$explicit_nix_capture")"
test_eq "$expected_nix" "$actual_nix" 'explicit --runtime nix did not invoke expected nix develop path'

precedence_capture="$tmpdir/precedence-nix-args"
PATH="$fakebin:$original_path" \
  PI_EN_RUNTIME=host \
  PI_EN_TEST_NIX_ARGS="$precedence_capture" \
  ./pi-en --runtime nix --help >/dev/null 2>&1 || true
# --help exits before runtime dispatch, so use a pi arg instead.
PATH="$fakebin:$original_path" \
  PI_EN_RUNTIME=host \
  PI_EN_TEST_NIX_ARGS="$precedence_capture" \
  ./pi-en --runtime nix --raw -- --version

test_file_exists "$precedence_capture"

if PI_EN_RUNTIME=bogus ./pi-en --help >/dev/null 2>&1; then
  : # help is allowed before validating runtime for discoverability
fi
if PI_EN_RUNTIME=bogus ./pi-en --raw -- --help >/dev/null 2>"$tmpdir/invalid.err"; then
  test_fail 'invalid PI_EN_RUNTIME was accepted'
fi
test_grep 'invalid PI_EN_RUNTIME value: bogus' "$tmpdir/invalid.err"

if PI_EN_RUNTIME= ./pi-en --raw -- --help >/dev/null 2>"$tmpdir/empty-env.err"; then
  test_fail 'empty PI_EN_RUNTIME was accepted'
fi
test_grep 'invalid PI_EN_RUNTIME value:' "$tmpdir/empty-env.err"

if ./pi-en --runtime= --raw -- --help >/dev/null 2>"$tmpdir/empty-cli.err"; then
  test_fail 'empty --runtime= was accepted'
fi
test_grep 'invalid --runtime value:' "$tmpdir/empty-cli.err"

echo 'pi-en runtime mode selection test passed'
