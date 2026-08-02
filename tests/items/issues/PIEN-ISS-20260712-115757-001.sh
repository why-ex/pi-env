#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

expected="Use 'pien' for default startup, 'pien shell' for a sandbox shell, or 'pien raw -- <pi args>' for custom runs."
old="Use 'pi-en' for default startup, 'pi-en-shell' for a sandbox shell, or 'pi-en --raw -- <pi args>' for custom runs."

test_grep 'Pi agent runtime loaded' flake.nix
test_grep "$expected" flake.nix
if grep -F -- "$old" flake.nix >/dev/null; then
  test_fail 'devshell entry guidance still references lower-level commands'
fi

quiet_block="$(awk '
  /if \[ -z "\x27\x27\$\{PI_EN_QUIET:-\}" \]; then/ { in_block=1 }
  in_block { print }
  in_block && /^            fi$/ { exit }
' flake.nix)"

printf '%s\n' "$quiet_block" | grep -F -- 'echo "Pi agent runtime loaded"' >/dev/null \
  || test_fail 'runtime loaded message is not inside quiet-mode guard'
printf '%s\n' "$quiet_block" | grep -F -- "echo \"$expected\"" >/dev/null \
  || test_fail 'pien guidance is not inside quiet-mode guard'

if printf '%s\n' "$quiet_block" | grep -F -- "$old" >/dev/null; then
  test_fail 'quiet-mode guarded output still uses old guidance'
fi

test_note 'devshell entry output guidance and quiet-mode guard are covered'
