# Git Configuration Import Design

Git configuration import gives sandboxed commands familiar version-control
behavior without copying credentials or granting broad access to host home
state.

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-013 | PIEN-FRQ-20260612-210000-013 |
| GIT-001 | PIEN-FRQ-20260612-210000-080 |
| GIT-002 | PIEN-FRQ-20260612-210000-081 |
| GIT-003 | PIEN-FRQ-20260612-210000-082 |
| GIT-004 | PIEN-FRQ-20260612-210000-083 |
| GIT-005 | PIEN-FRQ-20260612-210000-084 |
| GIT-006 | PIEN-FRQ-20260612-210000-085 |
| GIT-007 | PIEN-FRQ-20260612-210000-086 |
| GIT-008 | PIEN-FRQ-20260612-210000-087 |
| CRQ-006 | PIEN-CRQ-20260612-210000-006 |

## 1. Imported preferences

The sandbox may import Git preferences needed for normal repository work:
identity, default branch behavior, safe editor settings, aliases, color, and
other non-secret options. These are copied into the sandbox home so Git behaves
predictably for commits, status inspection, and local history operations.

The import step should preserve user intent but not require host-specific paths
to exist in the sandbox. Where a setting names a missing helper, the sandboxed
Git command should fail normally with a clear Git error rather than expanding
filesystem exposure.

## 2. Excluded credentials

Credential helpers, tokens, SSH private keys, cookie stores, and unrelated
application secrets are not copied as part of Git preference import. Network or
remote access should rely on explicitly provided credentials outside this
general Git configuration path.

This supports `CRQ-006`: convenience must not turn into accidental credential
exfiltration. The sandbox should prefer a usable local Git experience over an
automatically authenticated remote Git experience.

## 3. Safety expectations

Git import runs before the sandboxed command starts and writes only to sandbox
state. It should be testable by inspecting copied files and by checking that
known credential paths are absent. The Bubblewrap filesystem policy remains the
primary boundary preventing access to host Git credential material.
