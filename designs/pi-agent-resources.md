# Pi Agent Resource Design

Pi resource import prepares the sandboxed agent with the common and
project-local files it needs without exposing the entire user home directory.
Resources are copied or mounted according to purpose and ownership.

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-010 | PIEN-FRQ-20260612-210000-010 |
| UC-011 | PIEN-FRQ-20260612-210000-011 |
| UC-012 | PIEN-FRQ-20260612-210000-012 |
| CRQ-007 | PIEN-CRQ-20260612-210000-007 |
| AGENT-001 | PIEN-FRQ-20260612-210000-063 |
| AGENT-002 | PIEN-FRQ-20260612-210000-064 |
| AGENT-003 | PIEN-FRQ-20260612-210000-065 |
| AGENT-004 | PIEN-FRQ-20260612-210000-066 |
| AGENT-005 | PIEN-FRQ-20260612-210000-067 |
| AGENT-006 | PIEN-FRQ-20260612-210000-068 |
| AGENT-007 | PIEN-FRQ-20260612-210000-069 |
| AGENT-008 | PIEN-FRQ-20260612-210000-070 |
| AGENT-009 | PIEN-FRQ-20260612-210000-071 |
| AGENT-010 | PIEN-FRQ-20260612-210000-072 |
| AGENT-010a | PIEN-FRQ-20260612-210000-073 |
| AGENT-010b | PIEN-FRQ-20260612-210000-074 |
| AGENT-011 | PIEN-FRQ-20260612-210000-075 |
| AGENT-012 | PIEN-FRQ-20260612-210000-076 |
| AGENT-013 | PIEN-FRQ-20260612-210000-077 |
| AGENT-014 | PIEN-FRQ-20260612-210000-078 |
| AGENT-015 | PIEN-FRQ-20260612-210000-079 |

## 1. Resource scopes

Common Pi resources come from an external user-controlled Pi configuration and
support cross-project behavior such as providers, models, themes, extensions,
and skills. `CRQ-007` means `pi-en` imports or exposes those resources but
does not ship user-specific content. Project resources come from the current
workspace and support local instructions, roles, and project-specific packages.

Common resources are imported first, then project resources may add or override
within documented boundaries. This lets `UC-010` through `UC-012` support both
portable project behavior and user-level Pi preferences.

## 2. Auth and model data

Authentication and model configuration are treated as sensitive resources. The
launcher imports only the files and directories required by the Pi runtime
rather than exposing general shell credentials. Environment variables are not a
substitute for explicit auth import because the sandbox environment is filtered
by design.

Model and provider resources follow the same rule: make the intended Pi runtime
configuration available, but avoid copying unrelated host state.

## 3. Sessions, extensions, and packages

Session state lives in the sandbox home/state area so repeated agent use can be
stable without writing into the real home directory. Extension and package
loading combines common and project resources, allowing project-local behavior
to travel with the repository.

Role resources are imported only through the role selection path. This keeps
`AGENT-010`, `AGENT-010a`, and `AGENT-010b` from becoming global configuration
side effects: role prompts, skills, and package additions apply when that role
is active.

## 4. Generated Pi-en coordination context

When the selected project has the project-local coordination checkout at
`.pi-en/coordination`, `pi-en-bwrap` appends an idempotent generated block to
the sandbox copy of `/home/pi/.pi/agent/AGENTS.md`. This makes the coordination
attachment visible to Pi at normal startup even though the coordination
repository is nested below `.pi-en/` and its own `AGENTS.md` is not discovered
by Pi's ancestor walk from `/workspace`.

The generated block is deliberately small and operational. It tells the agent
to read `/workspace/.pi-en/coordination/AGENTS.md`, prefer sandbox-safe
`pien coord ...` helpers for lifecycle changes, linting, repo registry changes,
and generated requirements views, and to respect `domain_generated_files` in
the current repo manifest before regenerating committed domain outputs. The
block is stripped and rewritten on each launch so stale coordination guidance is
removed when a later run uses the same state directory for a project without a
coordination checkout.

This generated context is Pi-en runtime guidance, not user-owned common
configuration. It must not overwrite common rules imported from the host/common
agent directory, and it must not relax sandbox credential or filesystem policy:
if helpers or Git credentials are unavailable inside the sandbox, the agent
should report that limitation instead of bypassing the helper-first protocol.

## 5. Precedence and diagnostics

When the same resource name appears in multiple scopes, project-specific data
wins over common data only in the documented project resource locations. The
launcher should report missing required resources and continue quietly for
optional directories that are absent.
