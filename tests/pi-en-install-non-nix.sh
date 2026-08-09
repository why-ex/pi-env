#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
workdir="$(mktemp -d)"
cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

assert_file() {
  local path="$1"
  [ -f "$path" ] || { echo "missing expected file: $path" >&2; exit 1; }
}

# Local payload installs must work without remote bootstrap options or network.
local_prefix="$workdir/local-prefix"
mkdir -p "$local_prefix/bin"
stale_commands=(
  pi-start
  pi-bwrap
  bootstrap-coordination
  agent-coord-repo
  agent-coord-generate-requirements-coverage
  pi-serial-roles
  install-non-nix
)
for stale_command in "${stale_commands[@]}"; do
  printf 'stale legacy wrapper\n' > "$local_prefix/bin/$stale_command"
done
"$repo_root/scripts/pi-en-install-non-nix" --prefix "$local_prefix"
assert_file "$local_prefix/bin/pien"
"$local_prefix/bin/pien" help >/dev/null
"$local_prefix/bin/pien" completion bash | grep -q 'complete -F _pien pien'
assert_file "$local_prefix/bin/pi-en"
assert_file "$local_prefix/bin/pi-en-bwrap"
assert_file "$local_prefix/bin/pi-en-serial-roles"
assert_file "$local_prefix/bin/pi-en-install-non-nix"
assert_file "$local_prefix/bin/pi-en-update"
"$local_prefix/bin/pi-en-update" --help | grep -q 'pi-en-update - update a non-Nix Pi-en installation'
"$local_prefix/bin/pi-en-update" --help | grep -q -- '--artifact-url URL'
PI_EN_INSIDE_SANDBOX=0 "$local_prefix/bin/pien" update --help | grep -q 'pi-en-update - update a non-Nix Pi-en installation'
PI_EN_INSIDE_SANDBOX=0 "$local_prefix/bin/pien" update --help | grep -q -- '--url URL'
assert_file "$local_prefix/bin/pi-en-coord-repo"
assert_file "$local_prefix/share/pi-en/install-manifest"
assert_file "$local_prefix/share/bash-completion/completions/pien"
grep -qx "$local_prefix/share/bash-completion/completions/pien" "$local_prefix/share/pi-en/install-manifest"
grep -qx "$local_prefix/bin/pi-en-update" "$local_prefix/share/pi-en/install-manifest"
for stale_command in "${stale_commands[@]}"; do
  [ ! -e "$local_prefix/bin/$stale_command" ] || {
    echo "stale $stale_command wrapper survived reinstall" >&2
    exit 1
  }
done
[ ! -f "$local_prefix/share/pi-en/install-origin" ] || {
  echo "local install unexpectedly wrote remote origin metadata" >&2
  exit 1
}

# Build an archive-style payload and run a detached installer copy so no local
# payload can be discovered beside the script.
archive_root="$workdir/archive-root/pi-en-main"
mkdir -p "$archive_root"
cp -R "$repo_root/scripts" "$archive_root/scripts"
cp -R "$repo_root/role-manager" "$archive_root/role-manager"
cp -R "$repo_root/pi-skill-templates" "$archive_root/pi-skill-templates"
archive="$workdir/pi-en-main.tar.gz"
tar -czf "$archive" -C "$workdir/archive-root" pi-en-main

"$local_prefix/bin/pi-en-update" --artifact-url "file://$archive" >/dev/null
assert_file "$local_prefix/share/pi-en/install-origin"
grep -qx 'source=archive' "$local_prefix/share/pi-en/install-origin"
grep -qx "artifact_url=file://$archive" "$local_prefix/share/pi-en/install-origin"

remote_script_dir="$workdir/remote-script"
mkdir -p "$remote_script_dir"
cp "$repo_root/scripts/pi-en-install-non-nix" "$remote_script_dir/pi-en-install-non-nix"
remote_prefix="$workdir/remote-prefix"
(
  cd "$workdir"
  "$remote_script_dir/pi-en-install-non-nix" \
    --prefix "$remote_prefix" \
    --ref main \
    --repo test-owner/test-repo \
    --artifact-url "file://$archive"
)

assert_file "$remote_prefix/bin/pien"
assert_file "$remote_prefix/bin/pi-en"
assert_file "$remote_prefix/bin/pi-en-bwrap"
assert_file "$remote_prefix/bin/pi-en-serial-roles"
assert_file "$remote_prefix/bin/pi-en-install-non-nix"
assert_file "$remote_prefix/bin/pi-en-update"
assert_file "$remote_prefix/bin/pi-en-coord-repo"
assert_file "$remote_prefix/share/pi-en/install-origin"
assert_file "$remote_prefix/share/bash-completion/completions/pien"
grep -qx 'source=archive' "$remote_prefix/share/pi-en/install-origin"
grep -qx 'repository=test-owner/test-repo' "$remote_prefix/share/pi-en/install-origin"
grep -qx 'requested_ref=main' "$remote_prefix/share/pi-en/install-origin"
grep -qx 'ref=main' "$remote_prefix/share/pi-en/install-origin"
grep -qx "artifact_url=file://$archive" "$remote_prefix/share/pi-en/install-origin"
grep -q '^sha256=' "$remote_prefix/share/pi-en/install-origin"
grep -qx "$remote_prefix/share/pi-en/install-origin" "$remote_prefix/share/pi-en/install-manifest"
grep -qx "$remote_prefix/bin/pi-en-update" "$remote_prefix/share/pi-en/install-manifest"

# Git-source installs must persist reusable update origin metadata.
git_source="$workdir/git-source"
mkdir -p "$git_source"
cp -R "$repo_root/scripts" "$git_source/scripts"
cp -R "$repo_root/role-manager" "$git_source/role-manager"
cp -R "$repo_root/pi-skill-templates" "$git_source/pi-skill-templates"
git -C "$git_source" init -q
git -C "$git_source" config user.email pi-en-test@example.invalid
git -C "$git_source" config user.name 'Pi-en Test'
git -C "$git_source" add .
git -C "$git_source" commit -q -m 'Initial test payload'
git -C "$git_source" branch -M main
git -C "$git_source" checkout -q -b feature
git -C "$git_source" commit -q --allow-empty -m 'Feature test payload'
git -C "$git_source" checkout -q main
git_main_commit="$(git -C "$git_source" rev-parse main)"
git_feature_commit="$(git -C "$git_source" rev-parse feature)"

git_prefix="$workdir/git-prefix"
(
  cd "$workdir"
  "$remote_script_dir/pi-en-install-non-nix" \
    --prefix "$git_prefix" \
    --url "$git_source" \
    --ref main
)
assert_file "$git_prefix/bin/pi-en-update"
assert_file "$git_prefix/share/pi-en/install-origin"
grep -qx 'source=git' "$git_prefix/share/pi-en/install-origin"
grep -qx "url=$git_source" "$git_prefix/share/pi-en/install-origin"
grep -qx 'requested_ref=main' "$git_prefix/share/pi-en/install-origin"
grep -qx 'resolved_ref_type=branch' "$git_prefix/share/pi-en/install-origin"
grep -qx "resolved_commit=$git_main_commit" "$git_prefix/share/pi-en/install-origin"
grep -qx "$git_prefix/bin/pi-en-update" "$git_prefix/share/pi-en/install-manifest"
grep -qx "$git_prefix/share/pi-en/install-origin" "$git_prefix/share/pi-en/install-manifest"
"$git_prefix/bin/pi-en-update" >/dev/null
grep -qx "resolved_commit=$git_main_commit" "$git_prefix/share/pi-en/install-origin"
"$git_prefix/bin/pi-en-update" --ref feature >/dev/null
grep -qx 'requested_ref=feature' "$git_prefix/share/pi-en/install-origin"
grep -qx "resolved_commit=$git_feature_commit" "$git_prefix/share/pi-en/install-origin"

# Uninstall must be driven by installed state only. Remove source/archive inputs
# before invoking the installed wrapper.
rm -rf "$remote_script_dir" "$archive" "$archive_root"
"$remote_prefix/bin/pi-en-uninstall"
[ ! -e "$remote_prefix/bin/pien" ] || {
  echo "pien wrapper survived uninstall" >&2
  exit 1
}
[ ! -e "$remote_prefix/bin/pi-en" ] || {
  echo "pi-en wrapper survived uninstall" >&2
  exit 1
}
[ ! -e "$remote_prefix/share/pi-en/install-origin" ] || {
  echo "origin metadata survived uninstall" >&2
  exit 1
}
[ ! -e "$remote_prefix/bin/pi-en-update" ] || {
  echo "pi-en-update wrapper survived uninstall" >&2
  exit 1
}
[ ! -e "$remote_prefix/share/bash-completion/completions/pien" ] || {
  echo "pien bash completion survived uninstall" >&2
  exit 1
}

printf 'pi-en-install-non-nix tests passed\n'
