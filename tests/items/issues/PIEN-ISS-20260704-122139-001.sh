#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_issue() {
  local file="$1"
  local id="$2"
  local status="$3"
  local owner="${4:-}"
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<EOF_ITEM
schema: coordination-item/v1
id: $id
type: issue
category: task
status: $status
project: alpha
owner: $owner
priority: medium
created: 2026-07-04T00:00:00Z
updated: 2026-07-04T00:00:00Z
done: null
closed: null
reviewed: false
verified: false
testable: no
testability_note: 'fixture item'
current:
  event: evt-0001
  message: msg-0001
events:
  - id: evt-0001
    type: opened
    at: 2026-07-04T00:00:00Z
    actor:
      id: test
      role: developer
    message: msg-0001
messages:
  - id: msg-0001
    event: evt-0001
    body: |-
      Fixture item.
EOF_ITEM
}

coord_dir="$tmp/coordination"
mkdir -p "$coord_dir/repos/alpha/issues/open" \
  "$coord_dir/repos/alpha/issues/blocked" \
  "$coord_dir/repos/alpha/issues/done" \
  "$coord_dir/repos/alpha/issues/closed" \
  "$coord_dir/issues/open"
git -C "$coord_dir" init -q
git -C "$coord_dir" config user.name "Coordination Test"
git -C "$coord_dir" config user.email "coordination-test@example.invalid"
cat >"$coord_dir/PROJECT.md" <<'EOF_PROJECT'
---
project: domain
item_key: DOM
---
EOF_PROJECT
cat >"$coord_dir/repos/alpha/REPO.md" <<'EOF_REPO'
---
repo_id: alpha
status: active
item_key: ALPHA
project: alpha
---
EOF_REPO
make_issue "$coord_dir/issues/open/LEGACY-ISS-1.yaml" LEGACY-ISS-1 open
make_issue "$coord_dir/repos/alpha/issues/open/ALPHA-ISS-1.yaml" ALPHA-ISS-1 claimed agent-a
git -C "$coord_dir" add -A
git -C "$coord_dir" commit -q -m 'Seed repo-scoped issue fixtures'

# Discovery includes both legacy root issues and repo-scoped issues.
(
  cd "$coord_dir"
  # shellcheck source=/dev/null
  . "$repo_root/scripts/pi-en-coord-lib.sh"
  coord_item_find_files >"$tmp/items.out"
)
grep -q '^issues/open/LEGACY-ISS-1.yaml$' "$tmp/items.out"
grep -q '^repos/alpha/issues/open/ALPHA-ISS-1.yaml$' "$tmp/items.out"

# Lookup by global item ID resolves the repo-scoped location.
pi-en-coord-cat --coord-dir "$coord_dir" ALPHA-ISS-1 | grep -q '^id: ALPHA-ISS-1$'

# New issues in a repo-scoped coordination domain require a repo namespace.
if pi-en-coord-new --coord-dir "$coord_dir" "Root write" >"$tmp/new.out" 2>"$tmp/new.err"; then
  printf 'pi-en-coord-new unexpectedly wrote a root issue\n' >&2
  exit 1
fi
grep -q -- '--repo-id' "$tmp/new.err"
new_path="$(pi-en-coord-new --coord-dir "$coord_dir" --repo-id alpha "Repo write" | tail -n 1)"
case "$new_path" in
  repos/alpha/issues/open/ALPHA-ISS-*.yaml) ;;
  *) printf 'unexpected repo-scoped issue path: %s\n' "$new_path" >&2; exit 1 ;;
esac

# Status movement preserves the repo namespace.
pi-en-coord-done --coord-dir "$coord_dir" --agent-id agent-a --role developer \
  --implementation-ref "alpha:main@$(git -C "$repo_root" rev-parse HEAD)" \
  --no-pull --no-push ALPHA-ISS-1 >/dev/null
test -f "$coord_dir/repos/alpha/issues/done/ALPHA-ISS-1.yaml"
test ! -e "$coord_dir/issues/done/ALPHA-ISS-1.yaml"
grep -q '^status: done$' "$coord_dir/repos/alpha/issues/done/ALPHA-ISS-1.yaml"

# Duplicate global IDs across repo namespaces are lint failures.
make_issue "$coord_dir/repos/alpha/issues/open/LEGACY-ISS-1.yaml" LEGACY-ISS-1 open
if pi-en-coord-lint --coord-dir "$coord_dir" --project-root "$repo_root" >"$tmp/lint.out" 2>"$tmp/lint.err"; then
  printf 'pi-en-coord-lint unexpectedly accepted duplicate issue IDs\n' >&2
  exit 1
fi
grep -q 'duplicates item id LEGACY-ISS-1' "$tmp/lint.err"
