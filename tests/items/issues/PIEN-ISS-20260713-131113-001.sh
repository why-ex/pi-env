#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

script=scripts/pi-en-bwrap
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
fakebin="$tmpdir/bin"
mkdir -p "$fakebin" "$tmpdir/state" "$tmpdir/project"

cat >"$fakebin/pi" <<'FAKE_PI'
#!/usr/bin/env bash
echo 'fake pi should only run inside fake bwrap' >&2
exit 99
FAKE_PI
chmod +x "$fakebin/pi"

cat >"$fakebin/bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
set -euo pipefail
: "${PI_EN_TEST_BWRAP_CAPTURE:?missing capture path}"
printf '%s\n' "$@" >"$PI_EN_TEST_BWRAP_CAPTURE"
FAKE_BWRAP
chmod +x "$fakebin/bwrap"

run_bwrap() {
  local capture="$1"
  shift
  env \
    PATH="$fakebin:$PATH" \
    PI_EN_TEST_BWRAP_CAPTURE="$capture" \
    PI_EN_RUNTIME_PATH=/usr/bin \
    PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
    PI_EN_BWRAP_BASH="$(command -v bash)" \
    PI_EN_BWRAP_ENV="$(command -v env)" \
    PI_EN_BWRAP_PROJECT_ROOT="$tmpdir/project" \
    PI_EN_BWRAP_STATE_DIR="$tmpdir/state" \
    PI_EN_BWRAP_IMPORT_COMMON=0 \
    PI_EN_BWRAP_IMPORT_AUTH=0 \
    PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
    PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
    PI_EN_BWRAP_IMPORT_SESSIONS=0 \
    PI_EN_COORD_REMOTE= \
    PI_EN_COORD_DIR= \
    bash "$script" "$@"
}

contains_arg() {
  local arg="$1" capture="$2"
  grep -Fx -- "$arg" "$capture" >/dev/null
}

# Default shell mode is interactive; without a usable terminal it fails before
# entering bwrap and emits a project-owned diagnostic.
non_tty_capture="$tmpdir/non-tty-default.capture"
non_tty_err="$tmpdir/non-tty-default.err"
set +e
run_bwrap "$non_tty_capture" --shell >"$tmpdir/non-tty-default.out" 2>"$non_tty_err"
status=$?
set -e
test_eq 2 "$status" 'non-TTY default shell should be a usage error'
[ ! -e "$non_tty_capture" ] || test_fail 'non-TTY default shell should not invoke bwrap'
test_grep 'interactive shell mode requires both stdin and stdout to be TTYs' "$non_tty_err"
test_grep "-- -lc 'pwd'" "$non_tty_err"

# Explicit non-interactive Bash commands remain usable in non-TTY runners.
noninteractive_capture="$tmpdir/noninteractive.capture"
run_bwrap "$noninteractive_capture" --shell -- -lc 'pwd'
contains_arg --new-session "$noninteractive_capture" \
  || test_fail 'non-interactive shell payload should keep the standard new-session isolation'
contains_arg -lc "$noninteractive_capture" \
  || test_fail 'explicit non-interactive bash args should reach bwrap payload'
contains_arg pwd "$noninteractive_capture" \
  || test_fail 'explicit non-interactive command should reach bwrap payload'

# Explicit interactive requests also require a terminal.
interactive_err="$tmpdir/explicit-interactive.err"
set +e
run_bwrap "$tmpdir/explicit-interactive.capture" --shell -- -i -c true >"$tmpdir/explicit-interactive.out" 2>"$interactive_err"
status=$?
set -e
test_eq 2 "$status" 'explicit -i shell should require a TTY'
test_grep 'interactive shell mode requires both stdin and stdout to be TTYs' "$interactive_err"

# Normal Pi-agent launches keep --new-session.
normal_capture="$tmpdir/normal.capture"
run_bwrap "$normal_capture" -- --help
contains_arg --new-session "$normal_capture" \
  || test_fail 'normal Pi launch should keep --new-session'

# When a PTY helper is available, prove the default interactive shell bwrap argv
# omits --new-session and still defaults Bash to a login shell.
if command -v script >/dev/null 2>&1; then
  pty_capture="$tmpdir/pty-shell.capture"
  pty_log="$tmpdir/pty-shell.log"
  cmd="cd '$repo_root' && PI_EN_TEST_BWRAP_CAPTURE='$pty_capture' PATH='$fakebin':\$PATH PI_EN_RUNTIME_PATH=/usr/bin PI_EN_BWRAP_BWRAP='$fakebin/bwrap' PI_EN_BWRAP_BASH='$(command -v bash)' PI_EN_BWRAP_ENV='$(command -v env)' PI_EN_BWRAP_PROJECT_ROOT='$tmpdir/project' PI_EN_BWRAP_STATE_DIR='$tmpdir/state' PI_EN_BWRAP_IMPORT_COMMON=0 PI_EN_BWRAP_IMPORT_AUTH=0 PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 PI_EN_BWRAP_IMPORT_EXTENSIONS=0 PI_EN_BWRAP_IMPORT_SESSIONS=0 PI_EN_COORD_REMOTE= PI_EN_COORD_DIR= bash '$script' --shell"
  script -qec "$cmd" "$pty_log" >/dev/null
  [ -f "$pty_capture" ] || test_fail 'PTY-backed shell should invoke fake bwrap'
  if contains_arg --new-session "$pty_capture"; then
    test_fail 'interactive shell payload should omit --new-session'
  fi
  contains_arg -l "$pty_capture" \
    || test_fail 'default interactive shell should pass bash -l'
else
  test_note 'script(1) unavailable; skipped PTY-backed interactive shell argv check'
fi

test_note 'TTY-aware pien shell behavior is covered'
