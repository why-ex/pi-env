#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

bootstrap=scripts/pi-en-bootstrap-coordination
coord_init=scripts/pi-en-coord-init
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

export GIT_AUTHOR_NAME='pi-en test'
export GIT_AUTHOR_EMAIL='pi-en-test@example.invalid'
export GIT_COMMITTER_NAME='pi-en test'
export GIT_COMMITTER_EMAIL='pi-en-test@example.invalid'

coord_remote="$tmpdir/domain.git"
seed_clone="$tmpdir/seed-coord"
impl_origin="$tmpdir/frontend.git"
mkdir -p "$tmpdir"
git init --bare --initial-branch=main "$impl_origin" >/dev/null 2>&1 \
  || git init --bare "$impl_origin" >/dev/null

# Seed an existing coordination domain so bootstrap must attach to it rather
# than scaffold a new one for an unregistered implementation repo.
env -u PI_EN_COORD_REMOTE -u PI_EN_COORD_DIR -u PI_EN_COORD_PROJECT \
  -u PI_EN_COORD_PROJECT_KEY -u PI_EN_COORD_REPO_ID \
  bash "$coord_init" --remote "$coord_remote" --project domain \
    --project-key DOMAIN --repo-id seed --dir "$seed_clone" --agent-id tester

impl="$tmpdir/frontend-work"
mkdir -p "$impl"
git -C "$impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$impl" init >/dev/null
git -C "$impl" remote add origin "$impl_origin"

# Dry-run/print-only reports attachment details and leaves project/coordination
# paths untouched.
dry_out="$tmpdir/dry.out"
env -u PI_EN_COORD_REMOTE -u PI_EN_COORD_DIR -u PI_EN_COORD_PROJECT \
  -u PI_EN_COORD_PROJECT_KEY -u PI_EN_COORD_REPO_ID \
  bash "$bootstrap" --project-root "$impl" --remote "$coord_remote" \
    --project domain --project-key DOMAIN --repo-id frontend \
    --dir "$impl/.pi-en/coordination" --dry-run >"$dry_out"
test_grep 'Implementation repo id:      frontend' "$dry_out"
test_grep "Implementation repo remote:  $impl_origin" "$dry_out"
[ ! -e "$impl/.pi-en/coordination" ] || test_fail 'dry-run should not clone coordination repo'
[ ! -e "$impl/.pi-en-coordination.yaml" ] || test_fail 'dry-run should not write implementation config'

# Without --register-repo, attach locally and print an actionable diagnostic,
# but do not create a shared repo namespace.
attach_out="$tmpdir/attach.out"
env -u PI_EN_COORD_REMOTE -u PI_EN_COORD_DIR -u PI_EN_COORD_PROJECT \
  -u PI_EN_COORD_PROJECT_KEY -u PI_EN_COORD_REPO_ID \
  bash "$bootstrap" --project-root "$impl" --remote "$coord_remote" \
    --project domain --project-key DOMAIN --repo-id frontend \
    --dir "$impl/.pi-en/coordination" --no-status >"$attach_out" 2>&1
test_file_exists "$impl/.pi-en-coordination.yaml"
test_grep 'coordination_remote:' "$impl/.pi-en-coordination.yaml"
test_grep 'repo_id: frontend' "$impl/.pi-en-coordination.yaml"
test_grep 'rerun bootstrap with --register-repo' "$attach_out"
[ ! -e "$impl/.pi-en/coordination/repos/frontend/REPO.md" ] \
  || test_fail 'bootstrap without --register-repo should not register missing repo'

# Explicit registration creates and pushes the manifest and issue directories,
# recording the implementation remote.
env -u PI_EN_COORD_REMOTE -u PI_EN_COORD_DIR -u PI_EN_COORD_PROJECT \
  -u PI_EN_COORD_PROJECT_KEY -u PI_EN_COORD_REPO_ID \
  bash "$bootstrap" --project-root "$impl" --remote "$coord_remote" \
    --project domain --project-key DOMAIN --repo-id frontend \
    --implementation-remote "ssh://example.invalid/frontend.git" \
    --dir "$impl/.pi-en/coordination" --register-repo --no-status
manifest="$impl/.pi-en/coordination/repos/frontend/REPO.md"
test_file_exists "$manifest"
test_grep 'repo_id: frontend' "$manifest"
test_grep 'ssh://example.invalid/frontend.git' "$manifest"
for state in open blocked done closed; do
  test_dir_exists "$impl/.pi-en/coordination/repos/frontend/issues/$state"
  test_file_exists "$impl/.pi-en/coordination/repos/frontend/issues/$state/.gitkeep"
done
pushed_clone="$tmpdir/pushed-check"
git clone "$coord_remote" "$pushed_clone" >/dev/null 2>&1
test_file_exists "$pushed_clone/repos/frontend/REPO.md"
test_file_exists "$pushed_clone/repos/frontend/issues/open/.gitkeep"

# Brand-new coordination domains seeded by bootstrap still record explicit
# implementation remotes when --register-repo is requested.
fresh_remote="$tmpdir/fresh-domain.git"
fresh_impl="$tmpdir/fresh-frontend-work"
mkdir -p "$fresh_impl"
git -C "$fresh_impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$fresh_impl" init >/dev/null
env -u PI_EN_COORD_REMOTE -u PI_EN_COORD_DIR -u PI_EN_COORD_PROJECT \
  -u PI_EN_COORD_PROJECT_KEY -u PI_EN_COORD_REPO_ID \
  bash "$bootstrap" --project-root "$fresh_impl" --remote "$fresh_remote" \
    --project freshdomain --project-key FRESH --repo-id frontend \
    --implementation-remote "ssh://example.invalid/fresh-frontend.git" \
    --dir "$fresh_impl/.pi-en/coordination" --register-repo --no-status
fresh_manifest="$fresh_impl/.pi-en/coordination/repos/frontend/REPO.md"
test_file_exists "$fresh_manifest"
test_grep 'ssh://example.invalid/fresh-frontend.git' "$fresh_manifest"
fresh_pushed="$tmpdir/fresh-pushed-check"
git clone "$fresh_remote" "$fresh_pushed" >/dev/null 2>&1
test_grep 'ssh://example.invalid/fresh-frontend.git' \
  "$fresh_pushed/repos/frontend/REPO.md"

# Existing active registrations are detected without an extra commit.
before_head="$(git -C "$impl/.pi-en/coordination" rev-parse HEAD)"
env -u PI_EN_COORD_REMOTE -u PI_EN_COORD_DIR -u PI_EN_COORD_PROJECT \
  -u PI_EN_COORD_PROJECT_KEY -u PI_EN_COORD_REPO_ID \
  bash "$bootstrap" --project-root "$impl" --remote "$coord_remote" \
    --project domain --project-key DOMAIN --repo-id frontend \
    --dir "$impl/.pi-en/coordination" --register-repo --no-status
after_head="$(git -C "$impl/.pi-en/coordination" rev-parse HEAD)"
test_eq "$before_head" "$after_head" 'existing registration should not create a duplicate commit'

# Alias and retired matches fail explicitly rather than creating/reactivating.
awk '{ if ($0 == "aliases: []") { print "aliases:"; print "  - front" } else print }' \
  "$manifest" >"$manifest.tmp"
mv "$manifest.tmp" "$manifest"
(
  cd "$impl/.pi-en/coordination"
  git add repos/frontend/REPO.md
  git commit -m 'Add frontend alias for bootstrap test' >/dev/null
  git push origin HEAD >/dev/null
)
alias_err="$tmpdir/alias.err"
set +e
env -u PI_EN_COORD_REMOTE -u PI_EN_COORD_DIR -u PI_EN_COORD_PROJECT \
  -u PI_EN_COORD_PROJECT_KEY -u PI_EN_COORD_REPO_ID \
  bash "$bootstrap" --project-root "$impl" --remote "$coord_remote" \
    --project domain --project-key DOMAIN --repo-id front \
    --dir "$impl/.pi-en/coordination" --register-repo --no-status \
    >"$tmpdir/alias.out" 2>"$alias_err"
alias_status=$?
set -e
[ "$alias_status" -ne 0 ] || test_fail 'alias repo id should fail bootstrap registration'
test_grep "alias for 'frontend'" "$alias_err"

(
  cd "$impl/.pi-en/coordination"
  mkdir -p repos/retiredrepo/issues/open repos/retiredrepo/issues/blocked \
    repos/retiredrepo/issues/done repos/retiredrepo/issues/closed
  find repos/retiredrepo/issues -type d -empty -exec sh -c 'touch "$1/.gitkeep"' sh {} \;
  cat >repos/retiredrepo/REPO.md <<'EOF_RETIRED'
---
repo_id: retiredrepo
status: retired
item_key: RETIREDREPO
project: retiredrepo
created: 2026-07-13T00:00:00Z
updated: 2026-07-13T00:00:00Z
aliases: []
remotes: []
domain_generated_files: []
---

# retiredrepo
EOF_RETIRED
  git add repos/retiredrepo
  git commit -m 'Add retired repo for bootstrap test' >/dev/null
  git push origin HEAD >/dev/null
)
retired_err="$tmpdir/retired.err"
set +e
env -u PI_EN_COORD_REMOTE -u PI_EN_COORD_DIR -u PI_EN_COORD_PROJECT \
  -u PI_EN_COORD_PROJECT_KEY -u PI_EN_COORD_REPO_ID \
  bash "$bootstrap" --project-root "$impl" --remote "$coord_remote" \
    --project domain --project-key DOMAIN --repo-id retiredrepo \
    --dir "$impl/.pi-en/coordination" --register-repo --no-status \
    >"$tmpdir/retired.out" 2>"$retired_err"
retired_status=$?
set -e
[ "$retired_status" -ne 0 ] || test_fail 'retired repo id should fail bootstrap registration'
test_grep 'retired as canonical repo' "$retired_err"

test_note 'bootstrap implementation repo attachment and registration are covered'
