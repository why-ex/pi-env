#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

stdout_file="$(mktemp)"
cleanup() { rm -f "$stdout_file"; }
trap cleanup EXIT

scripts/pi-en-coord-generate-requirements > "$stdout_file"

grep -F 'This document is generated reference output' "$stdout_file" >/dev/null
grep -F 'preferred source of truth when present' "$stdout_file" >/dev/null
grep -F 'secondary fallback source' "$stdout_file" >/dev/null

grep -F '#### CMD-017' "$stdout_file" >/dev/null
grep -F '#### CRQ-010 — Requirement source of truth precedence' "$stdout_file" >/dev/null

if grep -F 'message: msg-0002' "$stdout_file" >/dev/null || grep -F 'events:' "$stdout_file" >/dev/null; then
  echo 'generated requirements leaked coordination YAML structure' >&2
  exit 1
fi

if [ "$(sha256sum "$stdout_file" | awk '{print $1}')" != "$(sha256sum REQUIREMENTS.md | awk '{print $1}')" ]; then
  echo 'REQUIREMENTS.md is not regenerated from coordination items' >&2
  exit 1
fi

printf 'PIEN-ISS-20260613-090705-001 passed\n'
