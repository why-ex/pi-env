#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

flake=flake.nix

# mkPiShell derives extra package bin directories with Nix path construction and
# preserves a caller-provided PI_EN_BWRAP_EXTRA_PATH after project-declared tools.
test_grep 'extraPackagePath = pkgs.lib.makeBinPath (extraPackages ++ \[' "$flake"
test_grep 'export PI_EN_BWRAP_EXTRA_PATH="${extraPackagePath}:$PI_EN_BWRAP_EXTRA_PATH"' "$flake"

# pi-en-bwrap validates the explicit extra path input before bwrap starts.
bwrap_script="$repo_root/scripts/pi-en-bwrap"
test_grep 'PI_EN_BWRAP_EXTRA_PATH' "$bwrap_script"
test_grep 'unsafe PI_EN_BWRAP_EXTRA_PATH entry is not absolute' "$bwrap_script"
test_grep 'unsafe PI_EN_BWRAP_EXTRA_PATH entry is not an existing directory' "$bwrap_script"
test_grep 'unsafe PI_EN_BWRAP_EXTRA_PATH entry outside /nix/store' "$bwrap_script"
test_grep 'canonical_extra_path="$(realpath "$extra_path_entry")"' "$bwrap_script"
test_grep '/nix/store/\*' "$bwrap_script"

# Empty entries are ignored and the final sandbox PATH preserves pi-en runtime
# precedence before validated extras and compatibility command dirs.
test_grep '\[ -n "$extra_path_entry" \] ||' "$bwrap_script"
test_grep 'sandbox_path="${PI_EN_RUNTIME_PATH:-}"' "$bwrap_script"
test_grep 'sandbox_path="$(append_path_entry "$validated_extra_path" "$sandbox_path")"' "$bwrap_script"
test_grep 'sandbox_path="$(append_path_entry /usr/local/bin "$sandbox_path")"' "$bwrap_script"
test_grep '--setenv PATH "$sandbox_path"' "$bwrap_script"

# Documentation surfaces the safe workflow and advanced escape hatch.
test_grep 'Project-specific build and test tools' README.md
test_grep 'gnumake' README.md
test_grep 'canonical `/nix/store` directories' README.md
test_grep 'PI_EN_BWRAP_EXTRA_PATH=/nix/store/.../bin' README.md
test_grep 'does not infer tools from a repository' README.md

# The sandbox still relies on a read-only Nix store rather than binding host
# system command directories to provide project tools.
if grep -q -- '--ro-bind /usr/bin /usr/bin\|--ro-bind /bin /bin' "$flake"; then
  test_fail 'flake binds host /bin or /usr/bin for command exposure'
fi

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

# Run pi-en-bwrap directly with a fake bwrap boundary. This keeps the test
# executable in environments where the Nix CLI is unavailable while still
# exercising the launcher shell code.
script="$repo_root/scripts/pi-en-bwrap"
test_grep 'PI_EN_BWRAP_EXTRA_PATH' "$script"
test_grep 'exec "$pi_bwrap_bwrap"' "$script"

extra_bin=""
while IFS= read -r dir; do
  first_exe="$(find "$dir" -maxdepth 1 -type f -perm -111 2>/dev/null | head -n 1 || true)"
  if [ -n "$first_exe" ]; then
    extra_bin="$dir"
    break
  fi
done < <(find /nix/store -maxdepth 2 -type d -name bin 2>/dev/null)
[ -n "$extra_bin" ] || test_fail 'could not find an executable /nix/store bin directory for behavioral test'
extra_bin="$(realpath "$extra_bin")"
extra_cmd="$(find "$extra_bin" -maxdepth 1 -type f -perm -111 2>/dev/null | head -n 1)"
extra_cmd_name="$(basename "$extra_cmd")"

runtime_bin="$tmpdir/runtime/bin"
mkdir -p "$runtime_bin"

fakebin="$tmpdir/fakebin"
mkdir -p "$fakebin"
cat >"$fakebin/pi" <<'FAKE_PI'
#!/usr/bin/env bash
echo 'fake pi should not be executed by the fake bwrap harness' >&2
exit 99
FAKE_PI
chmod +x "$fakebin/pi"

cat >"$tmpdir/fake-bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
set -euo pipefail
sandbox_path=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      break
      ;;
    --setenv)
      [ "$#" -ge 3 ] || exit 64
      if [ "$2" = PATH ]; then
        sandbox_path="$3"
      fi
      shift 3
      ;;
    *)
      shift
      ;;
  esac
done
[ -n "$sandbox_path" ] || exit 65
printf '%s\n' "$sandbox_path" >"$PI_EN_TEST_CAPTURE"
PATH="$sandbox_path" command -v "$PI_EN_TEST_COMMAND" >>"$PI_EN_TEST_CAPTURE"
FAKE_BWRAP
chmod +x "$tmpdir/fake-bwrap"

capture="$tmpdir/capture"
(
  cd "$tmpdir"
  PATH="$fakebin:$PATH" \
    PI_EN_BWRAP_BWRAP="$tmpdir/fake-bwrap" \
    PI_EN_RUNTIME_PATH="$runtime_bin" \
    PI_EN_TEST_CAPTURE="$capture" \
    PI_EN_TEST_COMMAND="$extra_cmd_name" \
    PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
    PI_EN_BWRAP_IMPORT_COMMON=0 \
    PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
    PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
    PI_EN_BWRAP_IMPORT_AUTH=0 \
    PI_EN_BWRAP_IMPORT_SESSIONS=0 \
    PI_EN_BWRAP_EXTRA_PATH=":$extra_bin:" \
    "$script" -- --version
)

sandbox_path="$(sed -n '1p' "$capture")"
resolved_extra_cmd="$(sed -n '2p' "$capture")"
test_eq "$extra_bin/$extra_cmd_name" "$resolved_extra_cmd" 'validated extra PATH resolves a command from the Nix store package bin'
case "$sandbox_path" in
  "$extra_bin"|"$extra_bin":*)
    test_fail 'extra PATH was placed before the pi-en runtime path'
    ;;
  *":$extra_bin:"*)
    ;;
  *)
    test_fail "validated extra PATH missing from sandbox PATH: $sandbox_path"
    ;;
esac
case "$sandbox_path" in
  *::*)
    test_fail "empty PI_EN_BWRAP_EXTRA_PATH entries leaked into sandbox PATH: $sandbox_path"
    ;;
esac

unsafe_dir="$tmpdir/unsafe-bin"
mkdir -p "$unsafe_dir"
set +e
unsafe_output="$(
  PATH="$fakebin:$PATH" \
    PI_EN_BWRAP_BWRAP="$tmpdir/fake-bwrap" \
    PI_EN_RUNTIME_PATH="$runtime_bin" \
    PI_EN_TEST_CAPTURE="$tmpdir/unsafe-capture" \
    PI_EN_TEST_COMMAND="$extra_cmd_name" \
    PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
    PI_EN_BWRAP_IMPORT_COMMON=0 \
    PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
    PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
    PI_EN_BWRAP_IMPORT_AUTH=0 \
    PI_EN_BWRAP_IMPORT_SESSIONS=0 \
    PI_EN_BWRAP_EXTRA_PATH="$unsafe_dir" \
    "$script" -- --version 2>&1
)"
unsafe_status=$?
set -e
test_eq 2 "$unsafe_status" 'unsafe non-Nix-store extra PATH exits before bwrap'
printf '%s\n' "$unsafe_output" >"$tmpdir/unsafe-output"
test_grep 'unsafe PI_EN_BWRAP_EXTRA_PATH entry outside /nix/store' "$tmpdir/unsafe-output"
if [ -e "$tmpdir/unsafe-capture" ]; then
  test_fail 'unsafe PI_EN_BWRAP_EXTRA_PATH reached bwrap'
fi

set +e
relative_output="$(
  PATH="$fakebin:$PATH" \
    PI_EN_BWRAP_BWRAP="$tmpdir/fake-bwrap" \
    PI_EN_RUNTIME_PATH="$runtime_bin" \
    PI_EN_TEST_CAPTURE="$tmpdir/relative-capture" \
    PI_EN_TEST_COMMAND="$extra_cmd_name" \
    PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
    PI_EN_BWRAP_IMPORT_COMMON=0 \
    PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
    PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
    PI_EN_BWRAP_IMPORT_AUTH=0 \
    PI_EN_BWRAP_IMPORT_SESSIONS=0 \
    PI_EN_BWRAP_EXTRA_PATH=./bin \
    "$script" -- --version 2>&1
)"
relative_status=$?
set -e
test_eq 2 "$relative_status" 'relative extra PATH exits before bwrap'
printf '%s\n' "$relative_output" >"$tmpdir/relative-output"
test_grep 'unsafe PI_EN_BWRAP_EXTRA_PATH entry is not absolute' "$tmpdir/relative-output"
if [ -e "$tmpdir/relative-capture" ]; then
  test_fail 'relative PI_EN_BWRAP_EXTRA_PATH reached bwrap'
fi

echo "safe extra Nix tool PATH propagation tests passed"
