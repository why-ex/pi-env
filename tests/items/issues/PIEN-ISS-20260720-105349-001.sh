#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bash scripts/pien --help >"$tmpdir/help.out"

test_grep 'pien \[launcher options\] \[pi args\.\.\.\]' "$tmpdir/help.out"
test_grep 'pien run \[launcher options\] \[pi args\.\.\.\]' "$tmpdir/help.out"
test_grep 'pien \[launcher options\] --raw -- \[pi args\.\.\.\]' "$tmpdir/help.out"
test_grep 'pien raw -- \[pi args\.\.\.\]' "$tmpdir/help.out"
test_grep 'pien shell \[launcher options\] \[shell args\.\.\.\]' "$tmpdir/help.out"
test_grep '--runtime host|nix|auto' "$tmpdir/help.out"
test_grep '--flake REF' "$tmpdir/help.out"
test_grep '--devshell NAME' "$tmpdir/help.out"
test_grep 'PI_EN_RUNTIME' "$tmpdir/help.out"
test_grep 'PI_EN_FLAKE' "$tmpdir/help.out"
test_grep 'PI_EN_NIX_DEVSHELL' "$tmpdir/help.out"
test_grep 'CLI options win over environment values' "$tmpdir/help.out"
test_grep 'Coordination,' "$tmpdir/help.out"
test_grep 'recipe, install, uninstall, and sandbox commands have separate option sets' "$tmpdir/help.out"

bash scripts/pien completion bash >"$tmpdir/completion.bash"
bash -n "$tmpdir/completion.bash"

cat >>"$tmpdir/completion-check.sh" <<'CHECK'
source "$1"
assert_completion() {
  local expected="$1"
  shift
  COMP_WORDS=(pien "$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  _pien
  case " ${COMPREPLY[*]} " in
    *" $expected "*) ;;
    *) printf 'missing completion %s for pien %s; got: %s\n' "$expected" "$*" "${COMPREPLY[*]}" >&2; exit 1 ;;
  esac
}
assert_no_completion() {
  local unexpected="$1"
  shift
  COMP_WORDS=(pien "$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  _pien
  case " ${COMPREPLY[*]} " in
    *" $unexpected "*) printf 'unexpected completion %s for pien %s; got: %s\n' "$unexpected" "$*" "${COMPREPLY[*]}" >&2; exit 1 ;;
  esac
}
assert_completion --runtime --
assert_completion --runtime run --
assert_completion --runtime shell --
assert_completion --flake run --
assert_completion --devshell shell --
assert_no_completion --runtime raw --
assert_no_completion --flake raw --
assert_no_completion auto raw --runtime a
assert_no_completion --runtime --raw --
assert_no_completion --runtime --runtime host --raw --
assert_no_completion auto --runtime host --raw --runtime a
assert_no_completion --runtime coord --
assert_no_completion --runtime sandbox --
assert_no_completion --runtime recipe --
assert_no_completion auto coord --runtime a
CHECK
bash "$tmpdir/completion-check.sh" "$tmpdir/completion.bash"

mkdir -p "$tmpdir/bin" "$tmpdir/support"
cp scripts/pien "$tmpdir/support/pien"
chmod +x "$tmpdir/support/pien"
cat >"$tmpdir/bin/pi-en" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  printf 'arg=%s\n' "$arg"
done >"$PIEN_RAW_CAPTURE"
STUB
chmod +x "$tmpdir/bin/pi-en"
PIEN_RAW_CAPTURE="$tmpdir/raw.args" PATH="$tmpdir/bin:$PATH" \
  "$tmpdir/support/pien" raw --runtime host -- foo
printf '%s\n' \
  'arg=--raw' \
  'arg=--runtime' \
  'arg=host' \
  'arg=--' \
  'arg=foo' >"$tmpdir/expected-raw.args"
test_eq "$(cat "$tmpdir/expected-raw.args")" "$(cat "$tmpdir/raw.args")" \
  'pien raw must remain thin pi-en --raw parity dispatcher'

PIEN_RAW_CAPTURE="$tmpdir/raw-launcher.args" PATH="$tmpdir/bin:$PATH" \
  "$tmpdir/support/pien" --runtime host --raw -- foo
printf '%s\n' \
  'arg=--runtime' \
  'arg=host' \
  'arg=--raw' \
  'arg=--' \
  'arg=foo' >"$tmpdir/expected-raw-launcher.args"
test_eq "$(cat "$tmpdir/expected-raw-launcher.args")" "$(cat "$tmpdir/raw-launcher.args")" \
  'top-level raw launcher options must remain available before --raw'

test_note 'PIEN-ISS-20260720-105349 top-level help, completion, and raw parity are covered'
