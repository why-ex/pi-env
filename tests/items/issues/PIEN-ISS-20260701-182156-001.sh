#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

assert_file() {
  [ -e "$1" ] || { echo "missing expected file: $1" >&2; exit 1; }
}

assert_executable() {
  [ -x "$1" ] || { echo "missing expected executable: $1" >&2; exit 1; }
}

verify_home_helper_bind_visible() {
  local prefix="$1"
  local fakebin="$tmp/fakebin-home-helper"
  local capture="$tmp/home-helper-bwrap.out"
  local real_realpath
  real_realpath="$(command -v realpath)"
  local helper_parent="$tmp/fake-home/pi/.local/share/pi-en-test"
  local helper_root helper_dir helper_sandbox_dir
  mkdir -p "$fakebin" "$helper_parent"
  helper_root="$(mktemp -d "$helper_parent/PIEN-ISS-20260701-182156-001.XXXXXX")"
  helper_dir="$helper_root/scripts"
  helper_sandbox_dir="/home/pi/.local/share/pi-en-test/${helper_root##*/}/scripts"
  mkdir -p "$helper_dir"
  cat >"$fakebin/pi" <<'FAKE_PI'
#!/usr/bin/env bash
exit 99
FAKE_PI
  chmod +x "$fakebin/pi"
  cat >"$fakebin/realpath" <<FAKE_REALPATH
#!/usr/bin/env bash
case "[\$*]" in
  "[-e $helper_dir]")
    printf '%s\\n' '$helper_sandbox_dir'
    ;;
  "[-m /home/pi]")
    printf '%s\\n' /home/pi
    ;;
  *)
    exec '$real_realpath' "\$@"
    ;;
esac
FAKE_REALPATH
  chmod +x "$fakebin/realpath"
  : >"$fakebin/host-bash"
  : >"$fakebin/host-env"
  chmod +x "$fakebin/host-bash" "$fakebin/host-env"
  cat >"$fakebin/bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
visible=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bind)
      if [ "${3:-}" = /home/pi ]; then
        visible=0
      fi
      shift 3
      ;;
    --ro-bind)
      if [ "${3:-}" = "$PI_EN_TEST_HELPER_SANDBOX_DIR" ]; then
        visible=1
      fi
      shift 3
      ;;
    *)
      shift
      ;;
  esac
done
if [ "$visible" != 1 ]; then
  echo 'host helper bind would be masked by the sandbox HOME bind' >&2
  exit 86
fi
printf 'visible\n' >"$PI_EN_TEST_BWRAP_CAPTURE"
FAKE_BWRAP
  chmod +x "$fakebin/bwrap"

  HOME=/home/pi \
    PATH="$fakebin:$PATH" \
    PI_EN_TEST_HELPER_SANDBOX_DIR="$helper_sandbox_dir" \
    PI_EN_TEST_BWRAP_CAPTURE="$capture" \
    PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
    PI_EN_BWRAP_BASH="$fakebin/host-bash" \
    PI_EN_BWRAP_ENV="$fakebin/host-env" \
    PI_EN_BWRAP_HOST_EXTRA_PATH="$fakebin" \
    PI_EN_BWRAP_HOST_RO_PATHS="$helper_dir" \
    PI_EN_BWRAP_PROJECT_ROOT="$repo_root" \
    PI_EN_BWRAP_STATE_DIR="$tmp/fake-home-state" \
    PI_EN_BWRAP_IMPORT_COMMON=0 \
    PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
    PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
    PI_EN_BWRAP_IMPORT_AUTH=0 \
    PI_EN_BWRAP_IMPORT_SESSIONS=0 \
    "$prefix/bin/pi-en-bwrap" -- --help
  grep -Fx visible "$capture" >/dev/null \
    || { echo 'fake bwrap did not confirm helper visibility' >&2; exit 1; }
}

make_serial_fixture() {
  local fixture_root="$1"
  local project_dir="$fixture_root/project"
  local coord_dir="$fixture_root/coordination"
  local remote_dir="$fixture_root/coordination.git"
  mkdir -p "$project_dir" "$coord_dir/issues/open"
  git -C "$project_dir" init -q
  git -C "$project_dir" config user.email test@example.invalid
  git -C "$project_dir" config user.name 'pi-en test'
  printf 'fixture\n' >"$project_dir/README.md"
  git -C "$project_dir" add README.md
  git -C "$project_dir" commit -q -m 'Initial fixture project'

  git -C "$coord_dir" init -q
  git -C "$coord_dir" config user.email test@example.invalid
  git -C "$coord_dir" config user.name 'pi-en test'
  printf '# fixture coordination\n' >"$coord_dir/AGENTS.md"
  cat >"$coord_dir/issues/open/PIEN-ISS-20260701-182156-001.yaml" <<'YAML'
schema: coordination-item/v1
id: PIEN-ISS-20260701-182156-001
type: issue
status: open
project: pi-en
title: Fixture issue
owner: samo
reviewed: false
verified: false
YAML
  git -C "$coord_dir" add AGENTS.md issues/open/PIEN-ISS-20260701-182156-001.yaml
  git -C "$coord_dir" commit -q -m 'Initial fixture coordination'
  git init --bare -q "$remote_dir"
  git -C "$coord_dir" remote add origin "$remote_dir"
  git -C "$coord_dir" push -q -u origin HEAD
  printf '%s\t%s\n' "$project_dir" "$coord_dir"
}

verify_install() {
  local prefix="$1"
  assert_executable "$prefix/bin/pi-en"
  [ ! -e "$prefix/bin/pi-start" ] || { echo "pi-start should not be installed" >&2; exit 1; }
  assert_executable "$prefix/bin/pi-en-bwrap"
  assert_executable "$prefix/bin/pi-en-bootstrap-coordination"
  assert_executable "$prefix/bin/pi-en-coord-status"
  assert_executable "$prefix/bin/pi-en-coord-done"
  assert_executable "$prefix/bin/pi-en-serial-roles"
  assert_executable "$prefix/bin/pi-en-uninstall"
  [ ! -e "$prefix/bin/pi-en-coord-lib.sh" ] || { echo "private library installed as command" >&2; exit 1; }
  assert_file "$prefix/share/pi-en/scripts/pi-en-coord-lib.sh"
  assert_file "$prefix/share/pi-en/pi-skill-templates/agent-coordination/AGENTS.md"
  assert_file "$prefix/share/pi-en/role-manager/package.json"
  assert_file "$prefix/share/pi-en/install-manifest"

  "$prefix/bin/pi-en-coord-status" --help >/dev/null
  "$prefix/bin/pi-en-bootstrap-coordination" --help >/dev/null
  PATH="$prefix/bin:$PATH" "$prefix/bin/pi-en-serial-roles" \
    --project-root "$repo_root" \
    --coord-dir "$repo_root/.pi-en/coordination" \
    --max-jobs 0 >/dev/null

  local dry_run_out fixture project_dir coord_dir
  dry_run_out="$tmp/pi-serial-dry-run.out"
  fixture="$(make_serial_fixture "$(mktemp -d "$tmp/serial-fixture.XXXXXX")")"
  IFS=$'\t' read -r project_dir coord_dir <<<"$fixture"
  PATH="$prefix/bin:$PATH" "$prefix/bin/pi-en-serial-roles" \
    --project-root "$project_dir" \
    --coord-dir "$coord_dir" \
    --agent-id samo \
    --dry-run >"$dry_run_out"
  grep -F "PI_EN_BWRAP_HOST_RO_PATHS=" "$dry_run_out" >/dev/null \
    || { echo "dry-run did not pass host read-only bind paths" >&2; cat "$dry_run_out" >&2; exit 1; }
  grep -F "/share/pi-en/scripts" "$dry_run_out" >/dev/null \
    || { echo "dry-run did not bind installed helper scripts" >&2; cat "$dry_run_out" >&2; exit 1; }
  grep -F "/share/pi-en/scripts/pi-en-coord-" "$dry_run_out" >/dev/null \
    || { echo "dry-run did not prompt with installed helper path" >&2; cat "$dry_run_out" >&2; exit 1; }
  verify_home_helper_bind_visible "$prefix"
}

source_prefix="$tmp/source prefix with dollar \$ and quote \""
"$repo_root/scripts/pi-en-install-non-nix" --prefix "$source_prefix"
verify_install "$source_prefix"
"$source_prefix/bin/pi-en-uninstall"
[ ! -e "$source_prefix/bin/pi-en" ] || { echo "uninstall left pi-en wrapper behind" >&2; exit 1; }
[ ! -e "$source_prefix/share/pi-en" ] || { echo "uninstall left support directory behind" >&2; exit 1; }

archive_root="$tmp/pi-en-release"
mkdir -p "$archive_root"
cp -R "$repo_root/scripts" "$archive_root/scripts"
cp -R "$repo_root/role-manager" "$archive_root/role-manager"
cp -R "$repo_root/pi-skill-templates" "$archive_root/pi-skill-templates"
archive_prefix="$tmp/archive-prefix"
"$archive_root/scripts/pi-en-install-non-nix" --prefix "$archive_prefix"
verify_install "$archive_prefix"
