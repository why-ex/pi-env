#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

script="$repo_root/scripts/pi-en-bwrap"
tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

find_nix_tool() {
  local name="$1" path
  path="$(find /nix/store -maxdepth 3 -type f -perm -111 -name "$name" 2>/dev/null | head -n 1 || true)"
  [ -n "$path" ] || test_fail "could not find executable $name in /nix/store"
  realpath "$path"
}

rg_path="$(find_nix_tool rg)"
fd_path="$(find_nix_tool fd)"
rg_dir="$(dirname "$rg_path")"
fd_dir="$(dirname "$fd_path")"

fakebin="$tmpdir/fakebin"
unsafe_bin="$tmpdir/unsafe-bin"
mkdir -p "$fakebin" "$unsafe_bin"
cat >"$unsafe_bin/rg" <<'UNSAFE_RG'
#!/usr/bin/env bash
echo unsafe rg
UNSAFE_RG
cat >"$unsafe_bin/fd" <<'UNSAFE_FD'
#!/usr/bin/env bash
echo unsafe fd
UNSAFE_FD
chmod +x "$unsafe_bin/rg" "$unsafe_bin/fd"

cat >"$tmpdir/fake-bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
set -euo pipefail
capture="${PI_EN_TEST_CAPTURE:?}"
: >"$capture"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      printf 'CMD %s\n' "$*" >>"$capture"
      exit 0
      ;;
    --bind|--ro-bind|--ro-bind-try)
      [ "$#" -ge 3 ] || exit 64
      printf '%s %s %s\n' "$1" "$2" "$3" >>"$capture"
      shift 3
      ;;
    --symlink)
      [ "$#" -ge 3 ] || exit 64
      printf '%s %s %s\n' "$1" "$2" "$3" >>"$capture"
      shift 3
      ;;
    --setenv)
      [ "$#" -ge 3 ] || exit 64
      printf '%s %s %s\n' "$1" "$2" "$3" >>"$capture"
      shift 3
      ;;
    --chdir|--proc|--dev|--tmpfs|--dir)
      [ "$#" -ge 2 ] || exit 64
      printf '%s %s\n' "$1" "$2" >>"$capture"
      shift 2
      ;;
    *)
      printf '%s\n' "$1" >>"$capture"
      shift
      ;;
  esac
done
FAKE_BWRAP
chmod +x "$tmpdir/fake-bwrap"

run_bwrap_capture() {
  local name="$1"
  shift
  local state_dir="$tmpdir/state-$name"
  local capture="$tmpdir/capture-$name"
  mkdir -p "$state_dir/agent/bin"
  cat >"$state_dir/agent/bin/rg" <<'STALE_RG'
#!/usr/bin/env bash
echo stale rg
STALE_RG
  cat >"$state_dir/agent/bin/fd" <<'STALE_FD'
#!/usr/bin/env bash
echo stale fd
STALE_FD
  chmod +x "$state_dir/agent/bin/rg" "$state_dir/agent/bin/fd"

  (
    cd "$tmpdir"
    env \
      PATH="$unsafe_bin:$PATH" \
      PI_EN_BWRAP_BWRAP="$tmpdir/fake-bwrap" \
      PI_EN_RUNTIME_PATH="$rg_dir:$fd_dir:$unsafe_bin:/usr/bin:/bin:$tmpdir" \
      PI_EN_BWRAP_STATE_DIR="$state_dir" \
      PI_EN_TEST_CAPTURE="$capture" \
      PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
      PI_EN_BWRAP_IMPORT_COMMON=0 \
      PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
      PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
      PI_EN_BWRAP_IMPORT_AUTH=0 \
      PI_EN_BWRAP_IMPORT_SESSIONS=0 \
      "$@" \
      "$script" --shell -- -lc true
  )
  printf '%s\n' "$state_dir" >"$tmpdir/state-path-$name"
  printf '%s\n' "$capture"
}

capture_default="$(run_bwrap_capture default)"
state_default="$(cat "$tmpdir/state-path-default")"
shadow_default="$state_default/agent-bin-shadow"

test_grep '^--bind .*/agent /home/pi/.pi/agent$' "$capture_default"
test_grep "^--ro-bind $shadow_default /home/pi/.pi/agent/bin$" "$capture_default"
agent_bind_line="$(grep -n '^--bind .*/agent /home/pi/.pi/agent$' "$capture_default" | tail -n 1 | cut -d: -f1)"
shadow_bind_line="$(grep -n "^--ro-bind $shadow_default /home/pi/.pi/agent/bin$" "$capture_default" | tail -n 1 | cut -d: -f1)"
[ "$agent_bind_line" -lt "$shadow_bind_line" ] || test_fail 'agent-bin shadow bind did not occur after the persisted agent bind'

for tool in rg fd; do
  target="$(readlink "$shadow_default/$tool")"
  case "$target" in
    /nix/store/*) ;;
    *) test_fail "shadow $tool did not target a canonical /nix/store path: $target" ;;
  esac
  [ -x "$target" ] || test_fail "shadow $tool target is not executable: $target"
  case "$target" in
    "$unsafe_bin"/*|"$state_default"/agent/bin/*|/usr/bin/*|/bin/*|"$tmpdir"/*|"$repo_root"/*)
      test_fail "shadow $tool used an unsafe or stale path: $target"
      ;;
  esac
done

if grep -q 'stale rg\|stale fd' "$shadow_default/rg" "$shadow_default/fd" 2>/dev/null; then
  test_fail 'stale persisted agent bin content determined shadowed tool resolution'
fi

capture_disabled="$(run_bwrap_capture disabled PI_EN_BWRAP_AGENT_BIN_SHADOW=0)"
state_disabled="$(cat "$tmpdir/state-path-disabled")"
if grep -q '^--ro-bind .* /home/pi/.pi/agent/bin$' "$capture_disabled"; then
  test_fail 'PI_EN_BWRAP_AGENT_BIN_SHADOW=0 still bound a shadow agent bin'
fi
test_grep "^--bind $state_disabled/agent /home/pi/.pi/agent$" "$capture_disabled"
test_file_exists "$state_disabled/agent/bin/rg"

capture_custom="$(run_bwrap_capture custom PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS='rg')"
state_custom="$(cat "$tmpdir/state-path-custom")"
shadow_custom="$state_custom/agent-bin-shadow"
test_grep "^--ro-bind $shadow_custom /home/pi/.pi/agent/bin$" "$capture_custom"
test_file_exists "$shadow_custom/rg"
[ ! -e "$shadow_custom/fd" ] || test_fail 'custom shadow tool list unexpectedly generated fd'

capture_empty="$(run_bwrap_capture empty PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS='   ')"
state_empty="$(cat "$tmpdir/state-path-empty")"
if grep -q '^--ro-bind .* /home/pi/.pi/agent/bin$' "$capture_empty"; then
  test_fail 'whitespace-only custom shadow tool list unexpectedly bound a shadow dir'
fi
if find "$state_empty/agent-bin-shadow" -mindepth 1 -print -quit | grep -q .; then
  test_fail 'whitespace-only custom shadow tool list generated shadow entries'
fi

capture_unsafe="$(run_bwrap_capture unsafe PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS='git')"
state_unsafe="$(cat "$tmpdir/state-path-unsafe")"
if [ -e "$state_unsafe/agent-bin-shadow/git" ]; then
  target="$(readlink "$state_unsafe/agent-bin-shadow/git" || true)"
  case "$target" in
    /nix/store/*) ;;
    *) test_fail "custom shadow tool resolved from an unsafe host path: $target" ;;
  esac
fi

echo 'Nix agent-bin shadowing tests passed'
