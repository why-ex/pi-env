#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
fakebin="$tmpdir/bin"
project="$tmpdir/project"
state="$tmpdir/state"
mkdir -p "$fakebin" "$project" "$state/agent/bin"

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
printf '#!/bin/sh\n' >"$fakebin/host-bash"
printf '#!/bin/sh\n' >"$fakebin/host-env"
chmod +x "$fakebin/host-bash" "$fakebin/host-env"

rg_path="$(command -v rg)"
fd_path="$(command -v fd)"
rg_dir="$(dirname "$rg_path")"
fd_dir="$(dirname "$fd_path")"
case "$(realpath -e "$rg_path")" in /nix/store/*) ;; *) test_fail 'rg must resolve from /nix/store for this test' ;; esac
case "$(realpath -e "$fd_path")" in /nix/store/*) ;; *) test_fail 'fd must resolve from /nix/store for this test' ;; esac

printf 'stale rg\n' >"$state/agent/bin/rg"
printf 'stale fd\n' >"$state/agent/bin/fd"
chmod +x "$state/agent/bin/rg" "$state/agent/bin/fd"

capture="$tmpdir/bwrap.args"
PATH="$fakebin:$PATH" \
PI_EN_TEST_BWRAP_CAPTURE="$capture" \
PI_EN_RUNTIME_PATH="$rg_dir" \
PI_EN_BWRAP_EXTRA_PATH="$fd_dir" \
PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS='rg fd' \
PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
PI_EN_BWRAP_BASH="$(command -v bash)" \
PI_EN_BWRAP_ENV="$(command -v env)" \
PI_EN_BWRAP_PROJECT_ROOT="$project" \
PI_EN_BWRAP_STATE_DIR="$state" \
PI_EN_BWRAP_IMPORT_COMMON=0 \
PI_EN_BWRAP_IMPORT_AUTH=0 \
PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
PI_EN_BWRAP_IMPORT_SESSIONS=0 \
PI_EN_COORD_REMOTE= \
PI_EN_COORD_DIR= \
bash scripts/pi-en-bwrap -- --help

shadow="$state/agent-bin-shadow"
test_eq "$(realpath -e "$rg_path")" "$(realpath -e "$shadow/rg")" \
  'shadowed rg should target the Nix runtime path'
test_eq "$(realpath -e "$fd_path")" "$(realpath -e "$shadow/fd")" \
  'shadowed fd should target the validated extra Nix path'

test_grep '^--ro-bind$' "$capture"
test_grep "^$shadow$" "$capture"
test_grep '^/home/pi/.pi/agent/bin$' "$capture"
awk -v agent="$state/agent" -v shadow="$shadow" '
  $0 == agent { agent_line = NR }
  $0 == shadow { shadow_line = NR }
  END { exit !(agent_line > 0 && shadow_line > agent_line) }
' "$capture" || test_fail 'shadow bind must occur after the agent state bind'

disabled_capture="$tmpdir/disabled.args"
PATH="$fakebin:$PATH" \
PI_EN_TEST_BWRAP_CAPTURE="$disabled_capture" \
PI_EN_RUNTIME_PATH="$rg_dir:$fd_dir" \
PI_EN_BWRAP_AGENT_BIN_SHADOW=0 \
PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS='rg fd' \
PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
PI_EN_BWRAP_BASH="$(command -v bash)" \
PI_EN_BWRAP_ENV="$(command -v env)" \
PI_EN_BWRAP_PROJECT_ROOT="$project" \
PI_EN_BWRAP_STATE_DIR="$state" \
PI_EN_BWRAP_IMPORT_COMMON=0 \
PI_EN_BWRAP_IMPORT_AUTH=0 \
PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
PI_EN_BWRAP_IMPORT_SESSIONS=0 \
PI_EN_COORD_REMOTE= \
PI_EN_COORD_DIR= \
bash scripts/pi-en-bwrap -- --help
if grep -Fx -- '/home/pi/.pi/agent/bin' "$disabled_capture" >/dev/null; then
  test_fail 'agent-bin shadow should be disabled by PI_EN_BWRAP_AGENT_BIN_SHADOW=0'
fi

host_capture="$tmpdir/host.args"
PATH="$fakebin:$PATH" \
PI_EN_TEST_BWRAP_CAPTURE="$host_capture" \
PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
PI_EN_BWRAP_BASH="$fakebin/host-bash" \
PI_EN_BWRAP_ENV="$fakebin/host-env" \
PI_EN_BWRAP_PROJECT_ROOT="$project" \
PI_EN_BWRAP_STATE_DIR="$state" \
PI_EN_BWRAP_IMPORT_COMMON=0 \
PI_EN_BWRAP_IMPORT_AUTH=0 \
PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
PI_EN_BWRAP_IMPORT_SESSIONS=0 \
PI_EN_COORD_REMOTE= \
PI_EN_COORD_DIR= \
bash scripts/pi-en-bwrap --shell -- -lc true
if grep -Fx -- '/home/pi/.pi/agent/bin' "$host_capture" >/dev/null; then
  test_fail 'host runtime should not shadow agent bin by default'
fi

invalid_err="$tmpdir/invalid.err"
set +e
PATH="$fakebin:$PATH" \
PI_EN_RUNTIME_PATH="$rg_dir" \
PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS='../rg' \
PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
PI_EN_BWRAP_BASH="$(command -v bash)" \
PI_EN_BWRAP_ENV="$(command -v env)" \
PI_EN_BWRAP_PROJECT_ROOT="$project" \
PI_EN_BWRAP_STATE_DIR="$state" \
PI_EN_BWRAP_IMPORT_COMMON=0 \
PI_EN_BWRAP_IMPORT_AUTH=0 \
PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
PI_EN_BWRAP_IMPORT_SESSIONS=0 \
PI_EN_COORD_REMOTE= \
PI_EN_COORD_DIR= \
bash scripts/pi-en-bwrap -- --help >"$tmpdir/invalid.out" 2>"$invalid_err"
status=$?
set -e
test_eq 2 "$status" 'invalid shadow override should fail usage validation'
test_grep 'invalid PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS entry' "$invalid_err"

printf 'PIEN-ISS-20260815-075447-001 tests passed\n'
