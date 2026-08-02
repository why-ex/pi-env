#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PI_ENV_COORD_LIB="$repo_root/scripts/pi-env-coord-lib.sh"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"

unset PI_ENV_COORD_REMOTE PI_ENV_COORD_WORKSPACE \
  PI_ENV_COORD_DIR PI_ENV_COORD_AGENT_ID PI_ENV_COORD_PROJECT PI_ENV_COORD_PROJECT_KEY PI_ENV_COORD_ROLE

git config --global user.name "Coordination Test"
git config --global user.email "coordination-test@example.invalid"

project_root="$tmp/project"
coord_dir="$project_root/.pi-env/coordination"
mkdir -p "$coord_dir" "$project_root/tests/items/issues" "$project_root/.pi-env" "$project_root/designs"
git -C "$coord_dir" init -q
cat >"$coord_dir/PROJECT.md" <<'EOF_PROJECT'
---
project: root-demo
item_key: ROOTDEMO
created: 2026-01-01T00:00:00Z
---

# Root Demo
EOF_PROJECT
mkdir -p \
  "$coord_dir/issues/open" \
  "$coord_dir/issues/blocked" \
  "$coord_dir/issues/done" \
  "$coord_dir/issues/closed" \
  "$coord_dir/requirements" \
  "$coord_dir/decisions" \
  "$coord_dir/notes"
git -C "$coord_dir" add -A
git -C "$coord_dir" commit -q -m "Initialize root layout"

issue_path="$(pi-env-coord-new \
  --coord-dir "$coord_dir" \
  --agent-id agent-a \
  --role architect \
  "Project-local root layout issue" | tail -n 1)"
case "$issue_path" in
  issues/open/ROOTDEMO-ISS-*.yaml) ;;
  *) printf 'unexpected project-local issue path: %s\n' "$issue_path" >&2; exit 1 ;;
esac
issue_id="$(basename "$issue_path" .yaml)"
grep -q '^project: root-demo$' "$coord_dir/$issue_path"
grep -q "^$issue_id[[:space:]]\+open[[:space:]]\+Project-local root layout issue$" \
  <(pi-env-coord-list --coord-dir "$coord_dir" issues open)
pi-env-coord-cat --coord-dir "$coord_dir" "$issue_id" | grep -q "^title: 'Project-local root layout issue'$"
pi-env-coord-status --coord-dir "$coord_dir" | grep -q "$issue_id"

env_issue_path="$(PI_ENV_COORD_PROJECT=env-project pi-env-coord-new \
  --coord-dir "$coord_dir" \
  --testable no \
  --testability-note "Project-local layout should ignore PI_ENV_COORD_PROJECT for paths." \
  "Project-local root layout env issue" | tail -n 1)"
case "$env_issue_path" in
  issues/open/ROOTDEMO-ISS-*.yaml) ;;
  *) printf 'unexpected env project-local issue path: %s\n' "$env_issue_path" >&2; exit 1 ;;
esac
test ! -e "$coord_dir/projects/env-project"

cat >"$project_root/tests/items/issues/$issue_id.sh" <<'EOF_TEST'
#!/usr/bin/env bash
set -euo pipefail
true
EOF_TEST
chmod +x "$project_root/tests/items/issues/$issue_id.sh"

pi-env-coord-claim --coord-dir "$coord_dir" --agent-id agent-a --role developer --no-pull --no-push "$issue_id" >/dev/null
pi-env-coord-done --coord-dir "$coord_dir" --agent-id agent-a --role developer --no-pull --no-push "$issue_id" >/dev/null
pi-env-coord-review --coord-dir "$coord_dir" --agent-id reviewer --role reviewer --no-pull --no-push --pass "$issue_id" >/dev/null
pi-env-coord-verify --coord-dir "$coord_dir" --agent-id verifier --role verifier --no-pull --no-push --pass "$issue_id" >/dev/null
pi-env-coord-close --coord-dir "$coord_dir" --agent-id closer --role maintainer --no-pull --no-push "$issue_id" >/dev/null

test -f "$coord_dir/issues/closed/$issue_id.yaml"
grep -q '^status: closed$' "$coord_dir/issues/closed/$issue_id.yaml"
pi-env-coord-list --coord-dir "$coord_dir" issues closed | grep -q "^$issue_id"

requirement_path="$(pi-env-coord-new \
  --coord-dir "$coord_dir" \
  --type functional \
  --testable no \
  --testability-note "Rendered by root layout test." \
  "Project-local root layout requirement" | tail -n 1)"
case "$requirement_path" in
  requirements/ROOTDEMO-FRQ-*.yaml) ;;
  *) printf 'unexpected project-local requirement path: %s\n' "$requirement_path" >&2; exit 1 ;;
esac
requirement_id="$(basename "$requirement_path" .yaml)"

pi-env-coord-generate-requirements \
  --coordination-dir "$coord_dir" \
  --project root-demo | grep -q 'Project-local root layout requirement'

cat >"$project_root/designs/root.md" <<EOF_DESIGN
# Root design

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| $requirement_id | $requirement_id |
EOF_DESIGN
pi-env-coord-generate-requirements-coverage \
  --coordination-dir "$coord_dir" \
  --project root-demo \
  --designs-dir "$project_root/designs" \
  --check

pi-env-coord-lint --coord-dir "$coord_dir" --project-root "$project_root"
