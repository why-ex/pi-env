#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PI_ENV_COORD_LIB="$repo_root/scripts/pi-env-coord-lib.sh"
export PI_ENV_COORD_TEMPLATE_DIR="$repo_root/pi-skill-templates/agent-coordination"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
unset PI_ENV_COORD_REMOTE PI_ENV_COORD_WORKSPACE \
  PI_ENV_COORD_DIR PI_ENV_COORD_AGENT_ID PI_ENV_COORD_PROJECT PI_ENV_COORD_PROJECT_KEY PI_ENV_COORD_ROLE
mkdir -p "$HOME" "$tmp/project"
git config --global user.name "Coordination Test"
git config --global user.email "coordination-test@example.invalid"

cd "$tmp/project"
pi-env-coord-init \
  --root "$tmp/remotes" \
  --project pi-env \
  --agent-id agent-a \
  --dir .pi-env/coordination >/dev/null
export PI_ENV_COORD_REPO_ID=pi-env

item_path="$(pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type issue \
  "Lint item-matched tests" | tail -n 1)"
item_id="$(grep '^id: ' ".pi-env/coordination/$item_path" | sed 's/^id: //')"

grep -q '^testable: yes$' ".pi-env/coordination/$item_path"
cp ".pi-env/coordination/$item_path" "$tmp/item.clean.yaml"
printf 'issue_type: bug\n' >>".pi-env/coordination/$item_path"
if pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for legacy issue_type field\n' >&2
  exit 1
fi
cp "$tmp/item.clean.yaml" ".pi-env/coordination/$item_path"
case "$item_path" in
  repos/pi-env/issues/open/"$item_id".yaml) ;;
  *) printf 'unexpected item path: %s\n' "$item_path" >&2; exit 1 ;;
esac

if pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for missing item-matched test\n' >&2
  exit 1
fi

mkdir -p tests/items/issues
cat >"tests/items/issues/$item_id.sh" <<'EOF_TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'item-matched test placeholder passed\n'
EOF_TEST
chmod +x "tests/items/issues/$item_id.sh"

pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null

if pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . \
  --require-done-or-closed >/dev/null 2>&1; then
  printf 'expected done-or-closed lint to fail for open issue\n' >&2
  exit 1
fi

requirement_path="$(pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type functional-requirement \
  --testable no \
  --testability-note "Reviewed as a policy requirement." \
  "Lint functional requirement item" | tail -n 1)"
requirement_id="$(grep '^id: ' ".pi-env/coordination/$requirement_path" | sed 's/^id: //')"

case "$requirement_path" in
  requirements/"$requirement_id".yaml) ;;
  *) printf 'unexpected requirement path: %s\n' "$requirement_path" >&2; exit 1 ;;
esac
grep -q '^id: PIENV-FRQ-[0-9]\{8\}-[0-9]\{6\}-001$' \
  ".pi-env/coordination/$requirement_path"
grep -q '^status: active$' ".pi-env/coordination/$requirement_path"
grep -q '^body: |-$' ".pi-env/coordination/$requirement_path"
if grep -E '^(current|events|messages):' ".pi-env/coordination/$requirement_path" >/dev/null; then
  printf 'new requirement item should not contain embedded history\n' >&2
  exit 1
fi
cp ".pi-env/coordination/$requirement_path" "$tmp/requirement.clean.yaml"
printf 'current:\n  event: evt-0001\n  message: msg-0001\n' \
  >>".pi-env/coordination/$requirement_path"
if pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for requirement with embedded history\n' >&2
  exit 1
fi
cp "$tmp/requirement.clean.yaml" ".pi-env/coordination/$requirement_path"

todo_path="$(pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type todos \
  --testable no \
  --testability-note "Lint covers TODO single-body records." \
  "Lint TODO item" | tail -n 1)"
todo_id="$(grep '^id: ' ".pi-env/coordination/$todo_path" | sed 's/^id: //')"
case "$todo_path" in
  todos/"$todo_id".yaml) ;;
  *) printf 'unexpected todo path: %s\n' "$todo_path" >&2; exit 1 ;;
esac
grep -q '^id: PIENV-TODO-[0-9]\{8\}-[0-9]\{6\}-001$' \
  ".pi-env/coordination/$todo_path"
grep -q '^type: todo$' ".pi-env/coordination/$todo_path"
grep -q '^body: |-$' ".pi-env/coordination/$todo_path"
if grep -E '^(current|events|messages):' ".pi-env/coordination/$todo_path" >/dev/null; then
  printf 'new todo item should not contain embedded history\n' >&2
  exit 1
fi
cp ".pi-env/coordination/$todo_path" "$tmp/todo.clean.yaml"
printf 'events:\n  - id: evt-0001\n' >>".pi-env/coordination/$todo_path"
if pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for todo with embedded history\n' >&2
  exit 1
fi
cp "$tmp/todo.clean.yaml" ".pi-env/coordination/$todo_path"

quality_requirement_path="$(pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type quality \
  --testable no \
  --testability-note "Reviewed as a quality requirement." \
  "Lint quality requirement item" | tail -n 1)"
imported_requirement_path="$(pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type quality \
  --testable no \
  --testability-note "Imported from REQUIREMENTS.md; reviewed as policy." \
  "Lint imported quality requirement" | tail -n 1)"
if pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for imported requirement without source_refs\n' >&2
  exit 1
fi
printf 'source_refs:\n  - "REQUIREMENTS.md#lint-imported-quality-requirement"\n' \
  >>".pi-env/coordination/$imported_requirement_path"
imported_note_requirement_path="$(pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type functional-requirement \
  --testable no \
  --testability-note "Imported requirement is review-only for now." \
  "Lint imported note wording" | tail -n 1)"
if pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for imported requirement note without source_refs\n' >&2
  exit 1
fi
printf 'source_refs:\n  - "USE_CASES.md#lint-imported-note-wording"\n' \
  >>".pi-env/coordination/$imported_note_requirement_path"
constraint_requirement_path="$(pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type constraint \
  --testable no \
  --testability-note "Reviewed as a constraint requirement." \
  "Lint constraint requirement item" | tail -n 1)"
if pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --type requirement \
  --testable no \
  --testability-note "Legacy requirement compatibility check." \
  "Lint legacy requirement item" >/dev/null 2>"$tmp/legacy-requirement.err"; then
  printf 'expected generic requirement creation to fail\n' >&2
  exit 1
fi
grep -q 'generic requirement items have been removed' "$tmp/legacy-requirement.err"

grep -q '^id: PIENV-QRQ-[0-9]\{8\}-[0-9]\{6\}-001$' \
  ".pi-env/coordination/$quality_requirement_path"
grep -q '^id: PIENV-QRQ-[0-9]\{8\}-[0-9]\{6\}-[0-9]\{3\}$' \
  ".pi-env/coordination/$imported_requirement_path"
grep -q '^id: PIENV-CRQ-[0-9]\{8\}-[0-9]\{6\}-001$' \
  ".pi-env/coordination/$constraint_requirement_path"

pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null

mkdir -p designs scripts
ln -sf "$repo_root/scripts/pi-env-coord-generate-requirements-coverage" \
  scripts/pi-env-coord-generate-requirements-coverage
requirement_key="$(grep '^requirement_key: ' ".pi-env/coordination/$requirement_path" | sed 's/^requirement_key: //')"
cat >designs/lint-coverage.md <<EOF_DESIGN
# Lint coverage

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| $requirement_key | $requirement_id |
EOF_DESIGN
pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null
sed -i "s/$requirement_id/PIENV-FRQ-20260614-000000-999/" designs/lint-coverage.md
if pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for stale design Covers item ID\n' >&2
  exit 1
fi
sed -i "s/PIENV-FRQ-20260614-000000-999/$requirement_id/" designs/lint-coverage.md

cat >tests/items/issues/ORPHAN-ISS-20260607-204155-001.sh <<'EOF_TEST'
#!/usr/bin/env bash
set -euo pipefail
EOF_TEST
chmod +x tests/items/issues/ORPHAN-ISS-20260607-204155-001.sh

if pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for orphan item-matched test\n' >&2
  exit 1
fi

rm tests/items/issues/ORPHAN-ISS-20260607-204155-001.sh
chmod -x "tests/items/issues/$item_id.sh"

if pi-env-coord-lint \
  --coord-dir .pi-env/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for non-executable item-matched test\n' >&2
  exit 1
fi

printf 'agent coordination lint tests passed\n'
