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
assert_file "$local_prefix/bin/pi-en-coord-repo"
assert_file "$local_prefix/share/pi-en/install-manifest"
assert_file "$local_prefix/share/bash-completion/completions/pien"
grep -qx "$local_prefix/share/bash-completion/completions/pien" "$local_prefix/share/pi-en/install-manifest"
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
assert_file "$remote_prefix/bin/pi-en-coord-repo"
assert_file "$remote_prefix/share/pi-en/install-origin"
assert_file "$remote_prefix/share/bash-completion/completions/pien"
grep -qx 'repository=test-owner/test-repo' "$remote_prefix/share/pi-en/install-origin"
grep -qx 'ref=main' "$remote_prefix/share/pi-en/install-origin"
grep -qx "artifact_url=file://$archive" "$remote_prefix/share/pi-en/install-origin"
grep -q '^sha256=' "$remote_prefix/share/pi-en/install-origin"
grep -qx "$remote_prefix/share/pi-en/install-origin" "$remote_prefix/share/pi-en/install-manifest"

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
[ ! -e "$remote_prefix/share/bash-completion/completions/pien" ] || {
  echo "pien bash completion survived uninstall" >&2
  exit 1
}

printf 'pi-en-install-non-nix tests passed\n'
