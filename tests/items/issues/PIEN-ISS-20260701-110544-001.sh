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
nixless_bin="$tmpdir/nixless-bin"
host_home="$tmpdir/host-home"
unrelated_project="$tmpdir/unrelated-project"
mkdir -p "$fakebin" "$nixless_bin" "$host_home/bin" "$host_home/.ssh" "$host_home/.aws" "$unrelated_project"
for cmd in bash dirname; do
  cmd_path="$(command -v "$cmd")" || test_fail "test setup could not find required command: $cmd"
  ln -s "$cmd_path" "$nixless_bin/$cmd"
done

cat >"$fakebin/pi" <<'FAKE_PI'
#!/usr/bin/env bash
echo 'fake pi should only run inside fake bwrap' >&2
exit 99
FAKE_PI
chmod +x "$fakebin/pi"

cat >"$host_home/bin/pi" <<'FAKE_HOME_PI'
#!/usr/bin/env bash
echo 'host home pi should fail closed before bwrap' >&2
exit 99
FAKE_HOME_PI
chmod +x "$host_home/bin/pi"

cat >"$fakebin/bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PI_EN_TEST_BWRAP_ARGS"
FAKE_BWRAP
chmod +x "$fakebin/bwrap"

cat >"$fakebin/nix" <<'FAKE_NIX'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PI_EN_TEST_NIX_ARGS"
exit "${PI_EN_TEST_NIX_EXIT:-66}"
FAKE_NIX
chmod +x "$fakebin/nix"

: >"$tmpdir/host-bash"
: >"$tmpdir/host-env"
chmod +x "$tmpdir/host-bash" "$tmpdir/host-env"

common_bwrap_env=(
  PI_EN_BWRAP_BASH="$tmpdir/host-bash"
  PI_EN_BWRAP_ENV="$tmpdir/host-env"
  PI_EN_BWRAP_BWRAP="$fakebin/bwrap"
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root"
  PI_EN_BWRAP_STATE_DIR="$tmpdir/state"
  PI_EN_BWRAP_HOST_EXTRA_PATH="$fakebin"
  PI_EN_BWRAP_IMPORT_COMMON=0
  PI_EN_BWRAP_IMPORT_EXTENSIONS=0
  PI_EN_BWRAP_IMPORT_GIT_CONFIG=0
  PI_EN_BWRAP_IMPORT_AUTH=0
  PI_EN_BWRAP_IMPORT_SESSIONS=0
)

host_capture="$tmpdir/default-host-bwrap-args"
env -u PI_EN_RUNTIME -u PI_EN_PI_START -u PI_EN_PI_EN_BWRAP \
  HOME="$host_home" \
  PATH="$fakebin:$PATH" \
  PI_EN_TEST_BWRAP_ARGS="$host_capture" \
  PI_EN_TEST_NIX_ARGS="$tmpdir/default-host-nix-args" \
  "${common_bwrap_env[@]}" \
  ./pi-en --raw -- --help

test_file_exists "$host_capture"
if [ -e "$tmpdir/default-host-nix-args" ]; then
  test_fail 'default direct checkout host runtime unexpectedly invoked nix'
fi

sandbox_path="$(awk 'prev == "--setenv" && $0 == "PATH" { getline; print; exit } { prev = $0 }' "$host_capture")"
[ -n "$sandbox_path" ] || test_fail 'fake bwrap capture did not include sandbox PATH'
case "$sandbox_path" in
  "$fakebin":/usr/local/bin:/usr/bin:/bin) ;;
  *) test_fail "host runtime sandbox PATH did not use validated host command dirs: $sandbox_path" ;;
esac

if ! awk -v dir="$fakebin" 'prev == "--ro-bind" && $0 == dir { getline; if ($0 == dir) found = 1 } { prev = $0 } END { exit found ? 0 : 1 }' "$host_capture"; then
  test_fail 'host runtime extra command directory was not mounted read-only'
fi
for dir in /bin /usr/bin /usr/local/bin; do
  if ! awk -v dir="$dir" 'prev == "--ro-bind-try" && $0 == dir { getline; if ($0 == dir) found = 1 } { prev = $0 } END { exit found ? 0 : 1 }' "$host_capture"; then
    test_fail "host runtime did not mount command directory read-only: $dir"
  fi
done
if ! awk 'prev == "--ro-bind-try" && $0 == "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent" { getline; if ($0 == "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent") found = 1 } { prev = $0 } END { exit found ? 0 : 1 }' "$host_capture"; then
  test_fail 'host runtime did not keep the global Pi package read-only'
fi
if awk 'prev == "--bind" && $0 == "/nix/store" { getline; if ($0 == "/nix/store") found = 1 } { prev = $0 } END { exit found ? 0 : 1 }' "$host_capture"; then
  test_fail 'default host runtime should not require a writable /nix/store bind'
fi

for forbidden in \
  "$host_home" \
  "$host_home/.ssh" \
  "$host_home/.aws" \
  /var/run/docker.sock \
  /run/docker.sock \
  "$unrelated_project"; do
  if grep -F -- "$forbidden" "$host_capture" >/dev/null 2>&1; then
    test_fail "host runtime mounted forbidden host path by default: $forbidden"
  fi
done

home_pi_status=0
env -u PI_EN_RUNTIME -u PI_EN_PI_START -u PI_EN_PI_EN_BWRAP \
  HOME="$host_home" \
  PATH="$host_home/bin:$fakebin:$PATH" \
  PI_EN_TEST_BWRAP_ARGS="$tmpdir/home-pi-en-bwrap-args" \
  "${common_bwrap_env[@]}" \
  ./pi-en --raw -- --help >"$tmpdir/home-pi-output" 2>&1 || home_pi_status=$?
test_eq 127 "$home_pi_status" 'host-home pi is rejected fail-closed'
test_grep 'host runtime resolved pi under host HOME' "$tmpdir/home-pi-output"
if [ -e "$tmpdir/home-pi-en-bwrap-args" ]; then
  test_fail 'host-home pi reached bwrap despite fail-closed policy'
fi

missing_dep_status=0
env -u PI_EN_RUNTIME -u PI_EN_PI_START -u PI_EN_PI_EN_BWRAP \
  HOME="$host_home" \
  PATH="$fakebin:$PATH" \
  PI_EN_BWRAP_BWRAP="$tmpdir/missing-bwrap" \
  PI_EN_BWRAP_BASH="$tmpdir/host-bash" \
  PI_EN_BWRAP_ENV="$tmpdir/host-env" \
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
  PI_EN_BWRAP_STATE_DIR="$tmpdir/missing-dep-state" \
  PI_EN_BWRAP_HOST_EXTRA_PATH="$fakebin" \
  PI_EN_BWRAP_IMPORT_COMMON=0 \
  PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
  PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
  PI_EN_BWRAP_IMPORT_AUTH=0 \
  PI_EN_BWRAP_IMPORT_SESSIONS=0 \
  ./pi-en --raw -- --help >"$tmpdir/missing-dep-output" 2>&1 || missing_dep_status=$?
test_eq 127 "$missing_dep_status" 'missing host bwrap dependency exits 127'
test_grep 'required host tool path does not exist: bwrap' "$tmpdir/missing-dep-output"

nix_capture="$tmpdir/explicit-nix-args"
env -u PI_EN_RUNTIME -u PI_EN_PI_START -u PI_EN_PI_EN_BWRAP \
  HOME="$host_home" \
  PATH="$fakebin:$PATH" \
  PI_EN_TEST_NIX_ARGS="$nix_capture" \
  PI_EN_TEST_NIX_EXIT=0 \
  ./pi-en --runtime nix --raw -- --help

test_file_exists "$nix_capture"
expected_nix="$tmpdir/expected-nix-args"
printf '%s\n' develop "$repo_root" -c pi-en --raw -- --help >"$expected_nix"
if [ "$(cat "$expected_nix")" != "$(cat "$nix_capture")" ]; then
  printf 'expected nix args:\n' >&2
  cat "$expected_nix" >&2
  printf 'actual nix args:\n' >&2
  cat "$nix_capture" >&2
  test_fail 'explicit nix runtime did not preserve nix develop fallback arguments'
fi

nix_missing_status=0
env -u PI_EN_RUNTIME -u PI_EN_PI_START -u PI_EN_PI_EN_BWRAP \
  HOME="$host_home" \
  PATH="$nixless_bin" \
  ./pi-en --runtime nix --raw -- --help >"$tmpdir/missing-nix-output" 2>&1 || nix_missing_status=$?
test_eq 127 "$nix_missing_status" 'explicit nix runtime reports missing nix'
test_grep "runtime mode 'nix' requires nix" "$tmpdir/missing-nix-output"

echo 'host runtime blackbox verification test passed'
