#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

script=scripts/pi-en-bwrap
prompt_command="$(awk -F"'" '/bwrap_dev_prompt_command=/{print $2; exit}' "$script")"

[ -n "$prompt_command" ] || test_fail 'missing bwrap-dev prompt command setup'

test_grep 'PI_EN_DEV_SHELL_PS1' flake.nix
test_grep 'set_env PS1 "$PI_EN_DEV_SHELL_PS1"' "$script"
test_grep 'set_env PROMPT_COMMAND "$bwrap_dev_prompt_command' "$script"

evaluate_interactive_prompt() {
  local initial_ps1="$1"
  PS1="$initial_ps1" PROMPT_COMMAND="$prompt_command" \
    bash --noprofile --norc -i -c 'eval "$PROMPT_COMMAND"; printf "%s" "$PS1"' \
    2>/dev/null
}

actual="$(evaluate_interactive_prompt '(nix-dev) base$ ')"
test_eq '(bwrap-dev) (nix-dev) base$ ' "$actual" \
  'bwrap prompt should compose with inherited nix prompt'

actual="$(evaluate_interactive_prompt '(bwrap-dev) (nix-dev) base$ ')"
test_eq '(bwrap-dev) (nix-dev) base$ ' "$actual" \
  'bwrap prompt should not be duplicated'

PS1='plain$ '
eval "$prompt_command"
test_eq 'plain$ ' "$PS1" 'non-interactive prompt command should be inert'

fake_bin="$(mktemp -d)"
trap 'rm -rf "$fake_bin"' EXIT
cat >"$fake_bin/bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--setenv" ] && [ "${2:-}" = "PS1" ]; then
    printf '%s' "${3:-}"
    exit 0
  fi
  shift
done
exit 1
FAKE_BWRAP
chmod +x "$fake_bin/bwrap"

actual="$(
  env \
    PS1='should be stripped by the bash wrapper' \
    PI_EN_DEV_SHELL_PS1='(nix-dev) wrapper$ ' \
    PI_EN_RUNTIME_PATH=/usr/bin \
    PI_EN_BWRAP_BWRAP="$fake_bin/bwrap" \
    PI_EN_BWRAP_BASH="$(command -v bash)" \
    PI_EN_BWRAP_ENV="$(command -v env)" \
    bash "$script" --shell -- -lc true
)"
test_eq '(nix-dev) wrapper$ ' "$actual" \
  'bwrap wrapper path should preserve the nix prompt via PI_EN_DEV_SHELL_PS1'

test_note 'bwrap-dev prompt prefix setup is covered'
