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
host_home="$tmpdir/host-home"
custom_tools="$tmpdir/custom-tools"
external_role_manager="$tmpdir/external-role-manager"
mkdir -p "$fakebin" "$host_home/bin" "$custom_tools" "$external_role_manager"

cat >"$custom_tools/pi" <<'FAKE_PI'
#!/usr/bin/env bash
echo 'fake pi should not run outside bwrap' >&2
exit 99
FAKE_PI
chmod +x "$custom_tools/pi"

cat >"$host_home/bin/pi" <<'FAKE_PI'
#!/usr/bin/env bash
echo 'home pi should fail before bwrap' >&2
exit 99
FAKE_PI
chmod +x "$host_home/bin/pi"

cat >"$fakebin/bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PI_EN_TEST_BWRAP_ARGS"
FAKE_BWRAP
chmod +x "$fakebin/bwrap"

: >"$tmpdir/host-bash"
: >"$tmpdir/host-env"
chmod +x "$tmpdir/host-bash" "$tmpdir/host-env"

common_env=(
  PI_EN_BWRAP_BASH="$tmpdir/host-bash"
  PI_EN_BWRAP_ENV="$tmpdir/host-env"
  PI_EN_BWRAP_BWRAP="$fakebin/bwrap"
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root"
  PI_EN_BWRAP_IMPORT_COMMON=0
  PI_EN_BWRAP_IMPORT_EXTENSIONS=0
  PI_EN_BWRAP_IMPORT_GIT_CONFIG=0
  PI_EN_BWRAP_IMPORT_AUTH=0
  PI_EN_BWRAP_IMPORT_SESSIONS=0
)

home_pi_status=0
env HOME="$host_home" \
  PATH="$host_home/bin:$fakebin:$PATH" \
  PI_EN_TEST_BWRAP_ARGS="$tmpdir/home-pi-args" \
  "${common_env[@]}" \
  scripts/pi-en-bwrap -- --help >"$tmpdir/home-pi-output" 2>&1 || home_pi_status=$?
test_eq 127 "$home_pi_status" 'host HOME pi is rejected before bwrap'
test_grep 'resolved pi under host HOME' "$tmpdir/home-pi-output"
if [ -e "$tmpdir/home-pi-args" ]; then
  test_fail 'host HOME pi reached bwrap'
fi

outside_pi_status=0
env HOME="$host_home" \
  PATH="$custom_tools:$fakebin:$PATH" \
  PI_EN_TEST_BWRAP_ARGS="$tmpdir/outside-pi-args" \
  "${common_env[@]}" \
  scripts/pi-en-bwrap -- --help >"$tmpdir/outside-pi-output" 2>&1 || outside_pi_status=$?
test_eq 127 "$outside_pi_status" 'unmounted custom pi is rejected before bwrap'
test_grep 'resolved pi outside default sandbox mounts' "$tmpdir/outside-pi-output"
if [ -e "$tmpdir/outside-pi-args" ]; then
  test_fail 'unmounted custom pi reached bwrap'
fi

custom_capture="$tmpdir/custom-pi-args"
env HOME="$host_home" \
  PATH="$custom_tools:$fakebin:$PATH" \
  PI_EN_TEST_BWRAP_ARGS="$custom_capture" \
  PI_EN_BWRAP_HOST_EXTRA_PATH="$custom_tools" \
  "${common_env[@]}" \
  scripts/pi-en-bwrap -e "$external_role_manager" --help

test_file_exists "$custom_capture"
if ! awk -v dir="$custom_tools" 'prev == "--ro-bind" && $0 == dir { getline; if ($0 == dir) found = 1 } { prev = $0 } END { exit found ? 0 : 1 }' "$custom_capture"; then
  test_fail 'custom pi command directory was not bound read-only'
fi
if ! awk -v src="$external_role_manager" 'prev == "--ro-bind" && $0 == src { getline; if ($0 == "/pi-en-resources/role-manager-1") found = 1 } { prev = $0 } END { exit found ? 0 : 1 }' "$custom_capture"; then
  test_fail 'external role-manager was not bound read-only at sandbox resource path'
fi
test_grep '/pi-en-resources/role-manager-1' "$custom_capture"

checkout_capture="$tmpdir/checkout-role-manager-args"
env HOME="$host_home" \
  PATH="$custom_tools:$fakebin:$PATH" \
  PI_EN_TEST_BWRAP_ARGS="$checkout_capture" \
  PI_EN_BWRAP_HOST_EXTRA_PATH="$custom_tools" \
  "${common_env[@]}" \
  scripts/pi-en-bwrap -e "$repo_root/role-manager" --help

test_file_exists "$checkout_capture"
test_grep '/workspace/role-manager' "$checkout_capture"
if grep -F -- '/pi-en-resources/role-manager-1' "$checkout_capture" >/dev/null 2>&1; then
  test_fail 'checkout role-manager should not require an extra resource bind'
fi

pi_en_capture="$tmpdir/pi-en-role-manager-args"
env HOME="$host_home" \
  PATH="$custom_tools:$fakebin:$PATH" \
  PI_EN_RUNTIME=auto \
  PI_EN_TEST_BWRAP_ARGS="$pi_en_capture" \
  PI_EN_BWRAP_HOST_EXTRA_PATH="$custom_tools" \
  PI_EN_PI_EN_BWRAP="$repo_root/scripts/pi-en-bwrap" \
  "${common_env[@]}" \
  ./pi-en 'prompt'

test_file_exists "$pi_en_capture"
test_grep '/workspace/role-manager' "$pi_en_capture"

echo 'host pi and role-manager resource policy fake-bwrap test passed'
