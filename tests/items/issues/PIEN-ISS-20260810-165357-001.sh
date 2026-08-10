#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
script="$repo_root/scripts/pi-en-update-nix-flake-input"
workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

fakebin="$workdir/bin"
mkdir -p "$fakebin"
cat >"$fakebin/nix" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$NIX_CALLS"
exit 0
FAKE
chmod +x "$fakebin/nix"
export PATH="$fakebin:$PATH"
export NIX_CALLS="$workdir/nix-calls"
export PI_EN_NIX_SHELL=1
export PI_EN_FLAKE_INPUT_NAME=pi-en

make_project() {
  local dir="$1" form="$2"
  mkdir -p "$dir/sub"
  cat >"$dir/flake.nix" <<EOF
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    $form
  };
  outputs = { self, nixpkgs, pi-en }: { };
}
EOF
  : >"$dir/flake.lock"
}

assert_contains() {
  local path="$1" text="$2"
  grep -Fq "$text" "$path" || {
    echo "missing '$text' in $path" >&2
    cat "$path" >&2
    exit 1
  }
}

help="$($script --help)"
printf '%s' "$help" | grep -q -- '--url URL'
printf '%s' "$help" | grep -q -- '--ref REF'
if printf '%s' "$help" | grep -q -- '--prefix'; then
  echo "Nix updater help leaked non-Nix installer options" >&2
  exit 1
fi

unset PI_EN_NIX_SHELL
if "$script" --url github:example/pi-en 2>"$workdir/outside.err"; then
  echo "updater succeeded outside Nix shell marker" >&2
  exit 1
fi
assert_contains "$workdir/outside.err" 'refusing to update outside'
export PI_EN_NIX_SHELL=1

p1="$workdir/p1"
make_project "$p1" 'pi-en.url = "github:old/pi-en";'
(cd "$p1/sub" && "$script" --url github:new/pi-en)
assert_contains "$p1/flake.nix" 'pi-en.url = "github:new/pi-en";'
assert_contains "$NIX_CALLS" 'flake update pi-en'

p2="$workdir/p2"
make_project "$p2" 'inputs.pi-en.url = "github:old/pi-en";'
(cd "$p2" && "$script" --url https://example.invalid/pi-en.git --ref abcdef1234567890@main)
assert_contains "$p2/flake.nix" 'inputs.pi-en.url = "git+https://example.invalid/pi-en.git?ref=main&rev=abcdef1234567890";'

p3="$workdir/p3"
make_project "$p3" '"pi-en".url = "github:old/pi-en";'
(cd "$p3" && "$script" --ref release)
assert_contains "$p3/flake.nix" '"pi-en".url = "github:old/pi-en?ref=release";'

p4="$workdir/p4"
mkdir -p "$p4"
cat >"$p4/flake.nix" <<'EOF'
{
  inputs.pi-en = { url = builtins.getEnv "PI_EN_URL"; };
  outputs = { self, pi-en }: { };
}
EOF
if (cd "$p4" && "$script" --url github:new/pi-en) 2>"$workdir/dynamic.err"; then
  echo "dynamic flake input unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$workdir/dynamic.err" 'unsupported or dynamic pi-en input definition'

if "$script" --prefix /tmp/nope 2>"$workdir/prefix.err"; then
  echo "unsupported non-Nix option unexpectedly succeeded" >&2
  exit 1
fi
assert_contains "$workdir/prefix.err" 'unsupported Nix-shell updater option'

REPO_ROOT="$repo_root" node --input-type=module <<'NODE'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
const flake = readFileSync(join(process.env.REPO_ROOT, 'flake.nix'), 'utf8');
assert.match(flake, /mkPiEnNixUpdate = pkgs:/);
assert.match(flake, /piEnNixUpdate = mkPiEnNixUpdate pkgs;/);
assert.match(flake, /export PI_EN_NIX_SHELL=1/);
assert.match(flake, /export PI_EN_FLAKE_INPUT_NAME=pi-en/);
assert.doesNotMatch(flake, /packages = \{[\s\S]*pi-en-update =/);
NODE

printf 'PIEN-ISS-20260810-165357-001 tests passed\n'
