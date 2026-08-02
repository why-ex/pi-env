#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=tests/lib/test-helpers.sh
. "$repo_root/tests/lib/test-helpers.sh"

# User-facing startup guidance must name pien as the canonical agent
# namespace, while retaining existing entrypoints as compatibility behavior
# sources. pi-start may only appear in explicit removal/migration tests and
# requirements notes.
test_grep '^pien help$' README.md
test_grep '^pien completion bash$' README.md
test_grep '^pien sandbox --help$' README.md
test_grep '^pien$' README.md
test_grep 'pien raw -- --model' README.md
test_grep '`pien shell` owns runtime selection' README.md
test_grep 'sandbox layer instead of using the default startup policy' README.md
test_grep 'loads the Nix-packaged role manager by' role-manager/README.md
test_grep 'PI_EN_ROLE_MANAGER_AUTO=0 pi-en' role-manager/README.md

test_grep 'mkPiEn' REQUIREMENTS.md
test_grep 'mkPiEnShell' REQUIREMENTS.md
if grep -F 'mkPiStart' REQUIREMENTS.md .pi-en/coordination/requirements/*.yaml >/dev/null 2>&1; then
  test_fail 'requirements still document mkPiStart'
fi

if grep -RIn --exclude-dir=.git --exclude='PIEN-ISS-20260710-184852-001.sh' \
  -E '(^|[^[:alnum:]_-])pi-start([^[:alnum:]_-]|$)' \
  README.md role-manager designs examples pi-en pi-en-shell scripts/pi-en-install-non-nix flake.nix tests/*.sh \
  tests/items/issues 2>/dev/null \
  | grep -Ev 'intentionally removes|scripts/pi-en-install-non-nix:[0-9]+:  pi-start|tests/pi-en-install-non-nix.sh:[0-9]+:  pi-start|removed_command_names|command -v pi-start|stale legacy wrapper|stale pi-start wrapper|\[ ! -e .*pi-start|pi-start should not be installed|should be removed|still exposes|still installs|survived reinstall|left stale|pi-start removal tests passed|leaked into pi-core|leaked into pi-runtime|PIEN-ISS-20260710-184849-001' >/tmp/pi-en-stale-pi-start.$$; then
  cat /tmp/pi-en-stale-pi-start.$$ >&2
  rm -f /tmp/pi-en-stale-pi-start.$$
  test_fail 'stale user-facing pi-start guidance remains'
fi
rm -f /tmp/pi-en-stale-pi-start.$$

echo 'PIEN-ISS-20260710-184852-001 documentation pi-start removal tests passed'
