#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PI_ENV_COORD_LIB="$repo_root/scripts/pi-env-coord-lib.sh"
export PI_ENV_COORD_TEMPLATE_DIR="$repo_root/pi-skill-templates/agent-coordination"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
workspace_dir="$tmp/pi-env_test"
mkdir -p "$HOME" "$workspace_dir"
git config --global user.name "Coordination Test"
git config --global user.email "coordination-test@example.invalid"

unset PI_ENV_COORD_REMOTE PI_ENV_COORD_WORKSPACE PI_ENV_COORD_DIR \
  PI_ENV_COORD_AGENT_ID PI_ENV_COORD_PROJECT PI_ENV_COORD_PROJECT_KEY PI_ENV_COORD_ROLE

project_git="$tmp/project-git"
mkdir -p "$project_git"
git -C "$project_git" init -q
git -C "$project_git" config user.name "Project User"
git -C "$project_git" config user.email "project@example.invalid"
PI_ENV_COORD_ROLE=architect git -C "$project_git" commit --allow-empty -m "Project commit" >/dev/null
test "$(git -C "$project_git" log -1 --format='%an <%ae>')" = "Project User <project@example.invalid>"

mkdir -p "$tmp/default-root"
cd "$tmp/default-root"
git init -q
if pi-env-coord-init \
  --workspace default-demo \
  --agent-id agent-a \
  --bare-only >"$tmp/default-root.out" 2>"$tmp/default-root.err"; then
  printf 'expected --workspace to be rejected\n' >&2
  exit 1
fi
grep -q -- '--workspace has been removed; use --project' "$tmp/default-root.err"
pi-env-coord-init \
  --project default-demo \
  --agent-id agent-a \
  --bare-only >/dev/null
test -d "$tmp/default-root/.pi-env/agent-remotes/default-demo-coordination.git"
test ! -e "$HOME/agent-remotes/default-demo-coordination.git"
grep -Fxq '/.pi-env/' "$tmp/default-root/.git/info/exclude"

if [ -d /workspace ] && [ "$(realpath -m /workspace)" = "$(realpath -m "$repo_root")" ]; then
  workspace_default_root="$(cd "$repo_root" && . "$PI_ENV_COORD_LIB" && coord_default_root)"
  test "$workspace_default_root" = "/workspace/.pi-env/agent-remotes"
fi

fresh_default_project="$tmp/fresh-default-project"
mkdir -p "$fresh_default_project"
git -C "$fresh_default_project" init -q
cd "$fresh_default_project"
pi-env-coord-init \
  --project fresh-default \
  --agent-id agent-a >/dev/null

test -d "$fresh_default_project/.pi-env/agent-remotes/fresh-default-coordination.git"
test -f "$fresh_default_project/.pi-env/coordination/AGENTS.md"
test -d "$fresh_default_project/.pi-env/coordination/repos/fresh-default/issues/open"
test -d "$fresh_default_project/.pi-env/coordination/repos/fresh-default/issues/blocked"
test -d "$fresh_default_project/.pi-env/coordination/repos/fresh-default/issues/done"
test -d "$fresh_default_project/.pi-env/coordination/repos/fresh-default/issues/closed"
test -f "$fresh_default_project/.pi-env/coordination/repos/fresh-default/REPO.md"
grep -q '^repo_id: fresh-default$' "$fresh_default_project/.pi-env/coordination/repos/fresh-default/REPO.md"
grep -q 'repos/{repo_id}/issues/{status}' "$fresh_default_project/.pi-env/coordination/AGENTS.md"
grep -q 'repos/{repo_id}/issues/{status}' "$fresh_default_project/.pi-env/coordination/docs/ITEM_FORMAT.md"
grep -q 'repos/{repo_id}/issues/{status}' "$fresh_default_project/.pi-env/coordination/.pi/skills/agent-coordination/SKILL.md"
test ! -e "$fresh_default_project/.pi-env/coordination/REPOS.md"
test ! -e "$fresh_default_project/.pi-env/coordination/issues"
grep -Fxq '/.pi-env/' "$fresh_default_project/.git/info/exclude"

bootstrap_project_dir="$tmp/bootstrap-project"
mkdir -p "$bootstrap_project_dir"
git -C "$bootstrap_project_dir" init -q
git -C "$bootstrap_project_dir" remote add origin git@example.invalid:example/other-project.git
cd "$tmp"
if pi-env-bootstrap-coordination \
  --workspace stale-workspace \
  --project-root "$bootstrap_project_dir" \
  --root "$tmp/bootstrap-remotes" \
  --agent-id agent-b \
  --print-only >"$tmp/bootstrap-workspace.out" 2>"$tmp/bootstrap-workspace.err"; then
  printf 'expected pi-env-bootstrap-coordination --workspace to be rejected\n' >&2
  exit 1
fi
grep -q -- '--workspace has been removed; use --project' \
  "$tmp/bootstrap-workspace.err"

if PI_ENV_COORD_WORKSPACE=stale-workspace pi-env-bootstrap-coordination \
  --project-root "$bootstrap_project_dir" \
  --root "$tmp/bootstrap-remotes" \
  --agent-id agent-b \
  --print-only >"$tmp/bootstrap-workspace-env.out" 2>"$tmp/bootstrap-workspace-env.err"; then
  printf 'expected pi-env-bootstrap-coordination PI_ENV_COORD_WORKSPACE to be rejected\n' >&2
  exit 1
fi
grep -q -- 'PI_ENV_COORD_WORKSPACE has been removed; use PI_ENV_COORD_PROJECT' \
  "$tmp/bootstrap-workspace-env.err"

bootstrap_plan="$tmp/bootstrap-plan.txt"
PI_ENV_COORD_DIR="$tmp/stale-coordination" \
PI_ENV_COORD_PROJECT=stale-project \
PI_ENV_COORD_PROJECT_KEY=STALE \
pi-env-bootstrap-coordination \
  --project-root "$bootstrap_project_dir" \
  --root "$tmp/bootstrap-remotes" \
  --agent-id agent-b \
  --no-status >"$bootstrap_plan" 2>/dev/null

test -d "$tmp/bootstrap-remotes/other-project-coordination.git"
test -f "$bootstrap_project_dir/.pi-env/coordination/AGENTS.md"
test -d "$bootstrap_project_dir/.pi-env/coordination/repos/other-project/issues/open"
test -f "$bootstrap_project_dir/.pi-env/coordination/repos/other-project/REPO.md"
test ! -e "$bootstrap_project_dir/.pi-env/coordination/WORKSPACE.md"
test ! -e "$bootstrap_project_dir/.pi-env/coordination/workspace"
test ! -e "$bootstrap_project_dir/.pi-env/coordination/functional-requirements"
test ! -e "$bootstrap_project_dir/.pi-env/coordination/quality-requirements"
test ! -e "$bootstrap_project_dir/.pi-env/coordination/constraint-requirements"
test -d "$bootstrap_project_dir/.pi-env/coordination/requirements"
test -d "$bootstrap_project_dir/.pi-env/coordination/todos"
test -d "$bootstrap_project_dir/.pi-env/coordination/notes"
grep -q '^project: other-project$' "$bootstrap_project_dir/.pi-env/coordination/PROJECT.md"
grep -q '^item_key: OTHERPROJECT$' "$bootstrap_project_dir/.pi-env/coordination/PROJECT.md"
grep -q '^domain_generated_files: \[\]$' "$bootstrap_project_dir/.pi-env/coordination/repos/other-project/REPO.md"
grep -q "Coordination clone dir:      $bootstrap_project_dir/.pi-env/coordination" "$bootstrap_plan"
grep -q "export PI_ENV_COORD_REMOTE=$tmp/bootstrap-remotes/other-project-coordination.git" "$bootstrap_plan"
grep -Fxq '/.pi-env/' "$bootstrap_project_dir/.git/info/exclude"
grep -q 'export PI_ENV_COORD_PROJECT=other-project' "$bootstrap_plan"
! grep -q 'PI_ENV_COORD_WORKSPACE' "$bootstrap_plan"
grep -q "^coordination_remote: $tmp/bootstrap-remotes/other-project-coordination.git$" \
  "$bootstrap_project_dir/.pi-env-coordination.yaml"

bootstrap_remote="$tmp/bootstrap-remotes/other-project-coordination.git"
bootstrap_coord_dir="$bootstrap_project_dir/.pi-env/coordination"
bootstrap_remote_rel="../../../bootstrap-remotes/other-project-coordination.git"
bootstrap_head="$(git -C "$bootstrap_coord_dir" rev-parse HEAD)"
test "$(git -C "$bootstrap_coord_dir" remote get-url origin)" = "$bootstrap_remote_rel"
git -C "$bootstrap_coord_dir" remote remove origin
rm -rf "$bootstrap_remote"
pi-env-bootstrap-coordination \
  --project-root "$bootstrap_project_dir" \
  --root "$tmp/bootstrap-remotes" \
  --agent-id agent-b \
  --no-status >/dev/null

test -d "$bootstrap_remote"
test "$(git --git-dir="$bootstrap_remote" rev-parse main)" = "$bootstrap_head"
test "$(git -C "$bootstrap_coord_dir" remote get-url origin)" = "$bootstrap_remote_rel"

rm -rf "$bootstrap_remote"
pi-env-bootstrap-coordination \
  --project-root "$bootstrap_project_dir" \
  --root "$tmp/bootstrap-remotes" \
  --agent-id agent-b \
  --no-status >/dev/null

test -d "$bootstrap_remote"
test "$(git --git-dir="$bootstrap_remote" rev-parse main)" = "$bootstrap_head"

print_only_project_dir="$tmp/print-only-project"
mkdir -p "$print_only_project_dir"
git -C "$print_only_project_dir" init -q
git -C "$print_only_project_dir" remote add origin https://example.invalid/org/printed-project.git
cd "$tmp"
pi-env-bootstrap-coordination \
  --project-root "$print_only_project_dir" \
  --root "$tmp/print-only-remotes" \
  --print-only >/dev/null

test ! -e "$tmp/print-only-remotes"
test ! -e "$print_only_project_dir/.pi-env/coordination"

fresh_print_project_dir="$tmp/fresh-print-project"
mkdir -p "$fresh_print_project_dir"
git -C "$fresh_print_project_dir" init -q
pi-env-bootstrap-coordination \
  --project-root "$fresh_print_project_dir" \
  --print-only >"$tmp/fresh-print-plan.txt" 2>/dev/null
grep -q "Root:                        $fresh_print_project_dir/.pi-env/agent-remotes" \
  "$tmp/fresh-print-plan.txt"
grep -q "Coordination clone dir:      $fresh_print_project_dir/.pi-env/coordination" \
  "$tmp/fresh-print-plan.txt"
grep -q 'export PI_ENV_COORD_REMOTE=.pi-env/agent-remotes/fresh-print-project-coordination.git' \
  "$tmp/fresh-print-plan.txt"
test ! -e "$fresh_print_project_dir/.pi-env"
test ! -e "$fresh_print_project_dir/.pi-env-coordination.yaml"

server_print_project_dir="$tmp/server-print-project"
mkdir -p "$server_print_project_dir"
git -C "$server_print_project_dir" init -q
server_print_remote="$tmp/server-print.git"
pi-env-bootstrap-coordination \
  --project-root "$server_print_project_dir" \
  --root "$tmp/server-print-remotes" \
  --remote "$server_print_remote" \
  --print-only >"$tmp/server-print-plan.txt" 2>/dev/null

grep -q "Coordination remote:         $server_print_remote" "$tmp/server-print-plan.txt"
grep -q "pi-env-coord-init --remote $server_print_remote" "$tmp/server-print-plan.txt"
test ! -e "$tmp/server-print-remotes"
test ! -e "$server_print_project_dir/.pi-env/coordination"

server_remote="$tmp/server-remote.git"
git init --bare --initial-branch=main "$server_remote" >/dev/null 2>&1 \
  || git init --bare "$server_remote" >/dev/null
pi-env-coord-init \
  --remote "$server_remote" \
  --project server-demo \
  --agent-id agent-server \
  --dir "$tmp/server-coordination" >/dev/null

test -f "$tmp/server-coordination/AGENTS.md"
server_head="$(git --git-dir="$server_remote" rev-parse main)"
pi-env-coord-init \
  --remote "$server_remote" \
  --project server-demo \
  --agent-id agent-server \
  --dir "$tmp/server-coordination-existing" >/dev/null

test "$(git -C "$tmp/server-coordination-existing" rev-parse HEAD)" = "$server_head"

env_remote="$tmp/env-clone-remote.git"
git clone --bare "$server_remote" "$env_remote" >/dev/null 2>&1
unset PI_ENV_COORD_REMOTE
PI_ENV_COORD_REMOTE="$env_remote" pi-env-coord-clone \
  --dir "$tmp/env-remote-clone" >/dev/null
test -f "$tmp/env-remote-clone/AGENTS.md"
pi-env-coord-clone \
  --remote "$server_remote" \
  --dir "$tmp/arg-remote-clone" >/dev/null
test -f "$tmp/arg-remote-clone/AGENTS.md"

clone_default_project="$tmp/clone-default-project"
mkdir -p "$clone_default_project"
git -C "$clone_default_project" init -q
cd "$clone_default_project"
pi-env-coord-clone \
  --remote "$server_remote" >/dev/null
test -f "$clone_default_project/.pi-env/coordination/AGENTS.md"
grep -Fxq '/.pi-env/' "$clone_default_project/.git/info/exclude"

bare_only_project_dir="$tmp/bare-only-project"
mkdir -p "$bare_only_project_dir"
git -C "$bare_only_project_dir" init -q
git -C "$bare_only_project_dir" remote add origin https://example.invalid/org/bare-project.git
cd "$tmp"
pi-env-bootstrap-coordination \
  --project-root "$bare_only_project_dir" \
  --root "$tmp/bare-only-remotes" \
  --bare-only \
  --no-status >/dev/null

test -d "$tmp/bare-only-remotes/bare-project-coordination.git"
test ! -e "$bare_only_project_dir/.pi-env/coordination"

bare_only_mixed_case_project="$tmp/bare-only-mixed-case-project"
mkdir -p "$bare_only_mixed_case_project"
git -C "$bare_only_mixed_case_project" init -q
git -C "$bare_only_mixed_case_project" remote add origin \
  https://example.invalid/Org/MixedCase.git
cd "$bare_only_mixed_case_project"
pi-env-coord-init \
  --project demo \
  --root "$tmp/bare-only-mixed-case-remotes" \
  --bare-only >/dev/null

test -d "$tmp/bare-only-mixed-case-remotes/demo-coordination.git"
test ! -e "$bare_only_mixed_case_project/.pi-env/coordination"

cd "$workspace_dir"
pi-env-coord-init \
  --root "$tmp/remotes" \
  --project pi-env \
  --agent-id agent-a \
  --dir .pi-env/coordination >/dev/null

test -d "$tmp/remotes/pi-env-coordination.git"
test -f .pi-env/coordination/AGENTS.md
test -f .pi-env/coordination/docs/SYNC_PROTOCOL.md
test -f .pi-env/coordination/docs/ITEM_FORMAT.md
test -f .pi-env/coordination/.pi/skills/agent-coordination/SKILL.md
test -d .pi-env/coordination/repos/pi-env/issues/open
test -d .pi-env/coordination/repos/pi-env/issues/done
test -f .pi-env/coordination/repos/pi-env/REPO.md
grep -q '^repo_id: pi-env$' .pi-env/coordination/repos/pi-env/REPO.md
test ! -e .pi-env/coordination/issues
test ! -e .pi-env/coordination/WORKSPACE.md
test ! -e .pi-env/coordination/workspace
test ! -e .pi-env/coordination/functional-requirements
test ! -e .pi-env/coordination/quality-requirements
test ! -e .pi-env/coordination/constraint-requirements
test -d .pi-env/coordination/requirements
test -d .pi-env/coordination/todos
test -d .pi-env/coordination/notes
grep -q '^project: pi-env$' .pi-env/coordination/PROJECT.md
grep -q '^item_key: PIENV$' .pi-env/coordination/PROJECT.md
git -C .pi-env/coordination config --get pull.rebase | grep -qx true
git -C .pi-env/coordination config --get rebase.autoStash | grep -qx true
test "$(git -C .pi-env/coordination remote get-url origin)" = "../../../remotes/pi-env-coordination.git"
export PI_ENV_COORD_REPO_ID=pi-env

cd "$tmp"
pi-env-coord-clone \
  --root "$tmp/remotes" \
  --project pi-env \
  --dir clone >/dev/null

test -f clone/AGENTS.md
test -f clone/docs/SYNC_PROTOCOL.md
test "$(git -C clone remote get-url origin)" = "../remotes/pi-env-coordination.git"

git -C clone remote remove origin
pi-env-coord-clone \
  --root "$tmp/remotes" \
  --project pi-env \
  --dir clone >/dev/null

test "$(git -C clone remote get-url origin)" = "../remotes/pi-env-coordination.git"

git -C clone rev-parse --verify HEAD >/dev/null

action_path="$(cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --agent-id agent-a \
  --role architect \
  --category Bug \
  "Document pi config behavior" | tail -n 1)"

test -f "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^id: PIENV-ISS-[0-9]\{8\}-[0-9]\{6\}-001$' \
  "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^status: open$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^category: bug$' "$workspace_dir/.pi-env/coordination/$action_path"
if grep -q '^issue_type:' "$workspace_dir/.pi-env/coordination/$action_path"; then
  printf 'new issue unexpectedly contained legacy issue_type field\n' >&2
  exit 1
fi
grep -q '^done: null$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^reviewed: false$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^verified: false$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^testable: yes$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^testability_note: null$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^project: pi-env$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q "^title: 'Document pi config behavior'$" \
  "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^    type: opened$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^      id: agent-a$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^      role: architect$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^      # Document pi config behavior$' \
  "$workspace_dir/.pi-env/coordination/$action_path"

if (cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --project other-project \
  "Legacy project item" >/dev/null 2>"$tmp/project-option.err"); then
  printf 'expected --project to be rejected for pi-env-coord-new\n' >&2
  exit 1
fi
grep -q -- '--project has been removed' "$tmp/project-option.err"

if (cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --project-key 'my_key | test/foo\bar' \
  "Conflicting project key item" >/dev/null 2>"$tmp/project-key-conflict.err"); then
  printf 'expected conflicting --project-key to be rejected\n' >&2
  exit 1
fi
grep -q -- '--project-key conflicts with stored project item_key: PIENV' \
  "$tmp/project-key-conflict.err"

if (cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --workspace-item \
  "Workspace coordination item" >/dev/null 2>"$tmp/workspace-item.err"); then
  printf 'expected --workspace-item to be rejected\n' >&2
  exit 1
fi
grep -q -- '--workspace-item has been removed' "$tmp/workspace-item.err"

requirement_path="$(cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type functional \
  --status accepted \
  --testable no \
  --testability-note "Covered by coordination helper smoke tests." \
  "Functional requirement item naming" | tail -n 1)"
grep -q '^id: PIENV-FRQ-[0-9]\{8\}-[0-9]\{6\}-001$' \
  "$workspace_dir/.pi-env/coordination/$requirement_path"
grep -q '^type: functional-requirement$' "$workspace_dir/.pi-env/coordination/$requirement_path"
grep -q '^status: accepted$' "$workspace_dir/.pi-env/coordination/$requirement_path"
grep -q '^testable: no$' "$workspace_dir/.pi-env/coordination/$requirement_path"
case "$requirement_path" in
  requirements/*.yaml) ;;
  *) printf 'unexpected requirement path: %s\n' "$requirement_path" >&2; exit 1 ;;
esac

quality_requirement_path="$(cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type quality \
  --status accepted \
  --testable no \
  --testability-note "Covered by coordination helper smoke tests." \
  "Quality requirement item naming" | tail -n 1)"
grep -q '^id: PIENV-QRQ-[0-9]\{8\}-[0-9]\{6\}-001$' \
  "$workspace_dir/.pi-env/coordination/$quality_requirement_path"
grep -q '^type: quality-requirement$' "$workspace_dir/.pi-env/coordination/$quality_requirement_path"
case "$quality_requirement_path" in
  requirements/*.yaml) ;;
  *) printf 'unexpected quality requirement path: %s\n' "$quality_requirement_path" >&2; exit 1 ;;
esac

constraint_requirement_path="$(cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type constraint \
  --status accepted \
  --testable no \
  --testability-note "Covered by coordination helper smoke tests." \
  "Constraint requirement item naming" | tail -n 1)"
grep -q '^id: PIENV-CRQ-[0-9]\{8\}-[0-9]\{6\}-001$' \
  "$workspace_dir/.pi-env/coordination/$constraint_requirement_path"
grep -q '^type: constraint-requirement$' "$workspace_dir/.pi-env/coordination/$constraint_requirement_path"
case "$constraint_requirement_path" in
  requirements/*.yaml) ;;
  *) printf 'unexpected constraint requirement path: %s\n' "$constraint_requirement_path" >&2; exit 1 ;;
esac

if (cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type requirement \
  --status accepted \
  --testable no \
  --testability-note "Covered by coordination helper smoke tests." \
  "Legacy requirement item naming" >/dev/null 2>"$tmp/generic-req.err"); then
  printf 'expected generic requirement creation to be rejected\n' >&2
  exit 1
fi
grep -q 'generic requirement items have been removed' "$tmp/generic-req.err"

todo_path="$(cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type todo \
  --testable no \
  --testability-note "Lightweight TODO covered by coordination smoke tests." \
  "Lightweight TODO item" | tail -n 1)"
grep -q '^id: PIENV-TODO-[0-9]\{8\}-[0-9]\{6\}-001$' \
  "$workspace_dir/.pi-env/coordination/$todo_path"
grep -q '^type: todo$' "$workspace_dir/.pi-env/coordination/$todo_path"
grep -q '^body: |-$' "$workspace_dir/.pi-env/coordination/$todo_path"
if grep -Eq '^(current|events|messages):' "$workspace_dir/.pi-env/coordination/$todo_path"; then
  printf 'todo item unexpectedly contained issue history\n' >&2
  exit 1
fi
case "$todo_path" in
  todos/*.yaml) ;;
  *) printf 'unexpected todo path: %s\n' "$todo_path" >&2; exit 1 ;;
esac
if pi-env-coord-new --coord-dir "$workspace_dir/.pi-env/coordination" --type tdo \
  "Unsupported TODO abbreviation" >"$tmp/tdo.out" 2>"$tmp/tdo.err"; then
  printf 'pi-env-coord-new unexpectedly accepted --type tdo\n' >&2
  exit 1
fi
grep -q -- '--type tdo is not supported; use --type todo' "$tmp/tdo.err"
for unsupported_item_type in task tasks; do
  if pi-env-coord-new --coord-dir "$workspace_dir/.pi-env/coordination" \
    --type "$unsupported_item_type" "Unsupported task item type" \
    >"$tmp/$unsupported_item_type-type.out" 2>"$tmp/$unsupported_item_type-type.err"; then
    printf 'pi-env-coord-new unexpectedly accepted --type %s\n' \
      "$unsupported_item_type" >&2
    exit 1
  fi
  grep -q -- \
    "--type $unsupported_item_type is not a coordination item type; use --type issue --category task" \
    "$tmp/$unsupported_item_type-type.err"
done

if pi-env-coord-new --coord-dir "$workspace_dir/.pi-env/coordination" \
  --issue-type task "Legacy issue type flag" \
  >"$tmp/new-legacy-category.out" 2>"$tmp/new-legacy-category.err"; then
  printf 'pi-env-coord-new unexpectedly accepted --issue-type\n' >&2
  exit 1
fi
grep -q -- '--issue-type has been removed; use --category' \
  "$tmp/new-legacy-category.err"

todo_open_path="$(cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type todo \
  --status open \
  --testable no \
  --testability-note "Open TODO covered by list status-filter tests." \
  "Open TODO item" | tail -n 1)"
grep -q '^type: todo$' "$workspace_dir/.pi-env/coordination/$todo_open_path"
grep -q '^status: open$' "$workspace_dir/.pi-env/coordination/$todo_open_path"
case "$todo_open_path" in
  todos/*.yaml) ;;
  *) printf 'unexpected open todo path: %s\n' "$todo_open_path" >&2; exit 1 ;;
esac

note_path="$(cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type note \
  --status active \
  --testable no \
  --testability-note "Note item covered by list and cat smoke tests." \
  "Reference note item" | tail -n 1)"
grep -q '^id: PIENV-NOTE-[0-9]\{8\}-[0-9]\{6\}-001$' \
  "$workspace_dir/.pi-env/coordination/$note_path"
grep -q '^type: note$' "$workspace_dir/.pi-env/coordination/$note_path"
grep -q '^status: active$' "$workspace_dir/.pi-env/coordination/$note_path"
case "$note_path" in
  notes/*.yaml) ;;
  *) printf 'unexpected note path: %s\n' "$note_path" >&2; exit 1 ;;
esac

requirement_id="$(grep '^id: ' "$workspace_dir/.pi-env/coordination/$requirement_path" | sed 's/^id: //')"
quality_requirement_id="$(grep '^id: ' "$workspace_dir/.pi-env/coordination/$quality_requirement_path" | sed 's/^id: //')"
constraint_requirement_id="$(grep '^id: ' "$workspace_dir/.pi-env/coordination/$constraint_requirement_path" | sed 's/^id: //')"
todo_id="$(grep '^id: ' "$workspace_dir/.pi-env/coordination/$todo_path" | sed 's/^id: //')"
todo_open_id="$(grep '^id: ' "$workspace_dir/.pi-env/coordination/$todo_open_path" | sed 's/^id: //')"
note_id="$(grep '^id: ' "$workspace_dir/.pi-env/coordination/$note_path" | sed 's/^id: //')"

decision_path="$(cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type decision \
  --status accepted \
  --testable no \
  --testability-note "Decision item covered by list helper smoke tests." \
  "Use coordination list helper" | tail -n 1)"
grep -q '^id: PIENV-DEC-[0-9]\{8\}-[0-9]\{6\}-001$' \
  "$workspace_dir/.pi-env/coordination/$decision_path"
grep -q '^type: decision$' "$workspace_dir/.pi-env/coordination/$decision_path"
grep -q '^status: accepted$' "$workspace_dir/.pi-env/coordination/$decision_path"
case "$decision_path" in
  decisions/*.yaml) ;;
  *) printf 'unexpected decision path: %s\n' "$decision_path" >&2; exit 1 ;;
esac

decision_id="$(grep '^id: ' "$workspace_dir/.pi-env/coordination/$decision_path" | sed 's/^id: //')"
item_id="$(grep '^id: ' "$workspace_dir/.pi-env/coordination/$action_path" | sed 's/^id: //')"

test "$(pi-env-coord-cat --coord-dir "$workspace_dir/.pi-env/coordination" "$item_id")" = \
  "$(cat "$workspace_dir/.pi-env/coordination/$action_path")"
test "$(pi-env-coord-cat --coord-dir "$workspace_dir/.pi-env/coordination" --path "$item_id")" = "$action_path"
test "$(pi-env-coord-cat --coord-dir "$workspace_dir/.pi-env/coordination" --path "$action_path")" = "$action_path"
test "$(pi-env-coord-cat \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --path "${item_id%-001}")" = "$action_path"

task_issue_path="$(cd "$workspace_dir" && pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --agent-id agent-a \
  --role architect \
  --category Tasks \
  "Task issue category item" | tail -n 1)"
grep -q '^type: issue$' "$workspace_dir/.pi-env/coordination/$task_issue_path"
grep -q '^category: task$' "$workspace_dir/.pi-env/coordination/$task_issue_path"
case "$task_issue_path" in
  repos/pi-env/issues/open/*.yaml) ;;
  *) printf 'unexpected task issue path: %s\n' "$task_issue_path" >&2; exit 1 ;;
esac
task_issue_id="$(grep '^id: ' "$workspace_dir/.pi-env/coordination/$task_issue_path" | sed 's/^id: //')"
test "$(pi-env-coord-cat --coord-dir "$workspace_dir/.pi-env/coordination" "$todo_id")" = \
  "$(cat "$workspace_dir/.pi-env/coordination/$todo_path")"
test "$(pi-env-coord-cat --coord-dir "$workspace_dir/.pi-env/coordination" --path "$todo_id")" = "$todo_path"
test "$(pi-env-coord-cat --coord-dir "$workspace_dir/.pi-env/coordination" "$note_id")" = \
  "$(cat "$workspace_dir/.pi-env/coordination/$note_path")"
test "$(pi-env-coord-cat --coord-dir "$workspace_dir/.pi-env/coordination" --path "$note_id")" = "$note_path"
test "$(pi-env-coord-cat \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --path "${note_id%-001}")" = "$note_path"
if pi-env-coord-cat --coord-dir "$workspace_dir/.pi-env/coordination" MISSING-ITEM \
  >"$tmp/cat-missing.out" 2>"$tmp/cat-missing.err"; then
  printf 'pi-env-coord-cat unexpectedly found missing item\n' >&2
  exit 1
fi
grep -q '^pi-env-coord: item not found: MISSING-ITEM$' "$tmp/cat-missing.err"
if pi-env-coord-cat --coord-dir "$workspace_dir/.pi-env/coordination" PIENV \
  >"$tmp/cat-ambiguous.out" 2>"$tmp/cat-ambiguous.err"; then
  printf 'pi-env-coord-cat unexpectedly resolved ambiguous prefix\n' >&2
  exit 1
fi
grep -q '^pi-env-coord: multiple items match PIENV:' "$tmp/cat-ambiguous.err"
grep -q "$action_path" "$tmp/cat-ambiguous.err"

issue_list="$(pi-env-coord-list --coord-dir "$workspace_dir/.pi-env/coordination" issues open)"
printf '%s\n' "$issue_list" \
  | grep -Eq "^$item_id[[:space:]]+open[[:space:]]+Document pi config behavior$"
category_list="$(pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" --show-category issues open)"
printf '%s\n' "$category_list" \
  | grep -Eq "^bug[[:space:]]+$item_id[[:space:]]+open[[:space:]]+Document pi config behavior$"
category_filter_list="$(pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" --category bug issues open)"
printf '%s\n' "$category_filter_list" \
  | grep -Eq "^$item_id[[:space:]]+open[[:space:]]+Document pi config behavior$"
task_category_filter_list="$(pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" --category tasks issues open)"
printf '%s\n' "$task_category_filter_list" \
  | grep -Eq "^$task_issue_id[[:space:]]+open[[:space:]]+Task issue category item$"
if printf '%s\n' "$task_category_filter_list" | grep -q "$item_id"; then
  printf 'task category filter included non-task issue\n' >&2
  exit 1
fi
category_group_list="$(pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" --group-by-category issues open)"
printf '%s\n' "$category_group_list" \
  | grep -Eq "^bug[[:space:]]+$item_id[[:space:]]+open[[:space:]]+Document pi config behavior$"
for legacy_category_flag in --issue-type --show-issue-type --group-by-issue-type; do
  if pi-env-coord-list --coord-dir "$workspace_dir/.pi-env/coordination" \
    "$legacy_category_flag" issues open \
    >"$tmp/list-legacy-category.out" 2>"$tmp/list-legacy-category.err"; then
    printf 'pi-env-coord-list unexpectedly accepted %s\n' \
      "$legacy_category_flag" >&2
    exit 1
  fi
  grep -q -- "$legacy_category_flag has been removed; use category flags" \
    "$tmp/list-legacy-category.err"
done
requirement_list="$(pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" functional-requirements accepted)"
printf '%s\n' "$requirement_list" \
  | grep -Eq "^$requirement_id[[:space:]]+accepted[[:space:]]+Functional requirement item naming$"
all_requirement_list="$(pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" requirements accepted)"
printf '%s\n' "$all_requirement_list" \
  | grep -Eq "^$requirement_id[[:space:]]+accepted[[:space:]]+Functional requirement item naming$"
printf '%s\n' "$all_requirement_list" \
  | grep -Eq "^$quality_requirement_id[[:space:]]+accepted[[:space:]]+Quality requirement item naming$"
printf '%s\n' "$all_requirement_list" \
  | grep -Eq "^$constraint_requirement_id[[:space:]]+accepted[[:space:]]+Constraint requirement item naming$"
if pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" legacy-requirements accepted \
  >"$tmp/legacy-requirements.out" 2>"$tmp/legacy-requirements.err"; then
  printf 'pi-env-coord-list unexpectedly accepted legacy requirements\n' >&2
  exit 1
fi
grep -q 'generic REQ requirement listing has been removed' "$tmp/legacy-requirements.err"
decision_list="$(pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" decisions accepted)"
printf '%s\n' "$decision_list" \
  | grep -Eq "^$decision_id[[:space:]]+accepted[[:space:]]+Use coordination list helper$"
todo_list="$(pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" todos active)"
printf '%s\n' "$todo_list" \
  | grep -Eq "^$todo_id[[:space:]]+active[[:space:]]+Lightweight TODO item$"
todo_open_list="$(pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" todo open)"
printf '%s\n' "$todo_open_list" \
  | grep -Eq "^$todo_open_id[[:space:]]+open[[:space:]]+Open TODO item$"
all_todo_list="$(pi-env-coord-list --coord-dir "$workspace_dir/.pi-env/coordination" todos)"
printf '%s\n' "$all_todo_list" \
  | grep -Eq "^$todo_id[[:space:]]+active[[:space:]]+Lightweight TODO item$"
printf '%s\n' "$all_todo_list" \
  | grep -Eq "^$todo_open_id[[:space:]]+open[[:space:]]+Open TODO item$"
note_list="$(pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" notes active)"
printf '%s\n' "$note_list" \
  | grep -Eq "^$note_id[[:space:]]+active[[:space:]]+Reference note item$"
note_alias_list="$(pi-env-coord-list \
  --coord-dir "$workspace_dir/.pi-env/coordination" note active)"
printf '%s\n' "$note_alias_list" \
  | grep -Eq "^$note_id[[:space:]]+active[[:space:]]+Reference note item$"
if printf '%s\n' "$note_alias_list" | grep -q "$todo_id"; then
  printf 'note list included a todo item\n' >&2
  exit 1
fi
all_note_list="$(pi-env-coord-list --coord-dir "$workspace_dir/.pi-env/coordination" notes)"
printf '%s\n' "$all_note_list" \
  | grep -Eq "^$note_id[[:space:]]+active[[:space:]]+Reference note item$"
if pi-env-coord-list --coord-dir "$workspace_dir/.pi-env/coordination" tdo \
  >"$tmp/list-tdo.out" 2>"$tmp/list-tdo.err"; then
  printf 'pi-env-coord-list unexpectedly accepted tdo alias\n' >&2
  exit 1
fi
grep -q 'item type must be issues, todos,' "$tmp/list-tdo.err"
for unsupported_list_type in task tasks; do
  if pi-env-coord-list --coord-dir "$workspace_dir/.pi-env/coordination" \
    "$unsupported_list_type" >"$tmp/list-$unsupported_list_type.out" \
    2>"$tmp/list-$unsupported_list_type.err"; then
    printf 'pi-env-coord-list unexpectedly accepted %s item type\n' \
      "$unsupported_list_type" >&2
    exit 1
  fi
  grep -q \
    "$unsupported_list_type is not a coordination item type; use issues --category task" \
    "$tmp/list-$unsupported_list_type.err"
done

pi-env-coord-status --coord-dir "$workspace_dir/.pi-env/coordination" >/dev/null
pi-env-coord-push \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id agent-a \
  --role architect \
  -m "Add coordination test item" >/dev/null
test "$(git -C "$workspace_dir/.pi-env/coordination" log -1 --format='%an <%ae>|%cn <%ce>')" = \
  "agent-a/architect <agent-a+architect@coordination.local>|agent-a/architect <agent-a+architect@coordination.local>"

pi-env-coord-claim \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id agent-a \
  --role developer \
  "$item_id" >/dev/null

grep -q '^status: claimed$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^owner: agent-a$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^    type: claimed$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^      role: developer$' "$workspace_dir/.pi-env/coordination/$action_path"
grep -q '^      Claimed\.$' "$workspace_dir/.pi-env/coordination/$action_path"
test "$(git -C "$workspace_dir/.pi-env/coordination" log -1 --format='%an <%ae>|%cn <%ce>')" = \
  "agent-a/developer <agent-a+developer@coordination.local>|agent-a/developer <agent-a+developer@coordination.local>"

done_path="$(pi-env-coord-done \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id agent-a \
  --role developer \
  --result "Implemented in test." \
  --implementation-ref \
  "pi-env:main@0123456789abcdef0123456789abcdef01234567" \
  "$item_id" | tail -n 1)"

test -f "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^status: done$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^done: 20' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^closed: null$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^reviewed: false$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^verified: false$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^    type: done$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^      role: developer$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^      - repo: pi-env$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^        branch: main$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^        commit: 0123456789abcdef0123456789abcdef01234567$' \
  "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^      Implemented in test\.$' "$workspace_dir/.pi-env/coordination/$done_path"
test "$(git -C "$workspace_dir/.pi-env/coordination" log -1 --format='%an <%ae>|%cn <%ce>')" = \
  "agent-a/developer <agent-a+developer@coordination.local>|agent-a/developer <agent-a+developer@coordination.local>"

done_issue_list="$(pi-env-coord-list --coord-dir "$workspace_dir/.pi-env/coordination" issues done)"
printf '%s\n' "$done_issue_list" \
  | grep -Eq "^$item_id[[:space:]]+done[[:space:]]+Document pi config behavior \\(reviewed:false, verified:false\\)$"

review_path="$(pi-env-coord-review \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id reviewer-a \
  --role reviewer \
  --pass \
  --result "Review passed." \
  "$item_id" | tail -n 1)"

test "$review_path" = "$done_path"
grep -q '^reviewed: true$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^    type: reviewed$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^      role: reviewer$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^      Review passed\.$' "$workspace_dir/.pi-env/coordination/$done_path"
test "$(git -C "$workspace_dir/.pi-env/coordination" log -1 --format='%an <%ae>|%cn <%ce>')" = \
  "reviewer-a/reviewer <reviewer-a+reviewer@coordination.local>|reviewer-a/reviewer <reviewer-a+reviewer@coordination.local>"

verify_path="$(PI_ENV_COORD_ROLE=tester pi-env-coord-verify \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id tester-a \
  --pass \
  --result "Verification passed." \
  "$item_id" | tail -n 1)"

test "$verify_path" = "$done_path"
grep -q '^verified: true$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^    type: verified$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^      role: tester$' "$workspace_dir/.pi-env/coordination/$done_path"
grep -q '^      Verification passed\.$' "$workspace_dir/.pi-env/coordination/$done_path"
test "$(git -C "$workspace_dir/.pi-env/coordination" log -1 --format='%an <%ae>|%cn <%ce>')" = \
  "tester-a/tester <tester-a+tester@coordination.local>|tester-a/tester <tester-a+tester@coordination.local>"

reviewed_verified_done_issue_list="$(pi-env-coord-list --coord-dir "$workspace_dir/.pi-env/coordination" issues done)"
printf '%s\n' "$reviewed_verified_done_issue_list" \
  | grep -Eq "^$item_id[[:space:]]+done[[:space:]]+Document pi config behavior \\(reviewed:true, verified:true\\)$"

closed_path="$(PI_ENV_COORD_ROLE=tester pi-env-coord-close \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id tester-a \
  --result "Closed after review and verification." \
  "$item_id" | tail -n 1)"

test -f "$workspace_dir/.pi-env/coordination/$closed_path"
grep -q '^status: closed$' "$workspace_dir/.pi-env/coordination/$closed_path"
grep -q '^closed: 20' "$workspace_dir/.pi-env/coordination/$closed_path"
grep -q '^reviewed: true$' "$workspace_dir/.pi-env/coordination/$closed_path"
grep -q '^verified: true$' "$workspace_dir/.pi-env/coordination/$closed_path"
grep -q '^    type: closed$' "$workspace_dir/.pi-env/coordination/$closed_path"
grep -q '^      role: tester$' "$workspace_dir/.pi-env/coordination/$closed_path"
grep -q '^      Closed after review and verification\.$' "$workspace_dir/.pi-env/coordination/$closed_path"
test "$(git -C "$workspace_dir/.pi-env/coordination" log -1 --format='%an <%ae>|%cn <%ce>')" = \
  "tester-a/tester <tester-a+tester@coordination.local>|tester-a/tester <tester-a+tester@coordination.local>"

closed_issue_list="$(pi-env-coord-list --coord-dir "$workspace_dir/.pi-env/coordination" issues closed)"
printf '%s\n' "$closed_issue_list" \
  | grep -Eq "^$item_id[[:space:]]+closed[[:space:]]+Document pi config behavior$"

review_fail_path="$(pi-env-coord-new \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id agent-a \
  --role developer \
  "Review failure clears owner" | tail -n 1)"
review_fail_id="$(basename "$review_fail_path")"
review_fail_id="${review_fail_id%.yaml}"
pi-env-coord-claim \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id agent-a \
  --role developer \
  "$review_fail_id" >/dev/null
pi-env-coord-done \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id agent-a \
  --role developer \
  --result "Ready for failed review." \
  "$review_fail_id" >/dev/null
review_failed_path="$(pi-env-coord-review \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id reviewer-a \
  --role reviewer \
  --fail \
  --result "Needs more work." \
  "$review_fail_id" | tail -n 1)"

test "$review_failed_path" = "repos/pi-env/issues/open/$review_fail_id.yaml"
grep -q '^status: open$' "$workspace_dir/.pi-env/coordination/$review_failed_path"
grep -q '^owner: null$' "$workspace_dir/.pi-env/coordination/$review_failed_path"
grep -q '^done: null$' "$workspace_dir/.pi-env/coordination/$review_failed_path"
grep -q '^reviewed: false$' "$workspace_dir/.pi-env/coordination/$review_failed_path"
grep -q '^verified: false$' "$workspace_dir/.pi-env/coordination/$review_failed_path"
grep -q '^    type: review_failed$' \
  "$workspace_dir/.pi-env/coordination/$review_failed_path"

verify_fail_path="$(pi-env-coord-new \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id agent-a \
  --role developer \
  "Verification failure clears owner" | tail -n 1)"
verify_fail_id="$(basename "$verify_fail_path")"
verify_fail_id="${verify_fail_id%.yaml}"
pi-env-coord-claim \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id agent-a \
  --role developer \
  "$verify_fail_id" >/dev/null
pi-env-coord-done \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id agent-a \
  --role developer \
  --result "Ready for failed verification." \
  "$verify_fail_id" >/dev/null
pi-env-coord-review \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id reviewer-a \
  --role reviewer \
  --pass \
  --result "Review passed for verification failure test." \
  "$verify_fail_id" >/dev/null
verification_failed_path="$(PI_ENV_COORD_ROLE=tester pi-env-coord-verify \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --agent-id tester-a \
  --fail \
  --result "Needs more verification work." \
  "$verify_fail_id" | tail -n 1)"

test "$verification_failed_path" = "repos/pi-env/issues/open/$verify_fail_id.yaml"
grep -q '^status: open$' "$workspace_dir/.pi-env/coordination/$verification_failed_path"
grep -q '^owner: null$' "$workspace_dir/.pi-env/coordination/$verification_failed_path"
grep -q '^done: null$' "$workspace_dir/.pi-env/coordination/$verification_failed_path"
grep -q '^reviewed: false$' "$workspace_dir/.pi-env/coordination/$verification_failed_path"
grep -q '^verified: false$' "$workspace_dir/.pi-env/coordination/$verification_failed_path"
grep -q '^    type: verification_failed$' \
  "$workspace_dir/.pi-env/coordination/$verification_failed_path"

head_before="$(git -C "$workspace_dir/.pi-env/coordination" rev-parse HEAD)"
pi-env-coord-upgrade-rules \
  --coord-dir "$workspace_dir/.pi-env/coordination" \
  --preview >/dev/null
head_after="$(git -C "$workspace_dir/.pi-env/coordination" rev-parse HEAD)"
test "$head_before" = "$head_after"
test -z "$(git -C "$workspace_dir/.pi-env/coordination" status --short)"

printf 'agent coordination blackbox tests passed\n'
