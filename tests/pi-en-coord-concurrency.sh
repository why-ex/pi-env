#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PI_EN_COORD_TEMPLATE_DIR="$repo_root/pi-skill-templates/agent-coordination"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
unset PI_EN_COORD_REMOTE PI_EN_COORD_WORKSPACE \
  PI_EN_COORD_DIR PI_EN_COORD_AGENT_ID PI_EN_COORD_PROJECT PI_EN_COORD_PROJECT_KEY PI_EN_COORD_ROLE
mkdir -p "$HOME" "$tmp/seed"
git config --global user.name "Coordination Test"
git config --global user.email "coordination-test@example.invalid"

cd "$tmp/seed"
pi-en-coord-init \
  --root "$tmp/remotes" \
  --project pi-en \
  --agent-id seed-agent \
  --dir .pi-en/coordination >/dev/null

item_path="$(pi-en-coord-new \
  --coord-dir .pi-en/coordination \
  --repo-id pi-en \
  "Exercise concurrent claim handling" | tail -n 1)"
item_id="$(grep '^id: ' ".pi-en/coordination/$item_path" | sed 's/^id: //')"
pi-en-coord-push \
  --coord-dir .pi-en/coordination \
  -m "Add concurrent claim test item" >/dev/null

cd "$tmp"
pi-en-coord-clone \
  --root "$tmp/remotes" \
  --project pi-en \
  --dir agent-a >/dev/null
pi-en-coord-clone \
  --root "$tmp/remotes" \
  --project pi-en \
  --dir agent-b >/dev/null

pi-en-coord-claim \
  --coord-dir agent-a \
  --agent-id agent-a \
  "$item_id" >/dev/null

if pi-en-coord-claim \
  --coord-dir agent-b \
  --agent-id agent-b \
  --no-pull \
  "$item_id" >/dev/null 2>&1; then
  printf 'expected stale push claim to fail\n' >&2
  exit 1
fi

git -C agent-b fetch origin >/dev/null
git -C agent-b reset --hard origin/main >/dev/null

if pi-en-coord-claim \
  --coord-dir agent-b \
  --agent-id agent-b \
  "$item_id" >/dev/null 2>&1; then
  printf 'expected owned claim to fail\n' >&2
  exit 1
fi

if pi-en-coord-done \
  --coord-dir agent-b \
  --agent-id agent-b \
  "$item_id" >/dev/null 2>&1; then
  printf 'expected done by non-owner to fail\n' >&2
  exit 1
fi

done_path="$(pi-en-coord-done \
  --coord-dir agent-a \
  --agent-id agent-a \
  --result "Done by owning agent." \
  "$item_id" | tail -n 1)"

test -f "agent-a/$done_path"
grep -q '^status: done$' "agent-a/$done_path"
grep -q '^owner: agent-a$' "agent-a/$done_path"

if pi-en-coord-close \
  --coord-dir agent-a \
  --agent-id agent-a \
  "$item_id" >/dev/null 2>&1; then
  printf 'expected close before review/verification to fail\n' >&2
  exit 1
fi

pi-en-coord-review \
  --coord-dir agent-b \
  --agent-id reviewer-b \
  --role reviewer \
  --pass \
  "$item_id" >/dev/null

pi-en-coord-verify \
  --coord-dir agent-b \
  --agent-id tester-b \
  --role tester \
  --pass \
  "$item_id" >/dev/null

closed_path="$(pi-en-coord-close \
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

pi-en-coord-pull --coord-dir agent-a >/dev/null
test -f "agent-a/$closed_path"
grep -q '^status: closed$' "agent-a/$closed_path"

printf 'subject length check\n' >agent-b/decisions/subject-length.md
long_subject="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
if pi-en-coord-push \
  --coord-dir agent-b \
  -m "$long_subject" >/dev/null 2>&1; then
  printf 'expected long commit subject to fail\n' >&2
  exit 1
fi

git -C agent-b reset --hard HEAD >/dev/null
git -C agent-b clean -fd >/dev/null

printf 'agent coordination concurrency tests passed\n'
