#!/usr/bin/env bash
# Shared helpers for bash-based pi-en tests.
# Source this file from tests that want small assertion helpers while keeping
# every test script executable on its own.

set -euo pipefail

test_note() {
  printf '# %s\n' "$*"
}

test_fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

test_file_exists() {
  local path
  path="$1"
  [ -f "$path" ] || test_fail "expected file to exist: $path"
}

test_dir_exists() {
  local path
  path="$1"
  [ -d "$path" ] || test_fail "expected directory to exist: $path"
}

test_grep() {
  local pattern path
  pattern="$1"
  path="$2"
  grep -q -- "$pattern" "$path" || test_fail "expected $path to match: $pattern"
}

test_eq() {
  local expected actual label
  expected="$1"
  actual="$2"
  label="${3:-values differ}"
  [ "$expected" = "$actual" ] || test_fail "$label: expected '$expected', got '$actual'"
}
