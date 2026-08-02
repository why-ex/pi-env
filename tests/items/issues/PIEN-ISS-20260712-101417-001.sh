#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
. "$repo_root/tests/lib/test-helpers.sh"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

install_bin="$tmpdir/install/bin"
fakebin="$tmpdir/fakebin"
project="$tmpdir/project"
no_flake_project="$tmpdir/no-flake-project"
mkdir -p "$install_bin" "$fakebin" "$project" "$no_flake_project"
printf '{ outputs = { self }: {}; }\n' >"$project/flake.nix"
cp "$repo_root/scripts/pien" "$install_bin/pien"
cp "$repo_root/scripts/pi-en-launcher" "$install_bin/pi-en"
chmod +x "$install_bin/pien" "$install_bin/pi-en"

cat >"$fakebin/nix" <<'FAKE_NIX'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'env.PI_EN_RUNTIME=%s\n' "${PI_EN_RUNTIME:-}"
  printf 'env.PI_EN_NIX_RUNTIME_READY=%s\n' "${PI_EN_NIX_RUNTIME_READY:-}"
  printf 'env.PI_EN_NIX_IGNORED_BWRAP=%s\n' "${PI_EN_NIX_IGNORED_BWRAP:-}"
  printf 'args:\n'
  for arg in "$@"; do
    printf '%s\n' "$arg"
  done
} >"$PI_EN_TEST_NIX_LOG"
if [ "${PI_EN_TEST_NIX_EXEC:-0}" = "1" ]; then
  [ "$1" = develop ] || exit 64
  shift 2
  [ "$1" = -c ] || exit 64
  shift
  if [ -n "${PI_EN_TEST_NIX_PREPEND_PATH:-}" ]; then
    export PATH="$PI_EN_TEST_NIX_PREPEND_PATH:$PATH"
  fi
  if [ -n "${PI_EN_TEST_NIX_PROJECT_BWRAP:-}" ]; then
    export PI_EN_NIX_PROJECT_BWRAP="$PI_EN_TEST_NIX_PROJECT_BWRAP"
  fi
  exec "$@"
fi
exit 0
FAKE_NIX
chmod +x "$fakebin/nix"

fake_bwrap="$tmpdir/fake-pi-en-bwrap"
cat >"$fake_bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'bwrap args:\n'
  for arg in "$@"; do
    printf '%s\n' "$arg"
  done
} >"$PI_EN_TEST_BWRAP_LOG"
exit 0
FAKE_BWRAP
chmod +x "$fake_bwrap"
cp "$fake_bwrap" "$install_bin/pi-en-bwrap"

nix_log="$tmpdir/non-nix-installed-nix.log"
(
  cd "$project"
  env -u PI_EN_RUNTIME -u PI_EN_FLAKE -u PI_EN_PI_EN_BWRAP -u PI_EN_NIX_RUNTIME_READY \
    PATH="$fakebin:$PATH" PI_EN_TEST_NIX_LOG="$nix_log" \
    "$install_bin/pien" --runtime nix --raw -- --help
)
test_file_exists "$nix_log"
printf '%s\n' \
  'env.PI_EN_RUNTIME=nix' \
  'env.PI_EN_NIX_RUNTIME_READY=1' \
  'env.PI_EN_NIX_IGNORED_BWRAP=' \
  'args:' \
  develop "$project" -c pi-en --raw -- --help >"$tmpdir/expected-nix.log"
test_eq "$(cat "$tmpdir/expected-nix.log")" "$(cat "$nix_log")" \
  'non-Nix installed pien --runtime nix did not enter the project flake'

profile_log="$tmpdir/profile-installed-nix.log"
(
  cd "$project"
  env -u PI_EN_RUNTIME -u PI_EN_FLAKE -u PI_EN_NIX_RUNTIME_READY \
    PATH="$fakebin:$PATH" PI_EN_PI_EN_BWRAP="$fake_bwrap" \
    PI_EN_TEST_NIX_LOG="$profile_log" \
    "$install_bin/pien" --runtime nix --raw -- --version
)
test_file_exists "$profile_log"
test_grep '^develop$' "$profile_log"
test_grep "^$project$" "$profile_log"
if [ -e "${PI_EN_TEST_BWRAP_LOG:-$tmpdir/unset}" ]; then
  test_fail 'profile-style wired launcher bypassed project nix develop before recursion marker'
fi

tmp_project_runtime="$tmpdir/project-runtime/bin"
mkdir -p "$tmp_project_runtime"
project_bwrap="$tmp_project_runtime/pi-en-bwrap"
cat >"$project_bwrap" <<'PROJECT_BWRAP'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'project bwrap=%s\n' "$0"
  printf 'stale bwrap=%s\n' "${PI_EN_PI_EN_BWRAP:-}"
  printf 'ignored bwrap=%s\n' "${PI_EN_NIX_IGNORED_BWRAP:-}"
  printf 'args:\n'
  for arg in "$@"; do
    printf '%s\n' "$arg"
  done
} >"$PI_EN_TEST_PROJECT_BWRAP_LOG"
exit 0
PROJECT_BWRAP
chmod +x "$project_bwrap"
second_stage_log="$tmpdir/profile-second-stage-nix.log"
project_bwrap_log="$tmpdir/project-bwrap.log"
(
  cd "$project"
  env -u PI_EN_RUNTIME -u PI_EN_FLAKE -u PI_EN_NIX_RUNTIME_READY -u PI_EN_NIX_IGNORED_BWRAP \
    PATH="$fakebin:$tmp_project_runtime:$install_bin:$PATH" PI_EN_PI_EN_BWRAP="$fake_bwrap" \
    PI_EN_TEST_NIX_LOG="$second_stage_log" PI_EN_TEST_NIX_EXEC=1 \
    PI_EN_TEST_PROJECT_BWRAP_LOG="$project_bwrap_log" \
    "$install_bin/pien" --runtime nix --raw -- --version
)
test_file_exists "$project_bwrap_log"
test_grep "^project bwrap=$project_bwrap$" "$project_bwrap_log"
test_grep "^stale bwrap=$fake_bwrap$" "$project_bwrap_log"
test_grep "^ignored bwrap=$fake_bwrap$" "$project_bwrap_log"
test_grep '^--version$' "$project_bwrap_log"
if [ -e "${PI_EN_TEST_BWRAP_LOG:-$tmpdir/unset}" ]; then
  test_fail 'second-stage nix runtime reused stale installed/profile pi-en-bwrap'
fi

same_store_bwrap_log="$tmpdir/same-store-project-bwrap.log"
(
  cd "$project"
  env -u PI_EN_RUNTIME -u PI_EN_FLAKE -u PI_EN_NIX_RUNTIME_READY -u PI_EN_NIX_IGNORED_BWRAP \
    PATH="$fakebin:$install_bin:$PATH" PI_EN_PI_EN_BWRAP="$install_bin/pi-en-bwrap" \
    PI_EN_TEST_NIX_LOG="$tmpdir/same-store-nix.log" PI_EN_TEST_NIX_EXEC=1 \
    PI_EN_TEST_NIX_PROJECT_BWRAP="$install_bin/pi-en-bwrap" \
    PI_EN_TEST_BWRAP_LOG="$same_store_bwrap_log" \
    "$install_bin/pien" --runtime nix --raw -- --version
)
test_file_exists "$same_store_bwrap_log"
test_grep '^--version$' "$same_store_bwrap_log"

stale_profile_status=0
stale_profile_bwrap_log="$tmpdir/stale-profile-bwrap.log"
(
  cd "$project"
  env -u PI_EN_RUNTIME -u PI_EN_FLAKE -u PI_EN_NIX_RUNTIME_READY -u PI_EN_NIX_IGNORED_BWRAP \
    PATH="$fakebin:$install_bin:$PATH" PI_EN_PI_EN_BWRAP="$install_bin/pi-en-bwrap" \
    PI_EN_TEST_NIX_LOG="$tmpdir/stale-profile-nix.log" PI_EN_TEST_NIX_EXEC=1 \
    PI_EN_TEST_BWRAP_LOG="$stale_profile_bwrap_log" \
    "$install_bin/pien" --runtime nix --raw -- --version >"$tmpdir/stale-profile.out" 2>&1
) || stale_profile_status=$?
test_eq 127 "$stale_profile_status" \
  'second-stage nix runtime without project pi-en-bwrap must fail instead of reusing installed/profile runtime'
test_grep 'project pi-en-bwrap was not found' "$tmpdir/stale-profile.out"
if [ -e "$stale_profile_bwrap_log" ]; then
  test_fail 'second-stage nix runtime executed stale installed/profile pi-en-bwrap from PATH'
fi

missing_status=0
(
  cd "$no_flake_project"
  env -u PI_EN_RUNTIME -u PI_EN_FLAKE -u PI_EN_PI_EN_BWRAP -u PI_EN_NIX_RUNTIME_READY \
    PATH="$fakebin:$PATH" PI_EN_TEST_NIX_LOG="$tmpdir/missing-nix.log" \
    "$install_bin/pien" --runtime nix --raw -- --help >"$tmpdir/missing.out" 2>&1
) || missing_status=$?
test_eq 2 "$missing_status" 'missing project flake exits non-zero before nix develop'
test_grep "requires a target project flake" "$tmpdir/missing.out"
test_grep "pass --flake REF" "$tmpdir/missing.out"
if [ -e "$tmpdir/missing-nix.log" ]; then
  test_fail 'missing project flake still invoked nix'
fi

direct_checkout_log="$tmpdir/direct-checkout-nix.log"
(
  cd "$no_flake_project"
  env -u PI_EN_RUNTIME -u PI_EN_FLAKE -u PI_EN_PI_EN_BWRAP -u PI_EN_NIX_RUNTIME_READY \
    PATH="$fakebin:$PATH" PI_EN_TEST_NIX_LOG="$direct_checkout_log" \
    "$repo_root/pien" --runtime nix --raw -- --help
)
test_file_exists "$direct_checkout_log"
test_grep "^$repo_root$" "$direct_checkout_log"

explicit_cli_log="$tmpdir/explicit-cli-flake.log"
(
  cd "$no_flake_project"
  env -u PI_EN_RUNTIME -u PI_EN_FLAKE -u PI_EN_PI_EN_BWRAP -u PI_EN_NIX_RUNTIME_READY \
    PATH="$fakebin:$PATH" PI_EN_TEST_NIX_LOG="$explicit_cli_log" \
    "$install_bin/pien" --runtime nix --flake custom-ref --raw -- --help
)
test_grep '^custom-ref$' "$explicit_cli_log"

explicit_env_log="$tmpdir/explicit-env-flake.log"
(
  cd "$no_flake_project"
  env -u PI_EN_RUNTIME -u PI_EN_PI_EN_BWRAP -u PI_EN_NIX_RUNTIME_READY \
    PATH="$fakebin:$PATH" PI_EN_FLAKE=env-ref PI_EN_TEST_NIX_LOG="$explicit_env_log" \
    "$install_bin/pien" --runtime nix --raw -- --help
)
test_grep '^env-ref$' "$explicit_env_log"

recursion_bwrap_log="$tmpdir/recursion-bwrap.log"
(
  cd "$project"
  env PI_EN_RUNTIME=nix PI_EN_NIX_RUNTIME_READY=1 PI_EN_PI_EN_BWRAP="$fake_bwrap" \
    PI_EN_TEST_BWRAP_LOG="$recursion_bwrap_log" PI_EN_TEST_NIX_LOG="$tmpdir/recursion-nix.log" \
    PATH="$fakebin:$PATH" "$install_bin/pien" --runtime nix --raw -- --help
)
test_file_exists "$recursion_bwrap_log"
test_grep '^--$' "$recursion_bwrap_log"
if [ -e "$tmpdir/recursion-nix.log" ]; then
  test_fail 'recursion-marked nix runtime re-entered nix develop'
fi

host_bwrap_log="$tmpdir/host-bwrap.log"
(
  cd "$project"
  env PI_EN_TEST_BWRAP_LOG="$host_bwrap_log" \
    "$install_bin/pien" --runtime host --raw -- --help
)
test_file_exists "$host_bwrap_log"

printf 'PIEN-ISS-20260712-101417-001 tests passed\n'
