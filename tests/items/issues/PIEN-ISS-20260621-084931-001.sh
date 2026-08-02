#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PI_EN_COORD_TEMPLATE_DIR="$repo_root/pi-skill-templates/agent-coordination"
export PATH="$repo_root/scripts:$PATH"

assert_no_top_level_history() {
  local path
  path="$1"
  if grep -Eq '^(current|events|messages):' "$path"; then
    test_fail "unexpected issue-history field in $path"
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME" "$tmp/project"
git config --global user.name "TODO Coordination Test"
git config --global user.email "todo-coordination@example.invalid"

cd "$tmp/project"
pi-en-coord-init \
  --root "$tmp/remotes" \
  --project pi-en \
  --agent-id agent-a \
  --dir .pi-en/coordination >/dev/null

test_dir_exists .pi-en/coordination/todos
test_grep '`TODO`: `todo`' .pi-en/coordination/docs/ITEM_FORMAT.md
test_grep '`TODO` for `todo`' .pi-en/coordination/AGENTS.md
test_grep '`TODO` for todo' .pi-en/coordination/.pi/skills/agent-coordination/SKILL.md

todo_path="$(pi-en-coord-new \
  --coord-dir .pi-en/coordination \
  --type todo \
  --testable no \
  --testability-note "Item test covers TODO creation." \
  "Example TODO" | tail -n 1)"

test_file_exists ".pi-en/coordination/$todo_path"
case "$todo_path" in
  todos/*.yaml) ;;
  *) test_fail "unexpected TODO path: $todo_path" ;;
esac

test_grep '^id: PIEN-TODO-[0-9]\{8\}-[0-9]\{6\}-001$' \
  ".pi-en/coordination/$todo_path"
test_grep '^type: todo$' ".pi-en/coordination/$todo_path"
test_grep '^status: active$' ".pi-en/coordination/$todo_path"
test_grep '^body: |-$' ".pi-en/coordination/$todo_path"
assert_no_top_level_history ".pi-en/coordination/$todo_path"

todo_id="$(grep '^id: ' ".pi-en/coordination/$todo_path" | sed 's/^id: //')"
todo_list="$(pi-en-coord-list --coord-dir .pi-en/coordination todos active)"
printf '%s\n' "$todo_list" \
  | grep -Eq "^$todo_id[[:space:]]+active[[:space:]]+Example TODO$" \
  || test_fail 'TODO item was not listed by todos active'

if pi-en-coord-new --coord-dir .pi-en/coordination --type tdo "Bad alias" \
  >"$tmp/tdo.out" 2>"$tmp/tdo.err"; then
  test_fail 'pi-en-coord-new accepted unsupported tdo alias'
fi
test_grep '--type tdo is not supported; use --type todo' "$tmp/tdo.err"

if pi-en-coord-list --coord-dir .pi-en/coordination tdo \
  >"$tmp/list-tdo.out" 2>"$tmp/list-tdo.err"; then
  test_fail 'pi-en-coord-list accepted unsupported tdo alias'
fi
test_grep 'item type must be issues, todos,' "$tmp/list-tdo.err"

printf 'PIEN-ISS-20260621-084931-001 passed\n'
