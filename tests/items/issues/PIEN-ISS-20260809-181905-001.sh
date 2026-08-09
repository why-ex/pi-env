#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

assert_file() {
  local path="$1"
  [ -f "$path" ] || { echo "missing expected file: $path" >&2; exit 1; }
}

make_source_repo() {
  local source_dir="$1"
  mkdir -p "$source_dir"
  cp -R "$repo_root/scripts" "$source_dir/scripts"
  cp -R "$repo_root/role-manager" "$source_dir/role-manager"
  cp -R "$repo_root/pi-skill-templates" "$source_dir/pi-skill-templates"
  git -C "$source_dir" init -q -b main
  git -C "$source_dir" config user.email test@example.invalid
  git -C "$source_dir" config user.name 'pi-en test'
  git -C "$source_dir" add .
  git -C "$source_dir" commit -q -m 'initial source'
}

run_detached_installer() {
  local tmpbase="$1"
  shift
  local script_dir="$workdir/detached-script-$RANDOM"
  mkdir -p "$script_dir" "$tmpbase"
  cp "$repo_root/scripts/pi-en-install-non-nix" "$script_dir/pi-en-install-non-nix"
  TMPDIR="$tmpbase" "$script_dir/pi-en-install-non-nix" "$@"
}

source_repo="$workdir/source repo"
make_source_repo "$source_repo"
main_commit="$(git -C "$source_repo" rev-parse HEAD)"
git -C "$source_repo" tag v1

git -C "$source_repo" checkout -q -b side
printf 'side only\n' > "$source_repo/side-only.txt"
git -C "$source_repo" add side-only.txt
git -C "$source_repo" commit -q -m 'side commit'
side_commit="$(git -C "$source_repo" rev-parse HEAD)"
git -C "$source_repo" checkout -q main

git -C "$source_repo" branch same-name
git -C "$source_repo" tag same-name

branch_tmp="$workdir/tmp-branch"
branch_prefix="$workdir/prefix-branch"
run_detached_installer "$branch_tmp" --url "$source_repo" --ref main --prefix "$branch_prefix"
assert_file "$branch_prefix/bin/pien"
[ -z "$(find "$branch_tmp" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
  echo "temporary checkout survived branch install" >&2
  exit 1
}

tag_tmp="$workdir/tmp-tag"
tag_prefix="$workdir/prefix-tag"
run_detached_installer "$tag_tmp" --url "file://$source_repo" --ref v1 --prefix "$tag_prefix"
assert_file "$tag_prefix/bin/pi-en"
[ -z "$(find "$tag_tmp" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
  echo "temporary checkout survived tag install" >&2
  exit 1
}

commit_tmp="$workdir/tmp-commit"
commit_prefix="$workdir/prefix-commit"
run_detached_installer "$commit_tmp" --url "$source_repo" --ref "$main_commit@main" --prefix "$commit_prefix"
assert_file "$commit_prefix/bin/pi-en-install-non-nix"
[ -z "$(find "$commit_tmp" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
  echo "temporary checkout survived COMMIT@BRANCH install" >&2
  exit 1
}

ambiguous_tmp="$workdir/tmp-ambiguous"
ambiguous_err="$workdir/ambiguous.err"
if run_detached_installer "$ambiguous_tmp" --url "$source_repo" --ref same-name --prefix "$workdir/prefix-ambiguous" 2>"$ambiguous_err"; then
  echo "ambiguous branch/tag ref unexpectedly succeeded" >&2
  exit 1
fi
grep -q 'ambiguous ref' "$ambiguous_err"
[ -z "$(find "$ambiguous_tmp" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
  echo "temporary checkout survived ambiguous-ref failure" >&2
  exit 1
}

unreachable_tmp="$workdir/tmp-unreachable"
unreachable_err="$workdir/unreachable.err"
if run_detached_installer "$unreachable_tmp" --url "$source_repo" --ref "$side_commit@main" --prefix "$workdir/prefix-unreachable" 2>"$unreachable_err"; then
  echo "unreachable COMMIT@BRANCH unexpectedly succeeded" >&2
  exit 1
fi
grep -Eq 'not reachable from branch main|commit not found after fetching branch' "$unreachable_err"
[ -z "$(find "$unreachable_tmp" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
  echo "temporary checkout survived unreachable-commit failure" >&2
  exit 1
}

printf 'PIEN-ISS-20260809-181905-001 tests passed\n'
