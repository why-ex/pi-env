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
mkdir -p "$HOME" "$tmp/seed"
git config --global user.name "Coordination Test"
git config --global user.email "coordination-test@example.invalid"

cd "$tmp/seed"
pi-env-coord-init \
  --root "$tmp/remotes" \
  --project pi-env \
  --agent-id seed-agent \
  --dir .pi-env/coordination >/dev/null

item_path="$(pi-env-coord-new \
  --coord-dir .pi-env/coordination \
  --repo-id pi-env \
  "Exercise concurrent claim handling" | tail -n 1)"
item_id="$(grep '^id: ' ".pi-env/coordination/$item_path" | sed 's/^id: //')"
pi-env-coord-push \
  --coord-dir .pi-env/coordination \
  -m "Add concurrent claim test item" >/dev/null

cd "$tmp"
pi-env-coord-clone \
  --root "$tmp/remotes" \
  --project pi-env \
  --dir agent-a >/dev/null
pi-env-coord-clone \
  --root "$tmp/remotes" \
  --project pi-env \
  --dir agent-b >/dev/null

pi-env-coord-claim \
  --coord-dir agent-a \
  --agent-id agent-a \
  "$item_id" >/dev/null

if pi-env-coord-claim \
  --coord-dir agent-b \
  --agent-id agent-b \
  --no-pull \
  "$item_id" >/dev/null 2>&1; then
  printf 'expected stale push claim to fail\n' >&2
  exit 1
fi

git -C agent-b fetch origin >/dev/null
git -C agent-b reset --hard origin/main >/dev/null

if pi-env-coord-claim \
  --coord-dir agent-b \
  --agent-id agent-b \
  "$item_id" >/dev/null 2>&1; then
  printf 'expected owned claim to fail\n' >&2
  exit 1
fi

if pi-env-coord-done \
  --coord-dir agent-b \
  --agent-id agent-b \
  "$item_id" >/dev/null 2>&1; then
  printf 'expected done by non-owner to fail\n' >&2
  exit 1
fi

done_path="$(pi-env-coord-done \
  --coord-dir agent-a \
  --agent-id agent-a \
  --result "Done by owning agent." \
  "$item_id" | tail -n 1)"

test -f "agent-a/$done_path"
grep -q '^status: done$' "agent-a/$done_path"
grep -q '^owner: agent-a$' "agent-a/$done_path"

if pi-env-coord-close \
  --coord-dir agent-a \
  --agent-id agent-a \
  "$item_id" >/dev/null 2>&1; then
  printf 'expected close before review/verification to fail\n' >&2
  exit 1
fi

pi-env-coord-review \
  --coord-dir agent-b \
  --agent-id reviewer-b \
  --role reviewer \
  --pass \
  "$item_id" >/dev/null

pi-env-coord-verify \
  --coord-dir agent-b \
  --agent-id tester-b \
  --role tester \
  --pass \
  "$item_id" >/dev/null

closed_path="$(pi-env-coord-close \
  --coord-dir agent-b \
  --agent-id tester-b \
  --role tester \
  --result "Closed after review and verification." \
  "$item_id" | tail -n 1)"

test -f "agent-b/$closed_path"
grep -q '^status: closed$' "agent-b/$closed_path"
grep -q '^owner: agent-a$' "agent-b/$closed_path"
grep -q '^reviewed: true$' "agent-b/$closed_path"
grep -q '^verified: true$' "agent-b/$closed_path"

pi-env-coord-pull --coord-dir agent-a >/dev/null
test -f "agent-a/$closed_path"
grep -q '^status: closed$' "agent-a/$closed_path"

printf 'subject length check\n' >agent-b/decisions/subject-length.md
long_subject="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
if pi-env-coord-push \
  --coord-dir agent-b \
  -m "$long_subject" >/dev/null 2>&1; then
  printf 'expected long commit subject to fail\n' >&2
  exit 1
fi

git -C agent-b reset --hard HEAD >/dev/null
git -C agent-b clean -fd >/dev/null

printf 'agent coordination concurrency tests passed\n'
