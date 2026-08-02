#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PI_EN_COORD_TEMPLATE_DIR="$repo_root/pi-skill-templates/agent-coordination"
export PATH="$repo_root/scripts:$PATH"

unset PI_EN_COORD_REMOTE PI_EN_COORD_WORKSPACE \
  PI_EN_COORD_DIR PI_EN_COORD_AGENT_ID PI_EN_COORD_PROJECT PI_EN_COORD_PROJECT_KEY PI_EN_COORD_ROLE

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME" "$tmp/project"
git config --global user.name "Task Type Test"
git config --global user.email "task-type-test@example.invalid"

git -C "$tmp/project" init -q
cd "$tmp/project"
pi-en-coord-init \
  --project task-type-test \
  --repo-id task-type-test \
  --agent-id agent-a >/dev/null
coord_dir="$tmp/project/.pi-en/coordination"

for unsupported_item_type in task tasks; do
  if pi-en-coord-new --coord-dir "$coord_dir" \
    --type "$unsupported_item_type" "Unsupported task item type" \
    >"$tmp/new-$unsupported_item_type.out" \
    2>"$tmp/new-$unsupported_item_type.err"; then
    test_fail "pi-en-coord-new accepted --type $unsupported_item_type"
  fi
  test_grep \
    "--type $unsupported_item_type is not a coordination item type; use --type issue --category task" \
    "$tmp/new-$unsupported_item_type.err"

  if pi-en-coord-list --coord-dir "$coord_dir" "$unsupported_item_type" \
    >"$tmp/list-$unsupported_item_type.out" \
    2>"$tmp/list-$unsupported_item_type.err"; then
    test_fail "pi-en-coord-list accepted item type $unsupported_item_type"
  fi
  test_grep \
    "$unsupported_item_type is not a coordination item type; use issues --category task" \
    "$tmp/list-$unsupported_item_type.err"
done

if pi-en-coord-new --coord-dir "$coord_dir" \
  --issue-type task "Legacy category flag" \
  >"$tmp/new-legacy-category.out" \
  2>"$tmp/new-legacy-category.err"; then
  test_fail "pi-en-coord-new accepted legacy --issue-type"
fi
test_grep '--issue-type has been removed; use --category' \
  "$tmp/new-legacy-category.err"

if pi-en-coord-list --coord-dir "$coord_dir" \
  --issue-type task issues \
  >"$tmp/list-legacy-category.out" \
  2>"$tmp/list-legacy-category.err"; then
  test_fail "pi-en-coord-list accepted legacy --issue-type"
fi
test_grep '--issue-type has been removed; use category flags' \
  "$tmp/list-legacy-category.err"

for category_alias in task tasks; do
  issue_path="$(pi-en-coord-new \
    --coord-dir "$coord_dir" \
    --repo-id task-type-test \
    --agent-id agent-a \
    --type issue \
    --category "$category_alias" \
    "Task issue category: $category_alias" | tail -n 1)"
  test_file_exists "$coord_dir/$issue_path"
  test_grep '^type: issue$' "$coord_dir/$issue_path"
  test_grep '^category: task$' "$coord_dir/$issue_path"
  case "$issue_path" in
    repos/task-type-test/issues/open/*.yaml) ;;
    *) test_fail "unexpected task issue path: $issue_path" ;;
  esac

done

printf 'PIEN-ISS-20260625-213206-001 passed\n'
