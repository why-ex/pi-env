#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
updater="$repo_root/scripts/pi-en-update-nix-flake-input"
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

assert_file_equals() {
  local expected="$1" actual="$2" expected_text actual_text
  expected_text="$(<"$expected")"
  actual_text="$(<"$actual")"
  if [ "$expected_text" != "$actual_text" ]; then
    echo "$actual differs from $expected" >&2
    printf 'expected:\n%s\nactual:\n%s\n' "$expected_text" "$actual_text" >&2
    exit 1
  fi
}

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

p1="$workdir/dynamic-no-source"
mkdir -p "$p1/sub"
cat >"$p1/flake.nix" <<'EOF'
{
  inputs.pi-en = { url = builtins.getEnv "PI_EN_URL"; };
  outputs = { self, pi-en }: { };
}
EOF
: >"$p1/flake.lock"
cp "$p1/flake.nix" "$workdir/p1.before"
(cd "$p1/sub" && "$updater" >"$workdir/no-source.out")
assert_contains "$workdir/no-source.out" 'refreshing lock'
assert_file_equals "$workdir/p1.before" "$p1/flake.nix"
assert_contains "$NIX_CALLS" 'flake update pi-en'

# Explicit source requests still parse/rewrite supported forms and refresh.
: >"$NIX_CALLS"
p2="$workdir/supported-explicit"
mkdir -p "$p2"
cat >"$p2/flake.nix" <<'EOF'
{
  inputs = {
    pi-en.url = "github:old/pi-en?ref=main";
  };
  outputs = { self, pi-en }: { };
}
EOF
(cd "$p2" && "$updater" --ref release)
assert_contains "$p2/flake.nix" 'pi-en.url = "github:old/pi-en?ref=release";'
assert_contains "$NIX_CALLS" 'flake update pi-en'

printf 'PIEN-ISS-20260810-190210-001 tests passed\n'
