#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
updater="$repo_root/scripts/pi-en-update-nix-flake-input"
pien="$repo_root/pien"
workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

assert_contains() {
  local path="$1" text="$2"
  grep -Fq -- "$text" "$path" || {
    echo "missing '$text' in $path" >&2
    [ -f "$path" ] && cat "$path" >&2
    exit 1
  }
}

assert_not_contains() {
  local path="$1" text="$2"
  if grep -Fq -- "$text" "$path"; then
    echo "unexpected '$text' in $path" >&2
    cat "$path" >&2
    exit 1
  fi
}

assert_unchanged() {
  local before="$1" path="$2" before_text current_text
  before_text="$(<"$before")"
  current_text="$(<"$path")"
  if [ "$before_text" != "$current_text" ]; then
    echo "$path changed unexpectedly" >&2
    printf 'before:\n%s\nafter:\n%s\n' "$before_text" "$current_text" >&2
    exit 1
  fi
}

fakebin="$workdir/bin"
mkdir -p "$fakebin"
cat >"$fakebin/nix" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$NIX_CALLS"
case "${NIX_FAIL_UPDATE:-0}:$*" in
  1:"flake update "*) exit 1 ;;
esac
exit 0
FAKE
chmod +x "$fakebin/nix"
export PATH="$fakebin:$PATH"
export NIX_CALLS="$workdir/nix-calls"
export PI_EN_FLAKE_INPUT_NAME=pi-en
export PI_EN_NIX_SHELL=1

make_project() {
  local dir="$1" form="$2"
  mkdir -p "$dir/sub"
  cat >"$dir/flake.nix" <<EOF
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    other.url = "github:example/other";
    $form
  };
  outputs = { self, nixpkgs, other, pi-en }: { };
}
EOF
  : >"$dir/flake.lock"
}

help="$($updater --help)"
printf '%s' "$help" | grep -q -- '--url URL'
printf '%s' "$help" | grep -q -- '--ref REF'
if printf '%s' "$help" | grep -q -- '--prefix'; then
  echo "Nix updater help leaked non-Nix installer options" >&2
  exit 1
fi

unset PI_EN_NIX_SHELL
if "$updater" --url github:new/pi-en 2>"$workdir/outside.err"; then
  echo "updater succeeded outside the Pi-en Nix shell marker" >&2
  exit 1
fi
assert_contains "$workdir/outside.err" 'refusing to update outside a Pi-en-enabled Nix shell'
export PI_EN_NIX_SHELL=1

if "$updater" --prefix "$workdir/nope" 2>"$workdir/reject.err"; then
  echo "Nix updater accepted a non-Nix updater option" >&2
  exit 1
fi
assert_contains "$workdir/reject.err" 'unsupported Nix-shell updater option: --prefix'

p1="$workdir/ref-only"
make_project "$p1" 'pi-en.url = "github:old/pi-en?ref=old&rev=deadbeef";'
(cd "$p1/sub" && "$updater" --ref release)
assert_contains "$p1/flake.nix" 'pi-en.url = "github:old/pi-en?ref=release";'
assert_not_contains "$p1/flake.nix" 'rev=deadbeef'

p2="$workdir/url-and-commit-branch"
make_project "$p2" 'inputs.pi-en.url = "https://example.invalid/old.git";'
(cd "$p2" && "$updater" --url https://example.invalid/pi-en.git --ref abcdef1234567890@main)
assert_contains "$p2/flake.nix" 'inputs.pi-en.url = "git+https://example.invalid/pi-en.git?ref=main&rev=abcdef1234567890";'

p3="$workdir/quoted-input"
make_project "$p3" '"pi-en".url = "github:old/pi-en";'
(cd "$p3" && "$updater" --ref release)
assert_contains "$p3/flake.nix" '"pi-en".url = "github:old/pi-en?ref=release";'

p4="$workdir/dynamic"
mkdir -p "$p4"
cat >"$p4/flake.nix" <<'EOF'
{
  inputs.pi-en = { url = builtins.getEnv "PI_EN_URL"; };
  outputs = { self, pi-en }: { };
}
EOF
cp "$p4/flake.nix" "$workdir/dynamic.before"
if (cd "$p4" && "$updater" --url github:new/pi-en) 2>"$workdir/dynamic.err"; then
  echo "dynamic flake input unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$workdir/dynamic.err" 'unsupported or dynamic pi-en input definition'
assert_unchanged "$workdir/dynamic.before" "$p4/flake.nix"

p5="$workdir/lock-fallback"
make_project "$p5" 'pi-en.url = "github:old/pi-en";'
(cd "$p5" && NIX_FAIL_UPDATE=1 "$updater" --url github:new/pi-en)
assert_contains "$NIX_CALLS" 'flake update pi-en'
assert_contains "$NIX_CALLS" 'flake lock --update-input pi-en'
if grep -Fq 'other' "$NIX_CALLS"; then
  echo "updater attempted to update a non-pi-en input" >&2
  cat "$NIX_CALLS" >&2
  exit 1
fi

# `pien update` must prefer the shell-local pi-en-update when it is present,
# as in mkPiShell, and must not do that outside the simulated Nix-shell PATH.
dispatch_bin="$workdir/dispatch-bin"
mkdir -p "$dispatch_bin"
cat >"$dispatch_bin/pi-en-update" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf 'shell-local-updater:%s\n' "$*" >>"$DISPATCH_LOG"
FAKE
chmod +x "$dispatch_bin/pi-en-update"
DISPATCH_LOG="$workdir/dispatch.log" PATH="$dispatch_bin:$PATH" PI_EN_NIX_SHELL=1 PI_EN_INSIDE_SANDBOX=0 "$pien" update --ref main
assert_contains "$workdir/dispatch.log" 'shell-local-updater:--ref main'
if PATH="$fakebin:/usr/bin:/bin" PI_EN_NIX_SHELL= PI_EN_INSIDE_SANDBOX=0 "$pien" update 2>"$workdir/direct.err"; then
  echo "direct-checkout pien update unexpectedly succeeded without source arguments" >&2
  exit 1
fi
assert_contains "$workdir/direct.err" 'update from a direct checkout requires --url/--ref'

REPO_ROOT="$repo_root" node --input-type=module <<'NODE'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
const flake = readFileSync(join(process.env.REPO_ROOT, 'flake.nix'), 'utf8');
assert.match(flake, /mkPiEnNixUpdate = pkgs:/);
assert.match(flake, /piEnNixUpdate = mkPiEnNixUpdate pkgs;/);
assert.match(flake, /export PI_EN_NIX_SHELL=1/);
assert.doesNotMatch(flake, /packages = \{[\s\S]*pi-en-update =/);
assert.doesNotMatch(flake, /apps = \{[\s\S]*pi-en-update =/);
NODE

printf 'PIEN-ISS-20260810-165419-001 tests passed\n'
