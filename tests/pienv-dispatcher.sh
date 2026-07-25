#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/support" "$tmp_dir/bin"
cp "$repo_root/scripts/pienv" "$tmp_dir/support/pienv"
chmod +x "$tmp_dir/support/pienv"

make_stub() {
  local name="$1"
  cat > "$tmp_dir/bin/$name" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'cmd=%s\n' "$(basename "$0")"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
} > "$PIENV_TEST_LOG"
STUB
  chmod +x "$tmp_dir/bin/$name"
}

for name in \
  pi-env pi-env-shell pi-env-bwrap pi-env-bootstrap-coordination \
  pi-env-coord-init pi-env-coord-clone pi-env-coord-status pi-env-coord-list \
  pi-env-coord-cat pi-env-coord-new pi-env-coord-claim pi-env-coord-done \
  pi-env-coord-review pi-env-coord-verify pi-env-coord-close pi-env-coord-pull \
  pi-env-coord-push pi-env-coord-lint pi-env-coord-repo \
  pi-env-coord-upgrade-rules pi-env-coord-generate-requirements \
  pi-env-coord-generate-requirements-coverage pi-env-serial-roles \
  pi-env-install-non-nix pi-env-uninstall; do
  make_stub "$name"
done

run_case() {
  local expected="$1"
  shift
  : > "$tmp_dir/log"
  PIENV_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" "$@"
  actual="$(cat "$tmp_dir/log")"
  if [ "$actual" != "$expected" ]; then
    echo "pienv dispatcher mismatch for args: $*" >&2
    echo "expected:" >&2
    printf '%s\n' "$expected" >&2
    echo "actual:" >&2
    printf '%s\n' "$actual" >&2
    exit 1
  fi
}

run_case $'cmd=pi-env'
run_case $'cmd=pi-env\narg=--first' -- --first
run_case $'cmd=pi-env\narg=--foo' run --foo
run_case $'cmd=pi-env\narg=--raw\narg=--\narg=run' raw -- run
run_case $'cmd=pi-env\narg=--raw\narg=--runtime\narg=host\narg=--flake\narg=.#agent\narg=--devshell=agent\narg=--\narg=run' raw --runtime host --flake .#agent --devshell=agent -- run
run_case $'cmd=pi-env-shell\narg=--runtime\narg=nix' shell --runtime nix
run_case $'cmd=pi-env-bwrap\narg=--continue' sandbox --continue
run_case $'cmd=pi-env-bwrap\narg=--shell\narg=--\narg=-l' sandbox shell -- -l
run_case $'cmd=pi-env-bootstrap-coordination\narg=--help' coord bootstrap --help
run_case $'cmd=pi-env-coord-status\narg=--repo-id\narg=pi-env' coord status --repo-id pi-env
run_case $'cmd=pi-env-coord-cat\narg=ITEM-1' coord show ITEM-1
run_case $'cmd=pi-env-coord-upgrade-rules\narg=--check' coord rules upgrade --check
run_case $'cmd=pi-env-coord-generate-requirements\narg=--repo-id\narg=pi-env' coord requirements generate --repo-id pi-env
run_case $'cmd=pi-env-coord-generate-requirements-coverage' coord requirements coverage
run_case $'cmd=pi-env-serial-roles\narg=--role\narg=developer' roles serial --role developer
run_case $'cmd=pi-env-install-non-nix\narg=--prefix\narg=/tmp/pienv' install --prefix /tmp/pienv
run_case $'cmd=pi-env-uninstall\narg=--prefix\narg=/tmp/pienv' uninstall --prefix /tmp/pienv
rm "$tmp_dir/bin/pi-env-uninstall"
run_case $'cmd=pi-env-install-non-nix\narg=--uninstall\narg=--prefix\narg=/tmp/pienv' uninstall --prefix /tmp/pienv

version_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" version)"
case "$version_output" in
  'pienv '*) ;;
  *) echo "pienv version did not print version output" >&2; exit 1 ;;
esac

diagnostics_output="$(PI_ENV_INSIDE_SANDBOX=1 PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" diagnostics)"
case "$diagnostics_output" in
  *'PI_ENV_INSIDE_SANDBOX=1'*'coordination_helpers=available'* ) ;;
  *) echo "pienv diagnostics did not report sandbox/runtime state" >&2; exit 1 ;;
esac

run_sandbox_outer_only_case() {
  local args=("$@")
  : > "$tmp_dir/log"
  if PI_ENV_INSIDE_SANDBOX=1 PIENV_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" "${args[@]}" >"$tmp_dir/out" 2>"$tmp_dir/err"; then
    echo "in-sandbox outer-only command unexpectedly succeeded: pienv ${args[*]}" >&2
    exit 1
  fi
  if [ -s "$tmp_dir/log" ]; then
    echo "in-sandbox outer-only command dispatched unexpectedly: pienv ${args[*]}" >&2
    cat "$tmp_dir/log" >&2
    exit 1
  fi
  if ! grep -Fq 'must be run from the outer terminal' "$tmp_dir/err"; then
    echo "in-sandbox outer-only command missed actionable diagnostic: pienv ${args[*]}" >&2
    cat "$tmp_dir/err" >&2
    exit 1
  fi
}

run_sandbox_outer_only_case
run_sandbox_outer_only_case run --foo
run_sandbox_outer_only_case --runtime nix
run_sandbox_outer_only_case shell -- -lc true
run_sandbox_outer_only_case sandbox --help
run_sandbox_outer_only_case install --prefix /tmp/pienv
run_sandbox_outer_only_case uninstall --prefix /tmp/pienv

(
  export PI_ENV_INSIDE_SANDBOX=1
  run_case $'cmd=pi-env-coord-status\narg=--repo-id\narg=pi-env' coord status --repo-id pi-env
)

completion_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" completion bash)"
case "$completion_output" in
  *'complete -F _pienv pienv'*) ;;
  *) echo "pienv completion bash did not print sourceable completion" >&2; exit 1 ;;
esac
bash -n <(printf '%s\n' "$completion_output")

completion_env="$tmp_dir/completion-env.sh"
{
  printf '%s\n' "$completion_output"
  cat <<'COMPTEST'
assert_completion() {
  local expected="$1"
  shift
  COMP_WORDS=(pienv "$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  _pienv
  case " ${COMPREPLY[*]} " in
    *" $expected "*) ;;
    *) echo "missing completion '$expected' for: pienv $* (got: ${COMPREPLY[*]})" >&2; exit 1 ;;
  esac
}
assert_no_completion() {
  local unexpected="$1"
  shift
  COMP_WORDS=(pienv "$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  _pienv
  case " ${COMPREPLY[*]} " in
    *" $unexpected "*) echo "unexpected completion '$unexpected' for: pienv $* (got: ${COMPREPLY[*]})" >&2; exit 1 ;;
  esac
}
assert_completion coord c
assert_completion rules coord r
assert_completion upgrade coord rules u
assert_completion generate coord requirements g
assert_completion coverage coord requirements c
assert_completion serial roles s
assert_completion recipe r
assert_completion flake-agent-shell recipe f
assert_completion --runtime --
assert_completion --runtime run --
assert_completion --runtime shell --
assert_no_completion --runtime raw --
assert_no_completion --flake raw --
assert_no_completion --runtime --raw --
assert_no_completion --runtime --runtime host --raw --
assert_no_completion host --runtime host --raw --runtime h
assert_completion host run --runtime h
assert_completion --repo-id coord status --
assert_no_completion --runtime coord --
assert_no_completion --runtime sandbox --
assert_no_completion --runtime recipe --
assert_no_completion host coord --runtime h
COMPTEST
} > "$completion_env"
bash "$completion_env"

help_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" help)"
for snippet in \
  'pienv coord <command>' \
  'pienv recipe flake-agent-shell' \
  '--raw --' \
  'pienv raw --' \
  '--runtime host|nix|auto' \
  '--flake REF' \
  '--devshell NAME' \
  'PI_ENV_RUNTIME' \
  'PI_ENV_FLAKE' \
  'PI_ENV_NIX_DEVSHELL' \
  'CLI options win' \
  'pienv raw' \
  'pienv diagnostics' \
  'pienv version'; do
  if ! grep -Fq -- "$snippet" <<<"$help_output"; then
    echo "pienv help missed command, recipe, or runtime launcher guidance: $snippet" >&2
    exit 1
  fi
done

coord_help_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" help coord)"
case "$coord_help_output" in
  *'rules upgrade'*'pi-env-coord-upgrade-rules'*'requirements generate'*'pi-env-coord-generate-requirements'* ) ;;
  *) echo "pienv help coord did not list nested command equivalents" >&2; exit 1 ;;
esac

PIENV_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" help coord status
case "$(cat "$tmp_dir/log")" in
  $'cmd=pi-env-coord-status\narg=--help') ;;
  *) echo "pienv help coord status did not dispatch to leaf help" >&2; exit 1 ;;
esac

PIENV_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" help run
case "$(cat "$tmp_dir/log")" in
  $'cmd=pi-env\narg=--help') ;;
  *) echo "pienv help run did not delegate to pi-env help" >&2; exit 1 ;;
esac
PIENV_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" help shell
case "$(cat "$tmp_dir/log")" in
  $'cmd=pi-env-shell\narg=--help') ;;
  *) echo "pienv help shell did not delegate to pi-env-shell help" >&2; exit 1 ;;
esac

recipe_help_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" help recipe)"
case "$recipe_help_output" in
  *'flake-agent-shell'*'Recipes only print guidance'* ) ;;
  *) echo "pienv help recipe did not describe recipe command" >&2; exit 1 ;;
esac

recipe_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" recipe flake-agent-shell)"
for snippet in \
  'pi-env.url = "git+file:///home/me/src/pi-env";' \
  'outputs = { self, nixpkgs, flake-utils, pi-env, ... }:' \
  'keep that expression on' \
  'devShells.${system} = {' \
  '} // {' \
  'agent = pi-env.lib.mkPiShell {' \
  'agent = existingDevShells.default;' \
  'includeCoordinationHelpers = false;' \
  'extraPackages = with pkgs; [' \
  'does not read, edit, or write project files'; do
  if ! grep -Fq "$snippet" <<< "$recipe_output"; then
    echo "pienv recipe flake-agent-shell missed stable recipe snippet: $snippet" >&2
    exit 1
  fi
done
if grep -Fq 'self.devShells.${system}' <<< "$recipe_output"; then
  echo "pienv recipe flake-agent-shell must not recurse through self.devShells" >&2
  exit 1
fi

recipe_help_alias_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pienv" recipe flake-agent-shell --help)"
case "$recipe_help_alias_output" in
  *'pienv recipe flake-agent-shell'*'nix develop .#agent'* ) ;;
  *) echo "pienv recipe flake-agent-shell --help did not print recipe" >&2; exit 1 ;;
esac

printf 'pienv dispatcher tests passed\n'
