#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

coord_dir="$tmpdir/coordination"
designs_dir="$tmpdir/designs"
req_dir="$coord_dir/requirements"
mkdir -p "$req_dir" "$designs_dir"

write_req() {
  local id="$1" key="$2" order="$3"
  cat > "$req_dir/$id.yaml" <<EOF
schema: coordination-item/v1
id: $id
type: functional-requirement
requirement_key: $key
requirement_class: functional
requirement_kind: detailed-behavior
domain: test
status: active
project: pi-env
title: "$key"
render_order: $order
testable: no
testability_note: fixture
body: |-
  #### $key Fixture
EOF
}

write_req PIENV-FRQ-20260614-000000-001 UC-001 1
write_req PIENV-FRQ-20260614-000000-002 UC-002 2
write_req PIENV-FRQ-20260614-000000-003 UC-003 3

cat > "$designs_dir/alpha.md" <<'EOF'
# Alpha

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-001 | PIENV-FRQ-20260614-000000-001 |
| UC-002 | PIENV-FRQ-20260614-000000-002 |
EOF

cat > "$designs_dir/beta.md" <<'EOF'
# Beta

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-002 | PIENV-FRQ-20260614-000000-002 |
EOF

output="$tmpdir/coverage.md"
scripts/pi-env-coord-generate-requirements-coverage \
  --coordination-dir "$coord_dir" \
  --designs-dir "$designs_dir" \
  --output "$output"

stdout_output="$tmpdir/stdout.md"
scripts/pi-env-coord-generate-requirements-coverage \
  --coordination-dir "$coord_dir" \
  --designs-dir "$designs_dir" > "$stdout_output"
if [ "$(sha256sum "$output" | awk '{print $1}')" != "$(sha256sum "$stdout_output" | awk '{print $1}')" ]; then
  echo "stdout and --output coverage renderings differ" >&2
  exit 1
fi

grep -F -- '- Requirements: 3' "$output" >/dev/null
grep -F -- '- Covered by design: 2' "$output" >/dev/null
grep -F -- '- Not covered by design: 1' "$output" >/dev/null
grep -F "| UC-001 | PIENV-FRQ-20260614-000000-001 | $designs_dir/alpha.md |" "$output" >/dev/null
grep -F "| UC-002 | PIENV-FRQ-20260614-000000-002 | $designs_dir/alpha.md, $designs_dir/beta.md |" "$output" >/dev/null
grep -F '| UC-003 | PIENV-FRQ-20260614-000000-003 | Not covered |' "$output" >/dev/null

unknown_dir="$tmpdir/unknown-designs"
mkdir -p "$unknown_dir"
cat > "$unknown_dir/bad.md" <<'EOF'
# Bad

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-999 | PIENV-FRQ-20260614-000000-999 |
EOF
if scripts/pi-env-coord-generate-requirements-coverage \
  --coordination-dir "$coord_dir" \
  --designs-dir "$unknown_dir" \
  --check 2>"$tmpdir/unknown.err"; then
  echo "unknown requirement key should fail" >&2
  exit 1
fi
grep -F 'unknown or inactive requirement key UC-999' "$tmpdir/unknown.err" >/dev/null

stale_dir="$tmpdir/stale-designs"
mkdir -p "$stale_dir"
cat > "$stale_dir/stale.md" <<'EOF'
# Stale

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-001 | PIENV-FRQ-20260614-000000-003 |
EOF
if scripts/pi-env-coord-generate-requirements-coverage \
  --coordination-dir "$coord_dir" \
  --designs-dir "$stale_dir" \
  --check 2>"$tmpdir/stale.err"; then
  echo "stale coordination item ID should fail" >&2
  exit 1
fi
grep -F 'stale coordination item for UC-001' "$tmpdir/stale.err" >/dev/null

malformed_dir="$tmpdir/malformed-designs"
mkdir -p "$malformed_dir"
cat > "$malformed_dir/malformed.md" <<'EOF'
# Malformed

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-001 | PIENV-FRQ-20260614-000000-001 | extra |
EOF
if scripts/pi-env-coord-generate-requirements-coverage \
  --coordination-dir "$coord_dir" \
  --designs-dir "$malformed_dir" \
  --check 2>"$tmpdir/malformed.err"; then
  echo "malformed Covers row should fail" >&2
  exit 1
fi
grep -F 'malformed Covers row' "$tmpdir/malformed.err" >/dev/null

preview="$tmpdir/preview.md"
scripts/pi-env-coord-generate-requirements-coverage \
  --coordination-dir "$coord_dir" \
  --designs-dir "$unknown_dir" \
  --preview > "$preview"
grep -F '## Invalid design references' "$preview" >/dev/null
