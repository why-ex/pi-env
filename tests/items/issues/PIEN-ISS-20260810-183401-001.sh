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

make_project() {
  local dir="$1" input_url="$2"
  mkdir -p "$dir"
  cat >"$dir/flake.nix" <<EOF
{
  inputs = {
    pi-en.url = "$input_url";
  };
  outputs = { self, pi-en }: { };
}
EOF
  : >"$dir/flake.lock"
}

# No source options should be a successful no-op, not an error and not a lock
# update. It should not even require inspecting or rewriting the flake.
p0="$workdir/no-options"
make_project "$p0" 'github:old/pi-en?ref=main&rev=deadbeef'
cp "$p0/flake.nix" "$workdir/p0.before"
(cd "$p0" && "$updater" >"$workdir/no-options.out")
assert_contains "$workdir/no-options.out" 'nothing to update'
assert_file_equals "$workdir/p0.before" "$p0/flake.nix"
[ ! -s "$NIX_CALLS" ] || { echo "no-option updater invoked nix" >&2; cat "$NIX_CALLS" >&2; exit 1; }

# Supplying only --url should preserve the existing ref/rev selector.
p1="$workdir/url-only"
make_project "$p1" 'github:old/pi-en?ref=main&rev=deadbeef'
(cd "$p1" && "$updater" --url https://example.invalid/pi-en.git)
assert_contains "$p1/flake.nix" 'pi-en.url = "https://example.invalid/pi-en.git?ref=main&rev=deadbeef";'
assert_contains "$NIX_CALLS" 'flake update pi-en'

# Supplying only --ref should preserve the existing base URL and replace only
# the selector.
p2="$workdir/ref-only"
make_project "$p2" 'https://example.invalid/pi-en.git?ref=main&rev=deadbeef'
(cd "$p2" && "$updater" --ref release)
assert_contains "$p2/flake.nix" 'pi-en.url = "https://example.invalid/pi-en.git?ref=release";'

# Supplying the current ref should be a no-op and should not invoke nix.
: >"$NIX_CALLS"
p3="$workdir/same-ref"
make_project "$p3" 'github:old/pi-en?ref=release'
cp "$p3/flake.nix" "$workdir/p3.before"
(cd "$p3" && "$updater" --ref release >"$workdir/same-ref.out")
assert_contains "$workdir/same-ref.out" 'already uses'
assert_file_equals "$workdir/p3.before" "$p3/flake.nix"
[ ! -s "$NIX_CALLS" ] || { echo "same-ref updater invoked nix" >&2; cat "$NIX_CALLS" >&2; exit 1; }

printf 'PIEN-ISS-20260810-183401-001 tests passed\n'
