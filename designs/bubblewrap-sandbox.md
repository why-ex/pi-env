# Bubblewrap Sandbox Design

The Bubblewrap layer creates a constrained execution environment for Pi and
project commands. Its purpose is practical isolation: predictable project
paths, filtered environment, controlled host file exposure, and an explicit
network mode.

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-004 | PIEN-FRQ-20260612-210000-004 |
| UC-015 | PIEN-FRQ-20260612-210000-015 |
| UC-022 | PIEN-FRQ-20260612-210000-022 |
| UC-005 | PIEN-FRQ-20260612-210000-005 |
| UC-006 | PIEN-FRQ-20260612-210000-006 |
| UC-007 | PIEN-FRQ-20260612-210000-007 |
| UC-008 | PIEN-FRQ-20260612-210000-008 |
| UC-009 | PIEN-FRQ-20260612-210000-009 |
| PATH-001 | PIEN-FRQ-20260612-210000-048 |
| PATH-002 | PIEN-FRQ-20260612-210000-049 |
| PATH-003 | PIEN-FRQ-20260612-210000-050 |
| PATH-004 | PIEN-FRQ-20260612-210000-051 |
| PATH-005 | PIEN-FRQ-20260612-210000-052 |
| FS-001 | PIEN-FRQ-20260612-210000-053 |
| FS-002 | PIEN-FRQ-20260612-210000-054 |
| FS-003 | PIEN-FRQ-20260612-210000-055 |
| FS-004 | PIEN-FRQ-20260612-210000-056 |
| FS-005 | PIEN-FRQ-20260612-210000-057 |
| FS-006 | PIEN-FRQ-20260612-210000-058 |
| FS-007 | PIEN-FRQ-20260612-210000-059 |
| FS-008 | PIEN-FRQ-20260612-210000-060 |
| FS-009 | PIEN-FRQ-20260612-210000-061 |
| ENV-001 | PIEN-FRQ-20260612-210000-088 |
| ENV-002 | PIEN-FRQ-20260612-210000-089 |
| ENV-003 | PIEN-FRQ-20260612-210000-090 |
| ENV-004 | PIEN-FRQ-20260612-210000-091 |
| ENV-005 | PIEN-FRQ-20260612-210000-092 |
| NET-001 | PIEN-FRQ-20260612-210000-094 |
| NET-002 | PIEN-FRQ-20260612-210000-095 |
| CRQ-006 | PIEN-CRQ-20260612-210000-006 |
| CRQ-012 | PIEN-CRQ-20260614-180308-001 |
| CRQ-008 | PIEN-CRQ-20260612-210000-008 |
| CRQ-009 | PIEN-CRQ-20260612-210000-009 |

## 1. Project root and paths

The sandbox starts from one selected project root. Path requirements ensure
that the root is resolved consistently, mounted read-write at the fixed
in-sandbox location `/workspace`, and used as the working directory unless the
caller intentionally chooses a subdirectory. `/workspace` is a sandbox path
name for that one root, not a host-side workspace manager abstraction.

Host paths are not implicitly trusted. Only documented project, runtime, cache,
coordination, and temporary paths should be mounted. Project-local Pi-en
operational artifacts should be grouped under `.pi-en/` in the selected
project and are therefore visible through the normal `/workspace` mount;
examples include `.pi-en/coordination`, `.pi-en/agent-remotes`,
`.pi-en/locks`, and `.pi-en/logs`. Monorepos, submodules, worktrees,
integration checkouts, and other complex source layouts remain the selected
project's own policy; Pi-en only decides which project root is exposed for
this run. When a path is optional, missing host state should degrade to an
empty or freshly-created sandbox path rather than accidentally widening access.

## 2. Home and filesystem state

The sandbox uses an isolated home tree for Pi runtime state. Project files are
mounted separately from user home state so generated files, sessions, and
extension caches have clear ownership. Persistent sandbox Pi state remains
outside the project by default under the XDG state location because it can
contain copied auth files, Pi settings, sessions, imported common resources,
and caches. A user may explicitly opt into project-local sandbox state with
`PI_EN_BWRAP_STATE_DIR=$PWD/.pi-en/state`; Pi-en should not choose that path by
default. Read-only and read-write mounts are chosen by purpose: project work
needs writes, runtime inputs often do not.

`FS-001` through `FS-009` define the file exposure rules. They are implemented
as Bubblewrap mount choices, not as application-level checks after startup.
That makes violations visible in blackbox tests by inspecting the generated
Bubblewrap command.

## 3. Environment filtering

The launcher constructs an allowlist for environment variables. Variables that
select runtime behavior or safe terminal behavior may pass through; unrelated
host secrets should not. Explicit imports for auth or model configuration are
handled by the agent resource layer rather than broad environment copying.

Project-specific tool exposure uses the same allowlist approach. The sandbox
may accept a dedicated extra-path variable, but every entry must be explicit,
canonical, and constrained to read-only Nix-store paths by default. The
launcher must not scan all of `/nix/store`, inherit host `PATH`, or mount host
`/bin` or `/usr/bin` merely to discover project tools. Unsafe extra path
entries should fail closed before Pi starts.

## 4. Network mode and limits

Network access is explicit. `NET-001` and `NET-002` distinguish the default
network policy from requested network-enabled execution. `UC-015` combines this
with environment filtering so users can reduce network and environment exposure
for a run.

The same controls support `UC-022`: review and automation workflows can narrow
the selected project mount, tool access, environment variables, network access,
and state persistence when inspecting unfamiliar code.

The sandbox documents and tests the Bubblewrap flags used, but it is not a
complete security boundary against a malicious host or kernel. `CRQ-008` and
`CRQ-009` are therefore safety and disclosure requirements as much as
implementation requirements.
