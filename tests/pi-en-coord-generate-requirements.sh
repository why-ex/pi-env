#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

stdout_file="$tmpdir/requirements.stdout.md"
output_file="$tmpdir/requirements.output.md"

help_output="$(scripts/pi-en-coord-generate-requirements --help)"
grep -F 'render REQUIREMENTS.md from coordination items' <<<"$help_output" >/dev/null
grep -F "Renders active requirement items from the coordination repository's root" <<<"$help_output" >/dev/null
if grep -Fq 'designs' <<<"$help_output"; then
  echo "requirements generator help should not describe designs as its source" >&2
  exit 1
fi

scripts/pi-en-coord-generate-requirements > "$stdout_file"
scripts/pi-en-coord-generate-requirements --output "$output_file"

if [ "$(sha256sum "$stdout_file" | awk '{print $1}')" != "$(sha256sum "$output_file" | awk '{print $1}')" ]; then
  echo "stdout and --output renderings differ" >&2
  exit 1
fi

grep -F '# Pi-en Requirements' "$stdout_file" >/dev/null
grep -F '## 3. Functional requirements' "$stdout_file" >/dev/null
grep -F '## 4. Quality requirements' "$stdout_file" >/dev/null
grep -F '## 5. Constraint requirements' "$stdout_file" >/dev/null
grep -F '#### UC-001' "$stdout_file" >/dev/null
grep -F '#### CMD-004' "$stdout_file" >/dev/null
grep -F '#### CMD-017' "$stdout_file" >/dev/null
grep -F '#### TEST-031' "$stdout_file" >/dev/null
grep -F '#### CRQ-009' "$stdout_file" >/dev/null
grep -F '#### CRQ-010' "$stdout_file" >/dev/null
grep -F '#### CRQ-010 — Requirement source of truth precedence' "$stdout_file" >/dev/null
grep -F 'Requirement coordination items live under root `requirements/`' "$stdout_file" >/dev/null
grep -F 'one renderable top-level `body: |-` block' "$stdout_file" >/dev/null

fixture_project="$tmpdir/fixture-project"
root_coord="$fixture_project/.pi-en/coordination"
mkdir -p "$root_coord/requirements"
cat > "$root_coord/requirements/EXT-FRQ-20260618-000000-001.yaml" <<'EOF'
schema: coordination-item/v1
id: EXT-FRQ-20260618-000000-001
type: functional-requirement
requirement_key: EXT-001
requirement_class: functional
requirement_kind: detailed-behavior
domain: test
status: active
project: external-app
title: "EXT-001"
render_order: 1
render_section: "3.9 Root layout requirements"
testable: no
testability_note: fixture
body: |-
  #### EXT-001 Project-local fixture

  Requirements must render from the project-local .pi-en coordination requirements directory.
EOF
root_output="$tmpdir/root-requirements.md"
scripts/pi-en-coord-generate-requirements \
  --project 'External App' \
  --coordination-dir "$root_coord" > "$root_output"
grep -F '# External App Requirements' "$root_output" >/dev/null
grep -F '#### EXT-001 Project-local fixture' "$root_output" >/dev/null
if grep -F 'Nix development shell and Bubblewrap launcher' "$root_output" >/dev/null; then
  echo "external requirements output contains pi-en product scope" >&2
  exit 1
fi
if grep -F 'git history establishes' "$root_output" >/dev/null; then
  echo "external requirements output contains pi-en history framing" >&2
  exit 1
fi

env_output="$tmpdir/env-precedence.md"
env_stderr="$tmpdir/env-precedence.err"
(
  cd "$fixture_project"
  PI_EN_COORD_DIR="$repo_root/.pi-en/coordination" \
    "$repo_root/scripts/pi-en-coord-generate-requirements" \
      --project 'External App' \
      --output "$env_output" \
      2>"$env_stderr"
)
grep -F 'Using coordination requirements source:' "$env_stderr" >/dev/null
grep -F 'warning: ignoring PI_EN_COORD_DIR=' "$env_stderr" >/dev/null
grep -F '#### EXT-001 Project-local fixture' "$env_output" >/dev/null
if grep -F 'Nix development shell and Bubblewrap launcher' "$env_output" >/dev/null; then
  echo "stale PI_EN_COORD_DIR overrode project-local coordination" >&2
  exit 1
fi

explicit_coord="$tmpdir/explicit-coordination"
mkdir -p "$explicit_coord/requirements"
cat > "$explicit_coord/requirements/EXP-FRQ-20260618-000000-001.yaml" <<'EOF'
schema: coordination-item/v1
id: EXP-FRQ-20260618-000000-001
type: functional-requirement
requirement_key: EXP-001
requirement_class: functional
requirement_kind: detailed-behavior
domain: test
status: active
project: explicit-app
title: "EXP-001"
render_order: 1
render_section: "3.9 Explicit requirements"
testable: no
testability_note: fixture
body: |-
  #### EXP-001 Explicit fixture

  Requirements must render from the explicit coordination directory.
EOF
explicit_output="$tmpdir/explicit-requirements.md"
explicit_stderr="$tmpdir/explicit-requirements.err"
(
  cd "$fixture_project"
  PI_EN_COORD_DIR="$repo_root/.pi-en/coordination" \
    "$repo_root/scripts/pi-en-coord-generate-requirements" \
      --project 'Explicit App' \
      --coordination-dir "$explicit_coord" \
      --output "$explicit_output" \
      2>"$explicit_stderr"
)
grep -F "Using coordination requirements source: $explicit_coord/requirements" "$explicit_stderr" >/dev/null
grep -F '#### EXP-001 Explicit fixture' "$explicit_output" >/dev/null
if grep -F '#### EXT-001 Project-local fixture' "$explicit_output" >/dev/null; then
  echo "explicit coordination directory did not override project-local source" >&2
  exit 1
fi

no_local_project="$tmpdir/no-local-project"
mkdir -p "$no_local_project"
no_local_output="$tmpdir/no-local-requirements.md"
no_local_stderr="$tmpdir/no-local-requirements.err"
if (
  cd "$no_local_project"
  PI_EN_COORD_DIR="$explicit_coord" \
    "$repo_root/scripts/pi-en-coord-generate-requirements" \
      --project 'No Local App' \
      --output "$no_local_output" \
      2>"$no_local_stderr"
); then
  echo "inherited non-local PI_EN_COORD_DIR should require explicit override" >&2
  exit 1
fi
grep -F 'refusing inherited PI_EN_COORD_DIR=' "$no_local_stderr" >/dev/null
grep -F 'Pass --coordination-dir' "$no_local_stderr" >/dev/null
if [ -e "$no_local_output" ]; then
  echo "implicit inherited PI_EN_COORD_DIR should not write output" >&2
  exit 1
fi

empty_coord="$tmpdir/empty-coordination"
mkdir -p "$empty_coord/requirements"
empty_output="$tmpdir/empty-requirements.md"
empty_stderr="$tmpdir/empty-requirements.err"
if scripts/pi-en-coord-generate-requirements \
  --coordination-dir "$empty_coord" \
  --output "$empty_output" \
  >"$tmpdir/empty-requirements.out" \
  2>"$empty_stderr"; then
  echo "empty requirements source should fail by default" >&2
  exit 1
fi
grep -F 'no active renderable requirement items found' "$empty_stderr" >/dev/null
if [ -e "$empty_output" ]; then
  echo "empty requirements source should not write output" >&2
  exit 1
fi

sample_requirement=".pi-en/coordination/requirements/PIEN-FRQ-20260612-210000-001.yaml"
if [ ! -f "$sample_requirement" ]; then
  echo "missing canonical sample requirement: $sample_requirement" >&2
  exit 1
fi
grep -F 'body: |-' "$sample_requirement" >/dev/null
if grep -E '^(current|events|messages):' "$sample_requirement" >/dev/null; then
  echo "active requirement item still contains embedded history" >&2
  exit 1
fi

for heading in \
  '### 3.2 Flake and package requirements' \
  '## 4. Quality requirements' \
  '## 5. Constraint requirements'
do
  if [ "$(grep -F -c "$heading" "$stdout_file")" != 1 ]; then
    echo "generated requirements should render heading exactly once: $heading" >&2
    exit 1
  fi
done

if grep -F 'functional/quality/constraint requirement tests' "$stdout_file" >/dev/null; then
  echo "generated requirements contain stale class-specific test text" >&2
  exit 1
fi
if grep -F 'functional/quality/constraint requirement items' "$stdout_file" >/dev/null; then
  echo "generated requirements contain stale class-specific item text" >&2
  exit 1
fi

if grep -F 'message: msg-0002' "$stdout_file" >/dev/null || grep -F 'events:' "$stdout_file" >/dev/null; then
  echo "generated requirements leaked coordination YAML structure" >&2
  exit 1
fi

for key in UC-001 UC-023 FLAKE-001 CMD-016 CMD-017 TEST-031 CRQ-009 CRQ-010; do
  grep -F "#### $key" REQUIREMENTS.md >/dev/null
  grep -F "#### $key" "$stdout_file" >/dev/null
done

