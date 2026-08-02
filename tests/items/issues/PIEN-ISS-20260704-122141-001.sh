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
  local category="$4"
  local title="$5"
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<EOF_ITEM
schema: coordination-item/v1
id: $id
type: issue
category: $category
status: $status
project: fixtures
owner: ''
priority: medium
created: 2026-07-04T00:00:00Z
updated: 2026-07-04T00:00:00Z
done: null
closed: null
reviewed: false
verified: false
testable: no
testability_note: 'fixture item'
title: '$title'
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
impl_dir="$tmp/impl"
mkdir -p "$coord_dir" "$impl_dir"
git -C "$coord_dir" init -q
git -C "$coord_dir" config user.name "Coordination Test"
git -C "$coord_dir" config user.email "coordination-test@example.invalid"
cat >"$coord_dir/PROJECT.md" <<'EOF_PROJECT'
---
project: domain
item_key: DOM
---
EOF_PROJECT
for repo in alpha beta retired; do
  mkdir -p "$coord_dir/repos/$repo/issues/open" "$coord_dir/repos/$repo/issues/blocked" \
    "$coord_dir/repos/$repo/issues/done" "$coord_dir/repos/$repo/issues/closed"
done
cat >"$coord_dir/repos/alpha/REPO.md" <<'EOF_ALPHA'
---
repo_id: alpha
status: active
item_key: ALPHA
project: alpha
remotes:
  - https://example.invalid/alpha.git
---
EOF_ALPHA
cat >"$coord_dir/repos/beta/REPO.md" <<'EOF_BETA'
---
repo_id: beta
status: active
item_key: BETA
project: beta
---
EOF_BETA
cat >"$coord_dir/repos/retired/REPO.md" <<'EOF_RETIRED'
---
repo_id: retired
status: retired
item_key: RET
project: retired
---
EOF_RETIRED
make_issue "$coord_dir/repos/alpha/issues/open/ALPHA-ISS-1.yaml" ALPHA-ISS-1 open bug "Alpha bug"
make_issue "$coord_dir/repos/alpha/issues/open/ALPHA-ISS-2.yaml" ALPHA-ISS-2 open task "Alpha task"
make_issue "$coord_dir/repos/beta/issues/open/BETA-ISS-1.yaml" BETA-ISS-1 open task "Beta task"
make_issue "$coord_dir/repos/beta/issues/open/BETA-ISS-2.yaml" BETA-ISS-2 open bug "Beta bug"
git -C "$coord_dir" add -A
git -C "$coord_dir" commit -q -m 'Seed repo-aware fixtures'

git -C "$impl_dir" init -q
git -C "$impl_dir" remote add origin https://example.invalid/alpha.git

created_path="$(cd "$impl_dir" && pi-en-coord-new --coord-dir "$coord_dir" --category improvement "Created in active repo" | tail -n 1)"
case "$created_path" in
  repos/alpha/issues/open/ALPHA-ISS-*.yaml) ;;
  *) printf 'unexpected active repo issue path: %s\n' "$created_path" >&2; exit 1 ;;
esac
created_id="$(basename "$created_path" .yaml)"

if (cd "$tmp" && pi-en-coord-new --coord-dir "$coord_dir" "No active repo" >"$tmp/no-repo.out" 2>"$tmp/no-repo.err"); then
  printf 'pi-en-coord-new unexpectedly accepted missing active repo\n' >&2
  exit 1
fi
grep -q 'missing repo id' "$tmp/no-repo.err"

if pi-en-coord-new --coord-dir "$coord_dir" --repo-id unknown "Unknown repo" >"$tmp/unknown.out" 2>"$tmp/unknown.err"; then
  printf 'pi-en-coord-new unexpectedly accepted unknown repo\n' >&2
  exit 1
fi
grep -q 'not registered' "$tmp/unknown.err"

if pi-en-coord-new --coord-dir "$coord_dir" --repo-id retired "Retired repo" >"$tmp/retired.out" 2>"$tmp/retired.err"; then
  printf 'pi-en-coord-new unexpectedly accepted retired repo\n' >&2
  exit 1
fi
grep -q 'retired' "$tmp/retired.err"

alpha_list="$(cd "$impl_dir" && pi-en-coord-list --coord-dir "$coord_dir" issues open)"
printf '%s\n' "$alpha_list" | grep -q $'ALPHA-ISS-1\topen\tAlpha bug'
if printf '%s\n' "$alpha_list" | grep -q 'BETA-ISS-1'; then
  printf 'default issue list unexpectedly included beta issue\n' >&2
  exit 1
fi

all_list="$(pi-en-coord-list --coord-dir "$coord_dir" issues open --all-repos)"
printf '%s\n' "$all_list" | grep -q $'alpha\tALPHA-ISS-1\topen\tAlpha bug'
printf '%s\n' "$all_list" | grep -q $'beta\tBETA-ISS-1\topen\tBeta task'

all_grouped="$(pi-en-coord-list --coord-dir "$coord_dir" issues open --all-repos --group-by-category)"
printf '%s\n' "$all_grouped" | grep -q $'alpha\tbug\tALPHA-ISS-1\topen\tAlpha bug'
printf '%s\n' "$all_grouped" | grep -q $'beta\ttask\tBETA-ISS-1\topen\tBeta task'
expected_grouped=$'alpha\tbug\tALPHA-ISS-1\topen\tAlpha bug\nbeta\tbug\tBETA-ISS-2\topen\tBeta bug'
expected_grouped="$expected_grouped
alpha	improvement	$created_id	open	Created in active repo"
expected_grouped="$expected_grouped"$'\nalpha\ttask\tALPHA-ISS-2\topen\tAlpha task\nbeta\ttask\tBETA-ISS-1\topen\tBeta task'
if [ "$all_grouped" != "$expected_grouped" ]; then
  printf 'all-repos category grouping sorted incorrectly:\n%s\n' "$all_grouped" >&2
  exit 1
fi

bug_list="$(cd "$impl_dir" && pi-en-coord-list --coord-dir "$coord_dir" issues open --category bug)"
printf '%s\n' "$bug_list" | grep -q 'ALPHA-ISS-1'
if printf '%s\n' "$bug_list" | grep -q 'ALPHA-ISS-2'; then
  printf 'category filter unexpectedly included non-bug issue\n' >&2
  exit 1
fi

status_default="$(cd "$impl_dir" && pi-en-coord-status --coord-dir "$coord_dir")"
printf '%s\n' "$status_default" | grep -q 'Issue scope: repo alpha'
printf '%s\n' "$status_default" | grep -q 'ALPHA-ISS-1'
if printf '%s\n' "$status_default" | grep -q 'BETA-ISS-1'; then
  printf 'default status unexpectedly included beta issue\n' >&2
  exit 1
fi

status_all="$(pi-en-coord-status --coord-dir "$coord_dir" --all-repos)"
printf '%s\n' "$status_all" | grep -q 'Issue scope: all repos'
printf '%s\n' "$status_all" | grep -q 'repo=alpha'
printf '%s\n' "$status_all" | grep -q 'repo=beta'
