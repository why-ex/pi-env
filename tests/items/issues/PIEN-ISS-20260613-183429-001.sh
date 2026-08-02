#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

test_file_exists pi-en
test_grep "pi-en - run Pi through the pi-en launcher" <("./pi-en" --help)

set +e
missing_flake_output="$("$repo_root/pi-en" --flake 2>&1)"
missing_flake_status=$?
set -e
test_eq 2 "$missing_flake_status" 'pi-en --flake without an argument exits with usage error'
test_grep 'pi-en: --flake requires an argument' <(printf '%s\n' "$missing_flake_output")

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
fakebin="$tmpdir/bin"
mkdir -p "$fakebin" "$tmpdir/project"
cat >"$fakebin/pi-en-bwrap" <<'FAKE'
#!/usr/bin/env bash
{
  printf 'pi-en-bwrap\n'
  pwd
  printf '<%s>\n' "$@"
} >"$PI_EN_CAPTURE"
FAKE
cat >"$fakebin/nix" <<'FAKE'
#!/usr/bin/env bash
{
  printf 'nix\n'
  printf '<%s>\n' "$@"
} >"$PI_EN_CAPTURE"
FAKE
chmod +x "$fakebin"/*

capture="$tmpdir/capture"
(
  cd "$tmpdir/project"
  PI_EN_CAPTURE="$capture" PATH="$fakebin:$PATH" PI_EN_RUNTIME=auto \
    "$repo_root/pi-en" "hello prompt"
)
test_grep '^pi-en-bwrap$' "$capture"
test_grep "^$tmpdir/project$" "$capture"
test_grep '^<--tools>$' "$capture"
test_grep '^<read,bash,edit,write,grep,find,ls>$' "$capture"
test_grep '^<--continue>$' "$capture"
test_grep '^<-e>$' "$capture"
test_grep "^<$repo_root/role-manager>$" "$capture"
test_grep '^<hello prompt>$' "$capture"

(
  cd "$tmpdir/project"
  PI_EN_CAPTURE="$capture" PATH="$fakebin:$PATH" PI_EN_RUNTIME=auto \
    "$repo_root/pi-en" --raw -- --model example/model "prompt"
)
test_grep '^pi-en-bwrap$' "$capture"
test_grep '^<-->$' "$capture"
test_grep '^<--model>$' "$capture"
test_grep '^<example/model>$' "$capture"
test_grep '^<prompt>$' "$capture"

rm "$fakebin/pi-en-bwrap"
PI_EN_CAPTURE="$capture" PATH="$fakebin:$PATH" PI_EN_RUNTIME=nix \
  PI_EN_FLAKE=env-flake "$repo_root/pi-en" "env prompt"
test_grep '^nix$' "$capture"
test_grep '^<develop>$' "$capture"
test_grep '^<env-flake>$' "$capture"
test_grep '^<-c>$' "$capture"
test_grep '^<pi-en>$' "$capture"
test_grep '^<env prompt>$' "$capture"

PI_EN_CAPTURE="$capture" PATH="$fakebin:$PATH" PI_EN_RUNTIME=nix \
  PI_EN_FLAKE=env-flake "$repo_root/pi-en" --flake cli-flake "prompt"
test_grep '^nix$' "$capture"
test_grep '^<develop>$' "$capture"
test_grep '^<cli-flake>$' "$capture"
test_grep '^<-c>$' "$capture"
test_grep '^<pi-en>$' "$capture"
test_grep '^<prompt>$' "$capture"

test_grep 'mkPiEn' flake.nix
test_grep 'pi-en = piEn' flake.nix
test_grep 'program = "${piEn}/bin/pi-en"' flake.nix
test_grep 'piEn' flake.nix

echo "pi-en launcher tests passed"
