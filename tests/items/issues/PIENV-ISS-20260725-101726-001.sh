#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

bootstrap=scripts/pi-env-bootstrap-coordination
init=scripts/pi-env-coord-init
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

unset PI_ENV_COORD_REMOTE PI_ENV_COORD_DIR PI_ENV_COORD_PROJECT \
  PI_ENV_COORD_PROJECT_KEY PI_ENV_COORD_REPO_ID PI_ENV_COORD_WORKSPACE

export GIT_AUTHOR_NAME="pi-env test"
export GIT_AUTHOR_EMAIL="pi-env-test@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

help_out="$tmpdir/bootstrap.help"
bash "$bootstrap" --help >"$help_out"
test_grep '--generated-requirements-docs' "$help_out"
test_grep '--domain-generated-file REQUIREMENTS.md' "$help_out"
test_grep '--domain-generated-file REQUIREMENTS_COVERAGE.md' "$help_out"

fresh_impl="$tmpdir/fresh-impl"
mkdir -p "$fresh_impl"
git -C "$fresh_impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$fresh_impl" init >/dev/null
bash "$bootstrap" \
  --project-root "$fresh_impl" \
  --root "$tmpdir/fresh-remotes" \
  --repo-id app \
  --generated-requirements-docs \
  --agent-id agent-domain \
  --no-status >/dev/null
fresh_manifest="$fresh_impl/.pi-env/coordination/repos/app/REPO.md"
test_grep '^domain_generated_files:$' "$fresh_manifest"
test_grep '^  - REQUIREMENTS.md$' "$fresh_manifest"
test_grep '^  - REQUIREMENTS_COVERAGE.md$' "$fresh_manifest"
test_eq 1 "$(grep -c '^  - REQUIREMENTS.md$' "$fresh_manifest")" \
  'alias-only duplicate REQUIREMENTS.md entries should be absent'
test_eq 1 "$(grep -c '^  - REQUIREMENTS_COVERAGE.md$' "$fresh_manifest")" \
  'alias-only duplicate REQUIREMENTS_COVERAGE.md entries should be absent'

existing_impl="$tmpdir/existing-impl"
mkdir -p "$existing_impl"
git -C "$existing_impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$existing_impl" init >/dev/null
remote="$tmpdir/existing-domain.git"
coord_dir="$existing_impl/.pi-env/coordination"
bash "$init" --remote "$remote" --project domain --repo-id api \
  --agent-id agent-domain --dir "$coord_dir" >/dev/null
before_head="$(git -C "$coord_dir" rev-parse HEAD)"
bash "$bootstrap" --project-root "$existing_impl" --remote "$remote" \
  --repo-id api --generated-requirements-docs \
  --domain-generated-file REQUIREMENTS.md \
  --domain-generated-file generated/DOMAIN.yaml \
  --agent-id agent-domain --no-status >/dev/null
after_head="$(git -C "$coord_dir" rev-parse HEAD)"
[ "$before_head" != "$after_head" ] || test_fail 'expected alias manifest update commit'
test_eq "$after_head" "$(git --git-dir="$remote" rev-parse main)" \
  'alias manifest update should be pushed'
existing_manifest="$coord_dir/repos/api/REPO.md"
test_grep '^  - REQUIREMENTS.md$' "$existing_manifest"
test_grep '^  - REQUIREMENTS_COVERAGE.md$' "$existing_manifest"
test_grep '^  - generated/DOMAIN.yaml$' "$existing_manifest"
test_eq 1 "$(grep -c '^  - REQUIREMENTS.md$' "$existing_manifest")" \
  'alias plus explicit duplicate should be removed'
req_line="$(grep -n '^  - REQUIREMENTS.md$' "$existing_manifest" | cut -d: -f1)"
coverage_line="$(grep -n '^  - REQUIREMENTS_COVERAGE.md$' "$existing_manifest" | cut -d: -f1)"
generated_line="$(grep -n '^  - generated/DOMAIN.yaml$' "$existing_manifest" | cut -d: -f1)"
[ "$req_line" -lt "$coverage_line" ] || test_fail 'alias order should place REQUIREMENTS.md first'
[ "$coverage_line" -lt "$generated_line" ] || test_fail 'explicit option after alias should remain last'

print_impl="$tmpdir/print-impl"
mkdir -p "$print_impl"
git -C "$print_impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$print_impl" init >/dev/null
bash "$bootstrap" --project-root "$print_impl" --root "$tmpdir/print-remotes" \
  --repo-id dry --generated-requirements-docs --dry-run \
  >"$tmpdir/print-plan.txt"
test_grep 'Domain generated files:      REQUIREMENTS.md REQUIREMENTS_COVERAGE.md' \
  "$tmpdir/print-plan.txt"
test ! -e "$print_impl/.pi-env/coordination" || test_fail 'dry run created coordination clone'
test ! -e "$tmpdir/print-remotes" || test_fail 'dry run created remote root'

missing_impl="$tmpdir/missing-impl"
mkdir -p "$missing_impl"
git -C "$missing_impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$missing_impl" init >/dev/null
missing_remote="$tmpdir/missing-domain.git"
missing_coord="$missing_impl/.pi-env/coordination"
bash "$init" --remote "$missing_remote" --project domain --repo-id core \
  --agent-id agent-domain --dir "$missing_coord" >/dev/null
before_missing="$(git -C "$missing_coord" rev-parse HEAD)"
bash "$bootstrap" --project-root "$missing_impl" --remote "$missing_remote" \
  --repo-id missing --generated-requirements-docs \
  --agent-id agent-domain --no-status >"$tmpdir/missing.out" 2>&1
after_missing="$(git -C "$missing_coord" rev-parse HEAD)"
test_eq "$before_missing" "$after_missing" \
  'alias should not mutate unregistered repo without --register-repo'
test ! -e "$missing_coord/repos/missing" || \
  test_fail 'alias created missing repo without --register-repo'
test_grep 'rerun bootstrap with --register-repo' "$tmpdir/missing.out"

test_note 'bootstrap generated-requirements-docs alias behavior is covered'
