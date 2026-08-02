#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

fake_root="$(mktemp -d)"
trap 'rm -rf "$fake_root"' EXIT
mkdir -p "$fake_root/bin" "$fake_root/host-tools" "$fake_root/state"

cat >"$fake_root/fake-bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
: "${PI_EN_TEST_BWRAP_TRACE:?}"
printf '%s\n' "$@" >"$PI_EN_TEST_BWRAP_TRACE"
FAKE_BWRAP
chmod +x "$fake_root/fake-bwrap"
: >"$fake_root/host-tools/bash"
: >"$fake_root/host-tools/env"
chmod +x "$fake_root/host-tools/bash" "$fake_root/host-tools/env"

run_host_shell() {
  PI_EN_RUNTIME_PATH=/nix/store/fake/bin \
  PI_EN_BWRAP_BWRAP="$fake_root/fake-bwrap" \
  PI_EN_BWRAP_BASH="$fake_root/host-tools/bash" \
  PI_EN_BWRAP_ENV="$fake_root/host-tools/env" \
  PI_EN_BWRAP_STATE_DIR="$fake_root/state" \
  PI_EN_BWRAP_EPHEMERAL_HOME=1 \
  PI_EN_BWRAP_IMPORT_COMMON=0 \
  PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
  PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
  PI_EN_BWRAP_IMPORT_AUTH=0 \
  PI_EN_BWRAP_IMPORT_SESSIONS=0 \
  PI_EN_TEST_BWRAP_TRACE="$fake_root/host.trace" \
  ./pi-en-shell --runtime host -- -lc 'printf host-shell' >/dev/null
}

run_host_shell
if grep -qx -- '--tools' "$fake_root/host.trace" || grep -qx -- '--continue' "$fake_root/host.trace"; then
  echo "pi-en-shell --runtime host must delegate to pi-en-bwrap shell mode" >&2
  exit 1
fi
tail -n 2 "$fake_root/host.trace" | grep -Fx -- '-lc' >/dev/null
tail -n 1 "$fake_root/host.trace" | grep -Fx -- 'printf host-shell' >/dev/null

cat >"$fake_root/fake-pi-en-bwrap" <<'FAKE_PI_EN_BWRAP'
#!/usr/bin/env bash
: "${PI_EN_TEST_LAUNCHER_TRACE:?}"
printf 'pi-en-bwrap\n' >"$PI_EN_TEST_LAUNCHER_TRACE"
printf '%s\n' "$@" >>"$PI_EN_TEST_LAUNCHER_TRACE"
FAKE_PI_EN_BWRAP
chmod +x "$fake_root/fake-pi-en-bwrap"

PI_EN_PI_EN_BWRAP="$fake_root/fake-pi-en-bwrap" \
PI_EN_NIX_RUNTIME_READY=1 \
PI_EN_TEST_LAUNCHER_TRACE="$fake_root/wired-nix.trace" \
./pi-en-shell --runtime nix -- -lc 'printf nix-shell'
mapfile -t wired_nix <"$fake_root/wired-nix.trace"
[ "${wired_nix[0]}" = "pi-en-bwrap" ]
[ "${wired_nix[1]}" = "--shell" ]
[ "${wired_nix[2]}" = "--" ]
[ "${wired_nix[3]}" = "-lc" ]
[ "${wired_nix[4]}" = "printf nix-shell" ]

PATH="$fake_root:$PATH" \
PI_EN_PI_EN_BWRAP="$fake_root/fake-pi-en-bwrap" \
PI_EN_TEST_LAUNCHER_TRACE="$fake_root/auto.trace" \
./pi-en-shell --runtime auto -- -i
mapfile -t auto_trace <"$fake_root/auto.trace"
[ "${auto_trace[0]}" = "pi-en-bwrap" ]
[ "${auto_trace[1]}" = "--shell" ]
[ "${auto_trace[2]}" = "--" ]
[ "${auto_trace[3]}" = "-i" ]

cat >"$fake_root/bin/nix" <<'FAKE_NIX'
#!/usr/bin/env bash
: "${PI_EN_TEST_NIX_TRACE:?}"
printf 'PI_EN_RUNTIME=%s\n' "${PI_EN_RUNTIME-}" >"$PI_EN_TEST_NIX_TRACE"
printf '%s\n' "$@" >>"$PI_EN_TEST_NIX_TRACE"
FAKE_NIX
chmod +x "$fake_root/bin/nix"

env -u PI_EN_PI_START -u PI_EN_PI_EN_BWRAP \
PATH="$fake_root/bin:$PATH" \
PI_EN_RUNTIME=host \
PI_EN_TEST_NIX_TRACE="$fake_root/nix-recurse.trace" \
./pi-en-shell --runtime nix --flake "$fake_root/flake-ref" -- -lc 'printf recurse'
mapfile -t nix_recurse <"$fake_root/nix-recurse.trace"
[ "${nix_recurse[0]}" = "PI_EN_RUNTIME=nix" ]
[ "${nix_recurse[1]}" = "develop" ]
[ "${nix_recurse[2]}" = "$fake_root/flake-ref" ]
[ "${nix_recurse[3]}" = "-c" ]
[ "${nix_recurse[4]}" = "pi-en-shell" ]
[ "${nix_recurse[5]}" = "-lc" ]
[ "${nix_recurse[6]}" = "printf recurse" ]

REPO_ROOT="$repo_root" node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = process.env.REPO_ROOT;
const flake = readFileSync(join(root, "flake.nix"), "utf8");
const install = readFileSync(join(root, "scripts/pi-en-install-non-nix"), "utf8");
assert.match(flake, /pi-en-shell = piEnShell;/);
assert.match(flake, /program = "\$\{piEnShell\}\/bin\/pi-en-shell";/);
assert.match(flake, /command -v pi-en-shell >\/dev\/null/);
assert.match(install, /pi-en-shell/);
assert.match(install, /pi-en\|pi-en-shell\) install_wrapper "\$name" pi-en-launcher ;;/);
NODE
