#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

[ ! -e scripts/pi-start ] || test_fail 'scripts/pi-start should be removed'
test_grep 'pi-en = piEn;' flake.nix
test_grep 'pi-en-shell = piEnShell;' flake.nix
if grep -Eq 'mkPiStart|PI_EN_PI_START|pi-start = piStart|program = "\$\{piStart\}/bin/pi-start"' flake.nix; then
  test_fail 'flake still exposes pi-start wiring'
fi
if awk '/^command_names=\(/ { in_commands=1; next } in_commands && /^\)/ { in_commands=0 } in_commands { print }' scripts/pi-en-install-non-nix | grep -Fx '  pi-start' >/dev/null 2>&1 || \
    grep -q 'PI_EN_PI_START' scripts/pi-en-install-non-nix; then
  test_fail 'non-Nix installer still installs pi-start'
fi

install_prefix="$tmpdir/install-prefix"
mkdir -p "$install_prefix/bin"
printf 'stale legacy wrapper\n' >"$install_prefix/bin/pi-start"
./scripts/pi-en-install-non-nix --prefix "$install_prefix" >/dev/null
[ ! -e "$install_prefix/bin/pi-start" ] || test_fail 'non-Nix reinstall left stale pi-start wrapper'

fake_bwrap="$tmpdir/pi-en-bwrap"
cat >"$fake_bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PI_EN_TEST_CAPTURE"
FAKE_BWRAP
chmod +x "$fake_bwrap"

capture="$tmpdir/default.args"
PI_EN_RUNTIME=auto \
PI_EN_PI_EN_BWRAP="$fake_bwrap" \
PI_EN_TEST_CAPTURE="$capture" \
./pi-en --model test/model 'hello world'

test_grep '^--tools$' "$capture"
test_grep '^read,bash,edit,write,grep,find,ls$' "$capture"
test_grep '^--continue$' "$capture"
test_grep '^-e$' "$capture"
test_grep "^$repo_root/role-manager$" "$capture"
test_grep '^--model$' "$capture"
test_grep '^test/model$' "$capture"
test_grep '^hello world$' "$capture"

custom_capture="$tmpdir/custom.args"
PI_EN_RUNTIME=auto \
PI_EN_PI_EN_BWRAP="$fake_bwrap" \
PI_EN_BWRAP_DEFAULT_TOOLS='bash,grep' \
PI_EN_ROLE_MANAGER_AUTO=0 \
PI_EN_TEST_CAPTURE="$custom_capture" \
./pi-en 'prompt'
test_grep '^bash,grep$' "$custom_capture"
if grep -Fx -- '-e' "$custom_capture" >/dev/null 2>&1; then
  test_fail 'PI_EN_ROLE_MANAGER_AUTO=0 should disable role-manager injection'
fi

raw_capture="$tmpdir/raw.args"
PI_EN_RUNTIME=auto \
PI_EN_PI_EN_BWRAP="$fake_bwrap" \
PI_EN_TEST_CAPTURE="$raw_capture" \
./pi-en --raw -- --model raw/model prompt
if grep -Fx -- '--tools' "$raw_capture" >/dev/null 2>&1 || grep -Fx -- '--continue' "$raw_capture" >/dev/null 2>&1; then
  test_fail 'raw mode should not inject default startup arguments'
fi
test_grep '^--$' "$raw_capture"
test_grep '^--model$' "$raw_capture"
test_grep '^raw/model$' "$raw_capture"

shell_capture="$tmpdir/shell.args"
PI_EN_RUNTIME=auto \
PI_EN_PI_EN_BWRAP="$fake_bwrap" \
PI_EN_TEST_CAPTURE="$shell_capture" \
./pi-en-shell -- -lc true
if grep -Fx -- '--tools' "$shell_capture" >/dev/null 2>&1 || grep -Fx -- '--continue' "$shell_capture" >/dev/null 2>&1; then
  test_fail 'pi-en-shell should delegate to shell mode without startup defaults'
fi
test_grep '^--shell$' "$shell_capture"
test_grep '^--$' "$shell_capture"
test_grep '^-lc$' "$shell_capture"

echo 'PIEN-ISS-20260710-184849-001 pi-start removal tests passed'
