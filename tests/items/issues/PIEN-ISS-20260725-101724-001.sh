#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

bootstrap=scripts/pi-en-bootstrap-coordination
init=scripts/pi-en-coord-init
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

unset PI_EN_COORD_REMOTE PI_EN_COORD_DIR PI_EN_COORD_PROJECT \
  PI_EN_COORD_PROJECT_KEY PI_EN_COORD_REPO_ID PI_EN_COORD_WORKSPACE

export GIT_AUTHOR_NAME="pi-en test"
export GIT_AUTHOR_EMAIL="pi-en-test@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

help_out="$tmpdir/bootstrap.help"
bash "$bootstrap" --help >"$help_out"
test_grep '--domain-generated-file PATH' "$help_out"
test_grep 'repos/<repo_id>/REPO.md domain_generated_files' "$help_out"

fresh_impl="$tmpdir/fresh-impl"
mkdir -p "$fresh_impl"
git -C "$fresh_impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$fresh_impl" init >/dev/null
bash "$bootstrap" \
  --project-root "$fresh_impl" \
  --root "$tmpdir/fresh-remotes" \
  --repo-id app \
  --domain-generated-file REQUIREMENTS.md \
  --domain-generated-file REQUIREMENTS.md \
  --domain-generated-file generated/DOMAIN.yaml \
  --agent-id agent-domain \
  --no-status >/dev/null
fresh_manifest="$fresh_impl/.pi-en/coordination/repos/app/REPO.md"
test_grep '^domain_generated_files:$' "$fresh_manifest"
test_grep '^  - REQUIREMENTS.md$' "$fresh_manifest"
test_grep '^  - generated/DOMAIN.yaml$' "$fresh_manifest"
test_eq 1 "$(grep -c '^  - REQUIREMENTS.md$' "$fresh_manifest")" \
  'duplicate generated file entries should be removed'

existing_impl="$tmpdir/existing-impl"
mkdir -p "$existing_impl"
git -C "$existing_impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$existing_impl" init >/dev/null
remote="$tmpdir/existing-domain.git"
coord_dir="$existing_impl/.pi-en/coordination"
bash "$init" --remote "$remote" --project domain --repo-id api \
  --agent-id agent-domain --dir "$coord_dir" >/dev/null
before_head="$(git -C "$coord_dir" rev-parse HEAD)"
bash "$bootstrap" --project-root "$existing_impl" --remote "$remote" \
  --repo-id api --domain-generated-file REQUIREMENTS.md \
  --domain-generated-file REQUIREMENTS_COVERAGE.md \
  --agent-id agent-domain --no-status >/dev/null
after_head="$(git -C "$coord_dir" rev-parse HEAD)"
[ "$before_head" != "$after_head" ] || test_fail 'expected existing manifest update commit'
test_eq "$after_head" "$(git --git-dir="$remote" rev-parse main)" \
  'existing manifest update should be pushed'
existing_manifest="$coord_dir/repos/api/REPO.md"
test_grep '^  - REQUIREMENTS.md$' "$existing_manifest"
test_grep '^  - REQUIREMENTS_COVERAGE.md$' "$existing_manifest"

dry_impl="$tmpdir/dry-impl"
mkdir -p "$dry_impl"
git -C "$dry_impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$dry_impl" init >/dev/null
bash "$bootstrap" --project-root "$dry_impl" --root "$tmpdir/dry-remotes" \
  --repo-id dry --domain-generated-file REQUIREMENTS.md --dry-run \
  >"$tmpdir/dry-plan.txt"
test_grep 'Domain generated files:      REQUIREMENTS.md' "$tmpdir/dry-plan.txt"
test ! -e "$dry_impl/.pi-en/coordination" || test_fail 'dry run created coordination clone'
test ! -e "$tmpdir/dry-remotes" || test_fail 'dry run created remote root'

for bad in '' /absolute ../escape nested/../escape; do
  if bash "$bootstrap" --project-root "$dry_impl" --repo-id dry \
    --domain-generated-file "$bad" --dry-run >"$tmpdir/bad.out" 2>"$tmpdir/bad.err"; then
    test_fail "invalid generated-file path was accepted: '$bad'"
  fi
done

missing_impl="$tmpdir/missing-impl"
mkdir -p "$missing_impl"
git -C "$missing_impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$missing_impl" init >/dev/null
missing_remote="$tmpdir/missing-domain.git"
missing_coord="$missing_impl/.pi-en/coordination"
bash "$init" --remote "$missing_remote" --project domain --repo-id core \
  --agent-id agent-domain --dir "$missing_coord" >/dev/null
bash "$bootstrap" --project-root "$missing_impl" --remote "$missing_remote" \
  --repo-id missing --domain-generated-file REQUIREMENTS.md \
  --agent-id agent-domain --no-status >"$tmpdir/missing.out" 2>&1

test ! -e "$missing_coord/repos/missing" || \
  test_fail 'missing repo was created without --register-repo'
test_grep 'rerun bootstrap with --register-repo' "$tmpdir/missing.out"

register_impl="$tmpdir/register-impl"
mkdir -p "$register_impl"
git -C "$register_impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$register_impl" init >/dev/null
register_remote="$tmpdir/register-domain.git"
register_coord="$register_impl/.pi-en/coordination"
bash "$init" --remote "$register_remote" --project domain --repo-id core \
  --agent-id agent-domain --dir "$register_coord" >/dev/null
bash "$bootstrap" --project-root "$register_impl" --remote "$register_remote" \
  --repo-id addon --register-repo --domain-generated-file REQUIREMENTS.md \
  --agent-id agent-domain --no-status >/dev/null
register_manifest="$register_coord/repos/addon/REPO.md"
test_file_exists "$register_manifest"
test_grep '^  - REQUIREMENTS.md$' "$register_manifest"
test_eq "$(git -C "$register_coord" rev-parse HEAD)" \
  "$(git --git-dir="$register_remote" rev-parse main)" \
  'registration manifest update should be pushed'

test_note 'bootstrap domain-generated-file behavior is covered'
