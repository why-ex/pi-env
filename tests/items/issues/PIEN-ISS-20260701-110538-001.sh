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
mkdir -p "$fakebin" "$tmpdir/actual-tools" "$host_home"
ln -s "$tmpdir/actual-tools" "$tmpdir/linked-tools"

cat >"$tmpdir/actual-tools/pi" <<'FAKE_PI'
#!/usr/bin/env bash
echo 'fake pi should not run outside bwrap' >&2
exit 99
FAKE_PI
chmod +x "$tmpdir/actual-tools/pi"

cat >"$fakebin/bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PI_EN_TEST_BWRAP_ARGS"
FAKE_BWRAP
chmod +x "$fakebin/bwrap"

: >"$tmpdir/host-bash"
: >"$tmpdir/host-env"
chmod +x "$tmpdir/host-bash" "$tmpdir/host-env"

host_capture="$tmpdir/host-bwrap-args"
HOME="$host_home" \
  PATH="$tmpdir/actual-tools:$fakebin:$PATH" \
  PI_EN_TEST_BWRAP_ARGS="$host_capture" \
  PI_EN_BWRAP_BASH="$tmpdir/host-bash" \
  PI_EN_BWRAP_ENV="$tmpdir/host-env" \
  PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
  PI_EN_BWRAP_HOST_EXTRA_PATH="$tmpdir/linked-tools" \
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
  PI_EN_BWRAP_IMPORT_COMMON=0 \
  PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
  PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
  PI_EN_BWRAP_IMPORT_AUTH=0 \
  PI_EN_BWRAP_IMPORT_SESSIONS=0 \
  scripts/pi-en-bwrap -- --help

test_file_exists "$host_capture"

host_sandbox_path="$(awk 'prev == "--setenv" && $0 == "PATH" { getline; print; exit } { prev = $0 }' "$host_capture")"
case "$host_sandbox_path" in
  *"$tmpdir/linked-tools"*)
    test_fail "host runtime PATH used non-canonical extra path: $host_sandbox_path"
    ;;
esac
case "$host_sandbox_path" in
  *"$tmpdir/actual-tools"*) ;;
  *)
    test_fail "host runtime PATH omitted canonical extra path: $host_sandbox_path"
    ;;
esac
case "$host_sandbox_path" in
  *"$fakebin"*)
    test_fail "host runtime PATH inherited caller PATH entry: $host_sandbox_path"
    ;;
esac

if ! awk -v dir="$tmpdir/actual-tools" 'prev == "--ro-bind" && $0 == dir { getline; if ($0 == dir) found = 1 } { prev = $0 } END { exit found ? 0 : 1 }' "$host_capture"; then
  test_fail 'host runtime did not bind canonical extra command directory read-only'
fi
if grep -F -- "$tmpdir/linked-tools" "$host_capture" >/dev/null 2>&1; then
  test_fail 'host runtime bwrap args included non-canonical extra command path'
fi
for sensitive in "$host_home" "$host_home/.ssh" "$host_home/.aws" "$host_home/.config/gcloud" /var/run/docker.sock; do
  if [ -n "$sensitive" ] && grep -Fx -- "$sensitive" "$host_capture" >/dev/null 2>&1; then
    test_fail "host runtime mounted sensitive path by default: $sensitive"
  fi
done

home_extra_status=0
HOME="$host_home" \
  PATH="$tmpdir/actual-tools:$fakebin:$PATH" \
  PI_EN_TEST_BWRAP_ARGS="$tmpdir/home-extra-args" \
  PI_EN_BWRAP_BASH="$tmpdir/host-bash" \
  PI_EN_BWRAP_ENV="$tmpdir/host-env" \
  PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
  PI_EN_BWRAP_HOST_EXTRA_PATH="$tmpdir/actual-tools:$host_home" \
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
  scripts/pi-en-bwrap -- --help >"$tmpdir/home-extra-output" 2>&1 || home_extra_status=$?
test_eq 2 "$home_extra_status" 'host HOME extra path is rejected before bwrap'
test_grep 'PI_EN_BWRAP_HOST_EXTRA_PATH entry under host HOME' "$tmpdir/home-extra-output"
if [ -e "$tmpdir/home-extra-args" ]; then
  test_fail 'host HOME extra path reached bwrap'
fi

nix_capture="$tmpdir/nix-bwrap-args"
runtime_tool_path="$(dirname "$(command -v realpath)")"
nix_host_extra_status=0
HOME="$host_home" \
  PATH="$tmpdir/actual-tools:$fakebin:$PATH" \
  PI_EN_RUNTIME_PATH="$runtime_tool_path" \
  PI_EN_TEST_BWRAP_ARGS="$nix_capture" \
  PI_EN_BWRAP_BASH="$tmpdir/host-bash" \
  PI_EN_BWRAP_ENV="$tmpdir/host-env" \
  PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
  PI_EN_BWRAP_HOST_EXTRA_PATH="$tmpdir/actual-tools" \
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
  scripts/pi-en-bwrap -- --help >"$tmpdir/nix-host-extra-output" 2>&1 || nix_host_extra_status=$?
test_eq 2 "$nix_host_extra_status" 'Nix runtime rejects host extra path before bwrap'
test_grep 'PI_EN_BWRAP_HOST_EXTRA_PATH is only supported in host runtime mode' "$tmpdir/nix-host-extra-output"
if [ -e "$nix_capture" ]; then
  test_fail 'Nix runtime PI_EN_BWRAP_HOST_EXTRA_PATH reached bwrap'
fi

nix_extra_status=0
HOME="$host_home" \
  PATH="$tmpdir/actual-tools:$fakebin:$PATH" \
  PI_EN_RUNTIME_PATH="$runtime_tool_path" \
  PI_EN_TEST_BWRAP_ARGS="$tmpdir/nix-unsafe-args" \
  PI_EN_BWRAP_BASH="$tmpdir/host-bash" \
  PI_EN_BWRAP_ENV="$tmpdir/host-env" \
  PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
  PI_EN_BWRAP_EXTRA_PATH="$tmpdir/actual-tools" \
  PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
  scripts/pi-en-bwrap -- --help >"$tmpdir/nix-extra-output" 2>&1 || nix_extra_status=$?
test_eq 2 "$nix_extra_status" 'Nix runtime rejects non-store PI_EN_BWRAP_EXTRA_PATH before bwrap'
test_grep 'unsafe PI_EN_BWRAP_EXTRA_PATH entry outside /nix/store' "$tmpdir/nix-extra-output"
if [ -e "$tmpdir/nix-unsafe-args" ]; then
  test_fail 'unsafe Nix PI_EN_BWRAP_EXTRA_PATH reached bwrap'
fi

echo 'conservative host runtime sandbox mounts fake-bwrap test passed'
