# pi-env Requirements

This document is generated reference output for requirements that have active coordination requirement items. Requirement coordination items are the preferred source of truth when present; update them first, then regenerate `REQUIREMENTS.md`. `REQUIREMENTS.md` is a secondary fallback source only for project or requirement areas that do not yet have coordination items.

Each rendered requirement has a stable public key such as `UC-001`, `CMD-004`, or `FS-010`. Coordination items may have timestamped item IDs, but generated documentation preserves these stable keys as the public requirement identifiers.

## 1. Product scope

`pi-env` provides a reusable Nix development shell and Bubblewrap launcher for `pi-coding-agent`. Each run operates on one selected project root, and that root is mounted read-write at `/workspace` inside the sandbox. `/workspace` is the sandbox path name, not a host-side multi-project workspace manager.

Coordination support must be implemented as an opt-in layer. It must not make default `pi-env` startup create, claim, mark done, review, verify, close, commit, push, or otherwise mutate coordination state automatically. Any coordination helper that changes shared state must be explicit, inspectable, and backed by normal Git commits.

The project must keep two responsibilities separate:

- **Nix devshell/runtime:** reproducibly provide command-line tools on `PATH`.
- **Bubblewrap launcher:** isolate the `pi` process from the host filesystem and environment while still allowing controlled access to the selected project root and selected Pi state.

## 2. History-derived intent

The git history establishes these product requirements:

1. The project started as a Nix flake providing a Pi agent runtime devshell.
2. A startup command was added for running `pi` with an explicit tool allowlist and `--continue`.
3. The launcher evolved from an ad-hoc script to flake-generated commands.
4. The runtime became self-contained and no longer depends on a local `common-nix-runtime` flake.
5. Bubblewrap isolation became the primary runtime boundary.
6. Project-specific Pi sessions were intentionally exposed inside the sandbox, but only for the active project/path.
7. The flake is intended for reuse by other projects through `lib.mkPiShell` or packages.
8. Common Pi rules/skills/prompts/roles are imported from an external user-controlled directory, not shipped by `pi-env`.
9. Host Git configuration is copied into the sandbox by default, but credentials, SSH keys, and host home are not mounted.

## 3. Functional requirements

### 3.1 Workflow-level functional requirements

Workflow-level requirements describe user goals that the detailed requirements must support. They are functional requirements with requirement kind `workflow`.

#### UC-001 — Run Pi in the current repository

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: FLAKE-006, CMD-003, CMD-005, CMD-018, PATH-001, PATH-004, PATH-005, AGENT-011

A user must be able to enter the `pi-env` development shell and run Pi for the current repository:

```bash
nix develop
pi-env
```

Default `pi-env` startup must start Pi through Bubblewrap with the default built-in tool allowlist:

```text
read,bash,edit,write,grep,find,ls
```

Default `pi-env` startup must run Pi with `--continue` so existing scoped sessions for the current project can be resumed.

#### UC-002 — Run Pi with custom arguments

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: CMD-001, CMD-004, CMD-006, CMD-007

A user must be able to invoke `pi-env-bwrap` directly when they want to pass custom Pi arguments instead of the default startup arguments:

```bash
pi-env-bwrap -- --model anthropic/claude-sonnet-4-5 "Inspect this repo"
```

If no arguments are supplied, `pi-env-bwrap` must default to the invocation in CMD-004. `pi-env-bwrap --help` must show launcher help. `pi-env-bwrap -- --help` must pass `--help` to Pi itself.

#### UC-003 — Use a reproducible Pi runtime shell

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: FLAKE-006, RUNTIME-001, RUNTIME-002

Inside `nix develop`, `pi-env` must provide a reproducible toolset on `PATH`, including Bash and core GNU utilities, Bubblewrap, Git, Node.js, ripgrep, fd, jq, tar, gzip, find, grep, sed, awk, and CA certificates.

#### UC-004 — Run Pi inside a filesystem sandbox

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: PATH-004, FS-001, FS-007, FS-008, FS-010, ENV-001, ENV-003, NET-001

A user must be able to run Pi with access to the current project but without exposing the whole host home directory. By default the sandbox mounts the selected project read-write at `/workspace`, uses an isolated sandbox home at `/home/pi`, mounts `/nix/store` read-only, exposes global npm Pi install paths read-only when present, avoids sensitive host mounts, clears the environment, and shares the host network unless disabled.

#### UC-005 — Select what project Pi can see

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: PATH-001, PATH-002, PATH-003, PATH-004, PATH-005

A user must be able to control which project root is exposed in the sandbox. The default selection is the Git repository root when detected, falling back to the current working directory. Users must be able to disable Git-root detection with `PI_ENV_BWRAP_USE_GIT_ROOT=0` and provide an explicit project root with `PI_ENV_BWRAP_PROJECT_ROOT=/path/to/repo`.

#### UC-006 — Keep per-project sandbox state

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: FS-002, FS-003, FS-005, FS-006

By default, `pi-env` must store persistent sandbox state outside the
project under `$XDG_STATE_HOME/pi-env/<project-hash>` or
`$HOME/.local/state/pi-env/<project-hash>` because that state may contain
copied model auth, sandbox Pi settings, sessions, imported common agent
resources, and caches. Users must be able to override the state directory
with `PI_ENV_BWRAP_STATE_DIR=/path/to/state`, including an explicit opt-in
project-local value such as `PI_ENV_BWRAP_STATE_DIR=$PWD/.pi-env/state`.

#### UC-007 — Run with an ephemeral sandbox home

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: FS-004, AGENT-011, AGENT-012

A user must be able to request disposable sandbox state with `PI_ENV_BWRAP_EPHEMERAL_HOME=1`. Project session import must be disabled by default for ephemeral homes unless explicitly enabled.

#### UC-008 — Import Pi model authentication into the sandbox

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: AGENT-002, AGENT-007, AGENT-008, AGENT-009, FS-006

By default, `pi-env-bwrap` must copy only selected Pi auth/model files from the host Pi agent directory into sandbox state: `auth.json` and `models.json`. Users must be able to disable this behavior with `PI_ENV_BWRAP_IMPORT_AUTH=0` and copy only missing files with `PI_ENV_BWRAP_AUTH_SYNC=missing`.

#### UC-009 — Resume only the current project's Pi sessions

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: AGENT-011, AGENT-012, AGENT-013, AGENT-014, AGENT-015

For persistent homes, `pi-env` must bind-mount only the Pi session directory corresponding to the current working directory/project path. Users must be able to disable session import with `PI_ENV_BWRAP_IMPORT_SESSIONS=0` and enable it explicitly, including for ephemeral homes, with `PI_ENV_BWRAP_IMPORT_SESSIONS=1`.

#### UC-010 — Use common Pi rules, skills, prompts, and roles

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: AGENT-002, AGENT-003, AGENT-004, AGENT-005, AGENT-006

`pi-env` must support importing common user-owned Pi resources into the sandbox agent directory. Only `AGENTS.md`, `CLAUDE.md`, `SYSTEM.md`, `APPEND_SYSTEM.md`, `skills/`, `prompts/`, and `roles/` may be imported as common resources. Users must be able to set `PI_ENV_BWRAP_COMMON_AGENT_DIR`, disable import with `PI_ENV_BWRAP_IMPORT_COMMON=0`, and use `PI_ENV_BWRAP_COMMON_SYNC=missing`.

#### UC-011 — Combine common and project-specific Pi behavior

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: PATH-004, AGENT-004, AGENT-010, AGENT-010a

A user must be able to combine common personal/team rules, skills, prompts, and roles outside the project with project-specific Pi resources committed inside the project. Pi must be able to load imported common/global resources from `/home/pi/.pi/agent` and discover project-specific resources from `/workspace`.

#### UC-012 — Use Pi extensions and packages

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: AGENT-010, AGENT-010a, AGENT-010b, CMD-003, CMD-004, CMD-005

Project-local extensions and project-installed packages under `.pi/` must be available through `/workspace`. Global Pi extensions and globally installed Pi packages from the host Pi agent directory must be exposed by default according to AGENT-010. Users must be able to disable global extension/package import with `PI_ENV_BWRAP_IMPORT_EXTENSIONS=0`.

#### UC-013 — Use host Git preferences without exposing credentials

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: GIT-001, GIT-002, GIT-003, GIT-004, GIT-005, GIT-006, GIT-007, GIT-008

`pi-env` must copy host Git configuration into the sandbox by default so Git commands use normal identity, aliases, default branch names, and diff preferences. Git credentials, SSH keys, signing keys, credential-helper stores, and referenced secret files must not be imported automatically. Users must be able to disable Git config import and override config source paths.

#### UC-014 — Customize Pi tool access

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: CMD-003, CMD-004, CMD-005

A user must be able to override the default Pi tool allowlist with `PI_ENV_BWRAP_DEFAULT_TOOLS`, for least-privilege runs, tool experiments, or extension/custom tools registered with Pi.

#### UC-015 — Control network and environment exposure

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: ENV-001, ENV-002, ENV-003, ENV-004, ENV-005, NET-001, NET-002

The sandbox must share host networking by default for model provider access, allow users to disable network sharing with `PI_ENV_BWRAP_NET=0`, and allow selected extra environment variables through `PI_ENV_BWRAP_PASS_ENV`.

#### UC-016 — Use with a globally installed Pi CLI

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: FS-008, RUNTIME-002

If Pi is installed globally via npm, `pi-env-bwrap` must be able to run it by mounting `/usr/local/bin` and `/usr/local/lib/node_modules/@earendil-works/pi-coding-agent` read-only when present.

#### UC-017 — Reuse `pi-env` from a new project flake

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: FLAKE-001, FLAKE-002, FLAKE-003, FLAKE-006

A project without an existing flake must be able to add `pi-env` as an input and use `mkPiShell`, then run `nix develop` and `pi-env`.

#### UC-018 — Add Pi wrappers to an existing project devshell

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: FLAKE-004, CMD-001, CMD-018

A project that already has a flake/devshell must be able to keep its existing shell and add the `pi-env`, `pi-env-shell`, and `pi-env-bwrap` wrapper packages.

#### UC-019 — Use `pi-env` as a flake package or app

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: FLAKE-004, FLAKE-005

Users must be able to use exposed packages and apps such as `default`,
`pi-env`, `pi-env-shell`, `pi-env-bwrap`, `pi-core`,
`pi-env-coordination`, and the compatibility `pi-runtime` bundle through
commands like `nix run .#pi-env -- ...`,
`nix run .#pi-env-bwrap -- ...`, `nix build .#pi-core`, and
`nix build .#pi-runtime`.

#### UC-020 — Use the library API in other flakes

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: FLAKE-003

Other flakes must be able to use the `pi-env` library API to construct project-specific shells, packages, or wrappers while reusing the same runtime and Bubblewrap behavior.

#### UC-021 — Test or validate the environment

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: TEST-001 through TEST-031

A user must be able to validate `pi-env` through blackbox-style checks including `nix flake show`, package builds, coordination helper tests, role-manager smoke tests, and fake-`pi` sandbox inspections.

#### UC-022 — Safer code-review and automation workflows

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: UC-004, UC-007, UC-014, UC-015, FS-010, GIT-007, NET-002

The isolated launcher must support safer workflows such as reviewing unfamiliar repositories, limiting Pi to the selected project root mounted at `/workspace`, avoiding accidental access to host secrets, using reduced tool allowlists, disabling network, using ephemeral state, and importing only the auth/session/config needed for the current project.

#### UC-023 — Coordinate multiple agents with Git

- Type: Functional requirement
- Requirement kind: workflow
- Related requirements: CMD-009 through CMD-015, ENV-006, FS-010

For projects where several agents coordinate through separate clones,
`pi-env` must optionally help establish and maintain a dedicated Git-backed
project coordination repository. Fresh project-local operational artifacts
for this workflow, including the coordination working clone and local bare
remotes, must live under `.pi-env/` by default. Agents synchronize only by
normal Git pull/commit/push operations. This use case remains opt-in, and
default `pi-env` startup behavior must not mutate coordination state automatically.
A coordination domain can cover multiple implementation repositories, but
each pi-env invocation remains attached to one selected implementation repo.
The coordination clone contains root `PROJECT.md`, shared `requirements/`,
`todos/`, `decisions/`, and `notes/` entries, plus repo-scoped issue
namespaces under `repos/<repo_id>/issues/<status>`. Each issue belongs to
exactly one implementation repo by path; cross-repo work should use one issue
per repo linked by stable item IDs. Each `repos/<repo_id>/REPO.md` may define
domain-wide generated files that are committed by that implementation
repository, using repo-root relative paths such as `REQUIREMENTS.md` or
`REQUIREMENTS_COVERAGE.md`. More than one active implementation repo may
list the same generated path when multiple committed copies are useful.

#### UC-024 Serial role automation workflow

A user must be able to run one serial automation loop over a single
project checkout and one coordination checkout. The loop polls the
coordination repository, selects one eligible issue, runs exactly one
developer, reviewer, or tester Pi job for that issue, waits for the job to
finish, and then returns to polling.

The serial workflow must avoid concurrent writes to the project and
coordination working trees. Its generated operational artifacts, such as
local locks and optional logs, must live under `.pi-env/` by default. It is
the first automation step before any future tmux, multi-clone, or parallel
worker design.

Acceptance criteria:

- The documented workflow uses one orchestrator process rather than three
  parallel terminals.
- The orchestrator prefers downstream work before new development:
  tester-eligible items, then reviewer-eligible items, then open developer
  items.
- Each selected issue is handled in a fresh Pi session, not by continuing
  a previous role session.
- The design explains that tmux and per-role clone locking are deferred
  until a later parallel-worker phase.

#### UC-025 Host runtime sandbox default workflow

A user must be able to run `pi-env` from a normal checkout without first
entering `nix develop` and without `pi-env` automatically invoking Nix.
The default direct-launch behavior should run Pi inside the Bubblewrap
workspace sandbox using a conservative, allowlisted host runtime.

Nix remains a first-class reproducible runtime. Users must be able to opt
into the Nix-backed runtime explicitly, and invocations that already enter
through Nix package, app, profile, or development-shell outputs may continue
to use the Nix-backed runtime by default.

Acceptance criteria:

- Direct checkout `pi-env` starts in host runtime mode unless the caller
  requests another runtime.
- `pi-env --runtime host` and `PI_ENV_RUNTIME=host` select host runtime
  mode explicitly.
- `pi-env --runtime nix` and `PI_ENV_RUNTIME=nix` select the existing
  pinned Nix runtime behavior.
- The command output or diagnostics make the selected runtime mode clear
  when reporting missing tools or startup failures.
- Bubblewrap sandboxing, isolated HOME, filtered environment, and the
  `/workspace` project mount remain the default in both runtime modes.

### 3.2 Flake and package requirements

#### FLAKE-001 Inputs

The flake must declare only these normal inputs:

- `nixpkgs` pointing at `github:NixOS/nixpkgs/nixos-25.05`
- `flake-utils` pointing at `github:numtide/flake-utils`

It must not require a local `common-nix-runtime` or other machine-specific flake input.

#### FLAKE-002 Systems

The flake must use `flake-utils.lib.eachDefaultSystem` to expose packages, apps, and devshells for default systems.

#### FLAKE-003 Library API

The flake must expose `lib` attributes:

- `defaultTools`
- `mkRuntime`
- `mkPiBwrap`
- `mkPiEnv`
- `mkPiEnvShell`
- `mkPiShell`
- `mkRoleManagerPackage`

`mkPiShell` must accept `includeCoordinationHelpers` with a compatibility
default of `true`; setting it to `false` must omit the optional
coordination helper commands from the shell.

#### FLAKE-004 Packages

For each supported system the flake must expose packages:

- `default` equal to `pi-env`
- `pi-env`
- `pi-env-shell`
- `pi-env-bwrap`
- `pi-core` for core runtime commands and tools only
- `pi-env-coordination` for the optional Git-backed coordination helpers
- `pi-runtime` as a combined bundle containing `pi-core` plus
  `pi-env-coordination`
- `pi-role-manager`
- `pi-env-bootstrap-coordination`
- `pi-env-coord-init`
- `pi-env-coord-clone`
- `pi-env-coord-new`
- `pi-env-coord-status`
- `pi-env-coord-list`
- `pi-env-coord-cat`
- `pi-env-coord-lint`
- `pi-env-coord-pull`
- `pi-env-coord-push`
- `pi-env-coord-claim`
- `pi-env-coord-done`
- `pi-env-coord-review`
- `pi-env-coord-verify`
- `pi-env-coord-close`
- `pi-env-coord-generate-requirements`
- `pi-env-coord-generate-requirements-coverage`
- `pi-env-coord-upgrade-rules`
- `pi-env-serial-roles`

#### FLAKE-005 Apps

For each supported system the flake must expose apps:

- `default` running `pi-env`
- `pi-env`
- `pi-env-shell`
- `pi-env-bwrap`

#### FLAKE-006 Devshell

The default devshell must include the runtime packages, wrappers, and
coordination helpers, and must print a helpful startup message unless
`PI_ENV_QUIET` is set. The reusable `mkPiShell` must keep that default for
compatibility while allowing `includeCoordinationHelpers = false` to omit the
optional coordination helper commands from consuming project shells.

The shell prompt must be prefixed with `(nix-dev)`. The shell must export
`PI_ENV_ROLE_MANAGER_PACKAGE` to the Nix-built role-manager Pi package path.

### 3.3 Runtime package requirements

#### RUNTIME-001 Included tools

`mkRuntime` must include at least:

- `bash`
- `bubblewrap`
- `cacert`
- `coreutils`
- `fd`
- `findutils`
- `gawk`
- `git`
- `gnugrep`
- `gnused`
- `gnutar`
- `gzip`
- `jq`
- `nodejs`
- `ripgrep`
- `which`

#### RUNTIME-002 Path construction

`pi-env-bwrap` must prepend the runtime package bin path to the host `PATH` before checking for `pi`.

#### RUNTIME-003 Project-declared Nix tool PATH exposure

`pi-env` must let projects that consume `pi-env.lib.mkPiShell` expose
their declared Nix `extraPackages` command directories inside the
Bubblewrap sandbox without expanding host filesystem access.

`mkPiShell` must derive the executable search path for `extraPackages`
from Nix package outputs, using the package `bin` directories normally
produced by Nix path construction, and export that list through a
dedicated pi-env environment variable for `pi-env-bwrap`.

`pi-env-bwrap` must add the validated extra command directories to the
sandbox `PATH` after the core pi-env runtime path and before host/global
fallback locations such as `/usr/local/bin`, `/usr/bin`, and `/bin`.
The core pi-env runtime must therefore keep precedence for launcher
dependencies, while project-declared tools such as `make`, `gcc`,
`pkg-config`, or `cmake` become discoverable to Pi tool commands.

Direct `nix run github:u2up/pi-env` usage is not required to infer a
target project's build tools automatically. Projects that need build or
test tools inside the sandbox should either integrate pi-env through a
project flake/devshell or use an explicit, documented extra-path opt-in.

#### RUNTIME-004 Runtime mode selection

The launcher stack must support explicit runtime modes named `host` and
`nix`. Runtime mode may be selected by a command-line option such as
`--runtime host|nix|auto` or by `PI_ENV_RUNTIME=host|nix|auto`, with the
command-line option taking precedence over the environment variable.

Direct checkout use should default to host runtime mode. Nix-provided
package, app, profile, and development-shell entrypoints should keep using
Nix-backed paths unless the implementation explicitly documents and tests a
safe host-mode override for those entrypoints.

Runtime mode selection must be resolved before any fallback that would
invoke `nix develop`. If host mode is selected and required host tools are
missing, the launcher must fail with host-mode diagnostics rather than
silently entering Nix.

#### RUNTIME-005 Host runtime dependency preflight

Host runtime mode must validate required host commands before constructing
the Bubblewrap command. At minimum, host mode must check for the commands
needed by the launcher itself, Bubblewrap, project-root detection, state
preparation, and Pi startup.

Missing dependency diagnostics must:

- identify that the selected runtime is `host`;
- list the missing command names;
- explain that host runtime tools are not pinned by pi-env;
- suggest installing missing host packages or retrying with the Nix runtime.

The implementation may treat some commands as optional when the feature that
needs them is disabled, but optionality must be documented and tested.

#### INSTALL-001 Non-Nix installation support

pi-env should provide a supported non-Nix installation path for users who
want the host-runtime workflow without entering a Nix development shell or
consuming a flake output. The non-Nix installer must install the pi-env
command wrappers and support files that Nix packages normally place on
`PATH` or expose through environment variables.

The installation path should, at minimum, support a user-local prefix such as
`~/.local` and should be adaptable to a system prefix such as `/usr/local`
when run with appropriate permissions. Installed commands must be able to
locate their support files without requiring the user to keep running from a
source checkout.

Installation and deinstallation should not require cloning the full pi-env
repository. The project may support direct checkout installation as a
contributor convenience, but end-user install and uninstall flows should work
from a published release artifact, downloaded installer, or already installed
manifest/uninstall command.

Installed support files must include the coordination helper library,
coordination templates, and role-manager package data needed by:

- `pi-env`, `pi-env-shell`, and `pi-env-bwrap`;
- `pi-env-bootstrap-coordination`;
- `pi-env-coord-*` helper commands;
- `pi-env-serial-roles`.

The non-Nix installer may rely on host-provided runtime tools such as Bash,
Bubblewrap, Git, jq, ripgrep, fd, Node, and the host `pi` command. It must
not describe those tools as pinned or reproducible by pi-env. User-facing
output and documentation must clearly state that Nix remains the
reproducible pinned runtime while the non-Nix install uses host tools.

Acceptance criteria:

- A non-Nix user can install pi-env commands and support files under a chosen
  prefix without invoking Nix or cloning the full pi-env repository.
- Installed command wrappers set or otherwise resolve the equivalent support
  paths for `PI_ENV_COORD_LIB`, `PI_ENV_COORD_TEMPLATE_DIR`, and
  `PI_ENV_ROLE_MANAGER_PACKAGE`.
- The installer checks or documents required host dependencies and reports
  missing dependencies with host-runtime wording.
- An uninstall or cleanup path is documented or provided for files installed
  by the non-Nix installer, and it can run without access to the original
  source checkout.
- README installation guidance distinguishes direct checkout, non-Nix
  installed host runtime, and Nix-backed reproducible runtime workflows.
- Existing direct-checkout and Nix flake/devshell workflows remain
  compatible.

#### RUNTIME-006 — Nix runtime agent devshell selection

When `pienv --runtime nix`, `pi-env --runtime nix`, or `pi-env-shell
--runtime nix` enters a target project flake, pi-env should prefer a
pi-env-aware agent devshell when the project provides one.

The preferred convention is `devShells.<system>.agent`, selected by the flake
reference fragment `.#agent`. If that shell exists, Nix runtime startup should
enter it instead of the default devshell so `pienv` uses the project-declared
agent shell, runtime wiring, extra packages, and optional coordination
helpers.

For backward compatibility, projects may define `.#agent` as an alias of
their normal default shell when no separate agent policy is needed. pi-env
must not require the alias for older flakes: if no agent devshell exists, Nix
runtime startup must continue to use the existing default `nix develop`
behavior.

pi-env must not silently fall back to the default devshell when an explicitly
selected or discovered `.#agent` shell exists but fails to evaluate or build;
that failure is actionable project configuration feedback and should be
reported.

The runtime should also provide an explicit selector override, such as a
`--devshell NAME` command-line option and `PI_ENV_NIX_DEVSHELL=NAME`, so
users can force `agent`, `default`, or another project shell without relying
on automatic discovery. Command-line selection must take precedence over the
environment variable.

#### INSTALL-002 Remote-ref non-Nix installer bootstrap

The non-Nix installer should be able to run as a small bootstrap script when
the full pi-env payload is not already present locally. In bootstrap mode, it
must fetch an explicit pi-env source artifact, unpack it to a temporary
directory, and continue installation from that artifact using the same
installed file layout as local payload installs.

The bootstrap interface must support installing from the upstream `main`
branch when the user explicitly requests that ref. Main-branch installation is
mutable and not reproducible, so it must be documented as a development or
latest channel rather than the recommended stable path. Tagged release refs or
release artifacts should remain the preferred stable installation channel.

The installer should record origin information in installed state or the
install manifest when available, including the repository, ref or version,
artifact URL, and checksum if one was verified. Future upgrade and uninstall
behavior may use this origin metadata, but uninstall must not require network
access or the original source checkout.

Acceptance criteria:

- A user can bootstrap installation without cloning the full repository by
  running the installer script and passing an explicit remote ref such as
  `--ref main`.
- `--ref main` fetches the GitHub branch archive or equivalent artifact for
  the configured repository, then installs from the fetched payload.
- Stable documentation prefers tagged releases or release artifacts and labels
  `main` installation as mutable, development/latest, and not reproducible.
- The installer supports configurable origin inputs such as repository and/or
  artifact URL while preserving safe defaults for the upstream pi-env repo.
- The installer records origin metadata in the install manifest or adjacent
  installed state when the install came from a remote artifact.
- Bootstrap downloads use a temporary directory and clean it up after success
  or failure where practical.
- Uninstall continues to work from installed state without network access,
  the original source checkout, or the downloaded temporary artifact.
- Existing local payload installation from a checkout or release archive
  remains compatible.

### 3.4 Command requirements

#### CMD-001 `pi-env-bwrap` existence

The package `pi-env-bwrap` must install an executable named `pi-env-bwrap`.

#### CMD-002 `pi-start` removal

The project must not expose `pi-start` as a package, app, installed
executable, devshell command, or direct-checkout wrapper. Default Pi startup
must be available through `pi-env`; shell startup must be available through
`pi-env-shell`; low-level sandbox/custom Pi invocation must remain available
through `pi-env-bwrap`.

#### CMD-003 Default tool allowlist clarification

This requirement defines the canonical global default Pi tool list only.
Role-specific tool allowlists are distinct active-role runtime settings
and are covered by `PIENV-FRQ-20260612-210000-047`.

#### CMD-004 `pi-env-bwrap` default invocation

When called without Pi arguments, `pi-env-bwrap` must run Pi with:

```bash
pi --tools read,bash,edit,write,grep,find,ls --continue
```

or with the same structure but replacing the tool list with `PI_ENV_BWRAP_DEFAULT_TOOLS` when set.

#### CMD-005 Default `pi-env` invocation

Default `pi-env` startup must run `pi-env-bwrap` with:

```bash
--tools "$tools" --continue "$@"
```

where `$tools` is the default tool list or `PI_ENV_BWRAP_DEFAULT_TOOLS`
when set. This behavior must be implemented without a separate `pi-start`
command.

#### CMD-006 Argument separator

`pi-env-bwrap -- <args>` must strip the separator and pass `<args>` to Pi.

#### CMD-007 Help

`pi-env-bwrap -h` and `pi-env-bwrap --help` must print launcher help and exit successfully without entering Bubblewrap.

#### CMD-008 Missing Pi executable

If `pi` is not found on `PATH` before sandbox entry, `pi-env-bwrap` must exit with code `127` and print an actionable error.

#### CMD-009 Coordination helper commands

The flake/devshell must provide these opt-in coordination commands:

- `pi-env-bootstrap-coordination`
- `pi-env-coord-init`
- `pi-env-coord-clone`
- `pi-env-coord-status`
- `pi-env-coord-list`
- `pi-env-coord-pull`
- `pi-env-coord-push`
- `pi-env-coord-new`
- `pi-env-coord-claim`
- `pi-env-coord-done`
- `pi-env-coord-review`
- `pi-env-coord-verify`
- `pi-env-coord-close`
- `pi-env-coord-lint`
- `pi-env-coord-upgrade-rules`

`pi-env-bootstrap-coordination` must provide the high-level setup path for
attaching an implementation repository to a coordination domain. By default
it prints the inferred `PI_ENV_COORD_*` settings and the corresponding
initialization command, records the selected remote as
`.pi-env-coordination.yaml` `coordination_remote` on real bootstraps, then
initializes or clones with those explicit values unless `--print-only` or
`--dry-run` is used. When project values are unset, it must infer useful
domain defaults from `PI_ENV_COORD_PROJECT`, the Git origin repository name,
the Git root basename, or the current directory basename, in that order. It
must support `--project-root DIR` to infer and initialize relative to another
project directory; when doing so, stale context values from
`PI_ENV_COORD_DIR`, `PI_ENV_COORD_PROJECT`, and `PI_ENV_COORD_PROJECT_KEY`
must not override the target directory's inferred defaults unless explicit
options are supplied. If the selected coordination clone already exists but
the planned local bare remote is missing or does not contain the clone's
current branch, it must restore that bare remote from committed clone
history, adding `origin` when absent and updating `origin` only when it
points to a missing local path.

Bootstrap must distinguish domain-level options from implementation-repo
options. `--project` names the coordination domain and `--project-key`
selects the domain-level item ID prefix stored in root `PROJECT.md`; neither
option identifies the implementation repository namespace. A separate
implementation `repo_id` must identify the current implementation repo.
Repeatable `--domain-generated-file PATH` options must populate the resolved
implementation repo manifest's `domain_generated_files` list in first-seen
order without duplicates. Paths must be implementation-repo-root-relative;
empty paths, absolute paths, and `..` traversal components are invalid.
`--print-only` and `--dry-run` plans must show the requested generated-file
settings without mutating coordination state.

For existing coordination domains, bootstrap should support an explicit
registration mode that attaches the current implementation repo and, only
when requested, mutates shared coordination state. A real bootstrap may write
`.pi-env-coordination.yaml` `repo_id` for the implementation repo. When an
explicit registration option is provided, it may create the missing
`repos/<repo_id>/REPO.md` manifest and issue-status directories, including any
provided `domain_generated_files`, then commit and push that coordination-domain
registry change. Existing registered repo manifests may be explicitly updated
with a provided `domain_generated_files` list during bootstrap, committing and
pushing when that manifest changes. Without the explicit registration option,
bootstrap must not silently add a repo namespace; it should report that the repo
id is unregistered and tell the user how to register it.

`--print-only`/`--dry-run` must not create, restore, register, commit, push,
or otherwise mutate anything. Default `pi-env` startup and non-registration
bootstrap paths must not claim, mark done, review, verify, close, or
otherwise mutate item state automatically.

#### CMD-010 `pi-env-coord-init`

`pi-env-coord-init` must create a local bare coordination remote and, unless
`--bare-only` is used, clone and scaffold a working coordination repository.
It must install the rule/protocol templates into:

- `AGENTS.md`
- `docs/SYNC_PROTOCOL.md`
- `docs/ITEM_FORMAT.md`
- `.pi/skills/agent-coordination/SKILL.md`

It must also create the standard coordination-domain skeleton: top-level
`PROJECT.md` item-key metadata; shared `requirements`, `decisions`, `notes`,
and `agents` directories; and an initial implementation namespace at
`repos/<repo_id>/issues/open`, `repos/<repo_id>/issues/blocked`,
`repos/<repo_id>/issues/done`, and `repos/<repo_id>/issues/closed` with a
`repos/<repo_id>/REPO.md` registry manifest. The clone must be configured
with `pull.rebase=true` and `rebase.autoStash=true`.

When `--dir` and `PI_ENV_COORD_DIR` are omitted, fresh project-local
coordination bootstraps must place the working clone at
`<project-root>/.pi-env/coordination`, visible inside the sandbox as
`/workspace/.pi-env/coordination` when the selected project is mounted there.

When no explicit/configured coordination remote is selected and `--root` and
`PI_ENV_COORD_ROOT` are omitted, coordination helpers must use a project-visible
`.pi-env/agent-remotes` directory instead of the isolated sandbox `$HOME`. If
`/workspace` resolves to the current project root, the default root must be
`/workspace/.pi-env/agent-remotes`; otherwise it must be
`<project-root>/.pi-env/agent-remotes`.

#### CMD-011 `pi-env-coord-clone`

`pi-env-coord-clone` must clone a coordination remote into the selected
coordination clone directory and configure the clone with `pull.rebase=true`
and `rebase.autoStash=true`. When no clone directory is selected with
`--dir` or `PI_ENV_COORD_DIR`, the default target must be
`<project-root>/.pi-env/coordination`. Explicit `--dir` or `PI_ENV_COORD_DIR`
values may select another coordination clone path.

#### CMD-012 `pi-env-coord-new`

`pi-env-coord-new` must create a YAML item with a type-coded timestamp ID,
top-level current-state fields, `done: null`, `closed: null`,
`reviewed: false`, `verified: false`, `testable: yes|no`, title,
acceptance-criteria placeholder, chronological `events`, and linked Markdown
`messages`. It must not commit or push automatically.

For issue items, `pi-env-coord-new` must accept optional `--category CATEGORY`
metadata. Supported built-in categories should include `bug`,
`feature-request`, `task`, `question`, and `improvement`; project-specific
slugs may be accepted for local categorization. New issue items must write
the category as a top-level `category:` field and must not write the legacy
`issue_type:` field. Because there are no external coordination repositories
requiring compatibility, `--issue-type` must not remain as a compatibility
alias. `task` and `tasks` must not be accepted as structural
`--type` aliases; task-category work must be created as
`--type issue --category task`.

The generated item ID prefix must resolve in this order:

1. explicit `--project-key`;
2. stored `item_key` metadata in root `PROJECT.md`;
3. `PI_ENV_COORD_PROJECT_KEY` when no stored key exists;
4. derived `--project` / `PI_ENV_COORD_PROJECT` for project items;
5. derived coordination clone directory name when no project name is set.

Derived keys must be uppercased with delimiters, whitespace, pipes,
slashes, backslashes, and other non-alphanumeric characters removed. Unless
`--id` is provided, generated IDs must use:

```text
<PROJECTKEY>-<TYPECODE>-<YYYYMMDD-HHMMSS>-<NNN>
```

Built-in type codes must include `ISS` for `issue`, `FRQ` for
`functional-requirement`, `QRQ` for `quality-requirement`, `CRQ` for
`constraint-requirement`, `TODO` for `todo`, `DEC` for `decision`, and `NOTE`
for `note`. The `NNN` suffix must start
at `001` for each timestamp and increment to avoid collisions in the local
coordination checkout. Filenames for new generated items must use the item ID
only. `--id` must override the whole item ID.

Domain item keys must be stored in top-level `PROJECT.md` as `item_key`.
Repo-scoped issue keys may come from `repos/<repo_id>/REPO.md`. When
`--project` is omitted in a coordination-domain clone, domain-common item
paths must be used even if `PI_ENV_COORD_PROJECT` is set for domain selection.
Issue items must be created under `repos/<repo_id>/issues/open`, resolving
the repo id from `--repo-id`, `PI_ENV_COORD_REPO_ID`, `.pi-env-coordination.yaml`,
or registry remote metadata. Functional, quality, constraint, and legacy
generic requirement items must be created under the root-level
`requirements/` directory while preserving FRQ, QRQ, and CRQ item-ID type
codes. Decision, note, and custom item types must be created under semantic
type directories by default. Existing historical items must not be silently
renumbered or rewritten only to satisfy newer naming conventions.

#### CMD-013 Coordination lifecycle helpers

The lifecycle helpers must remain thin wrappers around Git and YAML item
file edits:

- `pi-env-coord-status` shows Git status and open/blocked/done item summaries;
- `pi-env-coord-list` lists issue, TODO, note, decision, legacy requirement,
  or requirement-class IDs, statuses, and titles, optionally filtered by
  status, appends done-issue review/verification sub-status after the title,
  and supports issue category filtering/grouping with `--category`,
  `--show-category`, and `--group-by-category`;
- `pi-env-coord-pull` runs `git pull --rebase --autostash`;
- `pi-env-coord-push` commits staged/all changes and pushes;
- coordination commands that create item events or commits accept
  `--role ROLE`, read `PI_ENV_COORD_ROLE`, store actor ID/role metadata in
  events, and use per-command Git identity overrides for coordination
  commits;
- `pi-env-coord-claim` pulls, sets `status: claimed`, sets `owner:`, updates
  `current:`, appends a `claimed` event/message, commits, and pushes unless
  disabled by options;
- `pi-env-coord-done` pulls, moves issue items to `done/`, sets
  `status: done`, `done: <timestamp>`, `closed: null`, `reviewed: false`,
  and `verified: false`, appends a `done` event/message with optional
  structured implementation refs (`repo`, `branch`, full `commit`), commits,
  and pushes unless disabled by options. Its `--implementation-ref` option may
  accept `repo:branch@full-commit` as a compact CLI input format;
- `pi-env-coord-review` pulls, marks done items reviewed on pass, or moves
  them back to `open/` with `reviewed: false`, `verified: false`, and a
  `review_failed` event on failure, then commits and pushes unless disabled
  by options;
- `pi-env-coord-verify` pulls, marks done items verified on pass, or moves
  them back to `open/` with `reviewed: false`, `verified: false`, and a
  `verification_failed` event on failure, then commits and pushes unless
  disabled by options;
- `pi-env-coord-close` pulls, requires `status: done`, `reviewed: true`, and
  `verified: true` unless forced, moves issue items to `closed/`, sets closed
  YAML current-state fields, appends a `closed` event/message, commits, and
  pushes unless disabled by options.

Commands that create commits must reject subject lines longer than 72
characters.

#### CMD-014 `pi-env-coord-lint`

`pi-env-coord-lint` must inspect coordination items and item-matched tests. It
must check issue status-directory consistency, closed issue review and
verification flags, new-format item ID/type-code consistency, item filename
stems for new-format IDs, `testable: yes|no`, required `testability_note` for
`testable: no`, required executable test scripts for `testable: yes`, and
orphan scripts under `tests/items`. Its `--require-done-or-closed` option
must fail when any issue item is not `done` or `closed`.

Item-matched tests must live in the project repository under paths such as
`tests/items/issues/<item-id>.sh` and
`tests/items/requirements/<item-id>.sh`; they must not mirror issue status
directories.

#### CMD-015 `pi-env-coord-upgrade-rules`

`pi-env-coord-upgrade-rules --preview` must show template diffs without
changing files. Without `--preview`, it must require a clean worktree, copy
bundled coordination rule templates into their installed locations, and
commit the changes when any template differs. It must not push unless
`--push` is used.

#### CMD-016 Built-in role tool allowlists

The role-manager package must preserve bundled role metadata, including
role-specific tool allowlists, when loaded from this repository or as an
external Pi package. Activating a bundled role must request its declared
tool set from the host Pi runtime and warn with the missing tool names
when any requested tool is not registered.

The bundled `architect` role must include `read`, `grep`, `find`, `ls`,
`bash`, `edit`, and `write` so architecture work can inspect files,
create/edit Markdown or YAML documents, and run coordination or Git
commands.

#### CMD-017 Built-in role tool allowlists

The role-manager package must preserve bundled role metadata, including
role-specific tool allowlists, when loaded from this repository or as an
external Pi package. Activating a bundled role must request its declared
tool set from the host Pi runtime and warn with the missing tool names
when any requested tool is not registered.

Bundled base roles must declare these tool allowlists:

- `architect`: `read`, `grep`, `find`, `ls`, `bash`, `edit`, `write`
- `developer`: `read`, `grep`, `find`, `ls`, `edit`, `write`, `bash`
- `builder`: `read`, `grep`, `find`, `ls`, `bash`, `edit`
- `tester`: `read`, `grep`, `find`, `ls`, `bash`, `edit`, `write`
- `reviewer`: `read`, `grep`, `find`, `ls`, `bash`

Custom user roles may declare their own allowlists and must not be
forced to match bundled role policy.

#### CMD-018 pi-env top-level launcher

`pi-env` must provide the top-level entrypoint for starting Pi from any
target project while reusing `pi-env-bwrap` for sandbox construction.

Default invocation from a target project must be equivalent in behavior
to entering the selected `pi-env` Nix devshell and running `pi-env`:

```bash
cd /path/to/project
pi-env
```

The launcher must preserve the caller's current working directory so
`pi-env-bwrap` project-root detection continues to mount the target project
at `/workspace`.

The launcher must support these direct-use controls:

- `pi-env [args...]` applies the default startup policy itself after
  entering the selected devshell, then delegates to `pi-env-bwrap`.
- `pi-env --raw -- [pi args...]` delegates to `pi-env-bwrap -- [pi args...]`
  for fully custom Pi argument forwarding.
- `pi-env --flake REF ...` or `PI_ENV_FLAKE=REF pi-env ...` selects the
  `pi-env` flake to enter for direct use.

The flake must also expose a Nix-provided `pi-env` package/app and include
it in the default devshell so project-integrated users can run `pi-env`
after `nix develop` without a separate checkout script.

#### CMD-019 Default role-manager startup integration

Default `pi-env` startup must load the pi-env role-manager package by
default when the package is available, without requiring users to remember
an explicit `-e "$PI_ENV_ROLE_MANAGER_PACKAGE"` argument for normal
startup.

The default integration must:

- load the role-manager as a per-run Pi package/extension, not by
  mutating global or project Pi settings;
- preserve the existing default tool allowlist behavior, `--continue`,
  and caller-supplied Pi arguments;
- use `PI_ENV_ROLE_MANAGER_PACKAGE` when set, otherwise use the Nix-built
  role-manager package path known to `pi-env`;
- skip role-manager loading gracefully when no package path is available
  or the path does not exist;
- allow opt-out with `PI_ENV_ROLE_MANAGER_AUTO=0`;
- avoid duplicate command/tool registration surprises when the package is
  also installed through Pi settings, either through extension
  idempotency or by documenting the opt-out path.

Role-manager loading must not activate a role by itself. Role activation
remains controlled by stored session role state, `/role`, `/role-cycle`,
`/role-new`, or explicit role environment variables supported by the
role-manager extension.

#### CMD-020 Serial role automation command

pi-env should provide a serial automation command or script that can be
run from a project checkout containing, or configured with, a coordination
checkout. The command must own the polling loop outside Pi and invoke Pi
only for a concrete selected issue.

The command must:

- acquire a local lockfile under `.pi-env/locks/` before polling so two
  serial orchestrators do not accidentally operate in the same clone;
- pull/rebase coordination before selecting work when the coordination
  checkout is clean;
- treat a dirty coordination checkout during idle pre-selection polling as
  a temporary busy condition without pulling, inspecting, selecting,
  claiming, stashing, resetting, or discarding;
- stop rather than discard or auto-stash unexpected project changes;
- select tester work from done issues with `reviewed: true` and
  `verified: false`;
- select reviewer work from done issues with `reviewed: false`;
- select developer work from open issues and claim it before launching the
  developer job;
- optionally limit selection to a caller-provided ordered batch of explicit
  issue IDs while preserving tester, reviewer, then developer priority;
- reject unknown explicit issue IDs, duplicate explicit issue IDs, and
  explicit IDs that resolve to non-issue items before running a Pi job;
- sleep and poll again when no eligible issue exists in default queue mode;
- exit successfully when an explicit requested issue batch has no currently
  eligible work;
- allow a bounded or dry-run mode suitable for automated tests.

The command must not require tmux for the serial mode.

#### CMD-021 `pi-env-bwrap` shell mode

`pi-env-bwrap` must provide a shell mode that constructs the same Bubblewrap
sandbox, mounts, working directory, sanitized environment, runtime tool path,
Pi state exposure, extension/session/resource binds, and coordination path
rewrites as normal Pi coding-agent execution, but execs Bash instead of
`pi` as the final process.

Shell mode must be reachable through a wrapper-owned interface, such as
`pi-env-bwrap --shell`, and may also be exposed as `pi-env-bwrap-shell`. In normal
Pi mode, existing argument behavior must remain unchanged, including
`pi-env-bwrap -- <args>` passing arguments to Pi.

Shell mode must not inject Pi default arguments, must not treat shell-mode
arguments as Pi arguments, and must exit with the shell process status.

#### CMD-022 `pi-env-shell` runtime launcher

`pi-env` must expose a user-facing `pi-env-shell` command that enters a
Bash shell inside the same sandbox profile used by the Pi coding agent while
preserving the existing `pi-env` runtime selection contract.

`pi-env-shell` must accept the same runtime-selection inputs as `pi-env`,
including `--runtime host|nix|auto`, `PI_ENV_RUNTIME`, and `--flake REF`.
Host, Nix, and auto modes must resolve through the existing launcher layer
and then delegate to `pi-env-bwrap` shell mode instead of duplicating sandbox
policy.

When the Nix runtime is requested and the Nix-provided commands are not
already wired into the current process, `pi-env-shell` must enter
`nix develop` for the selected flake and run the Nix-provided
`pi-env-shell`, preserving the requested shell-mode arguments.

Existing `pi-env` and `pi-env-bwrap` Pi-agent behavior must remain unchanged,
except that `pi-start` is intentionally removed and its default startup
behavior moves into `pi-env`.

#### CMD-023 `pienv` command namespace

pi-env must provide a canonical `pienv` command namespace that covers the
current command surface without changing existing `.pi-env/` operational
state paths or `PI_ENV_*` environment variables. Lower-level behavior-source
commands must use the `pi-env-*` names required by CMD-026.

`pienv` without a subcommand must behave like the current default `pi-env`
launcher, and `pienv run` must be an explicit alias for the same behavior.
The namespace must expose these leaf commands:

- `pienv raw -- [pi args...]` for current `pi-env --raw -- [pi args...]`;
- `pienv shell [shell args...]` for current `pi-env-shell`;
- `pienv sandbox [pi args...]` for `pi-env-bwrap`;
- `pienv sandbox shell [shell args...]` for `pi-env-bwrap --shell`;
- `pienv coord bootstrap` for `pi-env-bootstrap-coordination`;
- `pienv coord init`, `clone`, `status`, `list`, `show`, `new`, `claim`,
  `done`, `review`, `verify`, `close`, `pull`, `push`, `lint`, and `repo`
  for the corresponding `pi-env-coord-*` helpers, with `show` mapping to
  `pi-env-coord-cat`;
- `pienv coord rules upgrade` for `pi-env-coord-upgrade-rules`;
- `pienv coord requirements generate` for
  `pi-env-coord-generate-requirements`;
- `pienv coord requirements coverage` for
  `pi-env-coord-generate-requirements-coverage`;
- `pienv roles serial` for `pi-env-serial-roles`;
- `pienv install` and `pienv uninstall` for supported non-Nix install and
  uninstall flows backed by `pi-env-install-non-nix` and `pi-env-uninstall`;
- `pienv completion bash` for portable Bash completion setup.

The command namespace must be available from direct checkout use,
host-runtime non-Nix installation, Nix devshells, and flake app/package
outputs.

#### CMD-024 `pienv` behavioral parity

Each `pienv` replacement command must preserve the parameter handling and
behavior of the renamed `pi-env-*` low-level command it dispatches to after
the new subcommand path is consumed. Parity includes accepted options,
positional arguments, argument
ordering, exit status, stdout/stderr behavior, working-directory behavior,
environment-variable handling, support-file resolution, and help behavior.

The implementation should remain a thin dispatcher rather than a rewrite of
launcher, sandbox, coordination, role-automation, or installer behavior. Leaf
commands should `exec` the renamed low-level implementation command with
unchanged remaining arguments. For example:

```bash
pienv coord status --repo-id pi-env
# equivalent to: pi-env-coord-status --repo-id pi-env

pienv shell --runtime nix
# equivalent to: pi-env-shell --runtime nix

pienv sandbox shell -- -l
# equivalent to: pi-env-bwrap --shell -- -l
```

Because top-level `pienv` subcommand names are reserved, users must be able
to use `pienv -- ...` when they need to pass a first Pi argument that looks
like a `pienv` subcommand.

Parity must be verified in both host and Nix runtime contexts, including
direct checkout, non-Nix installed host runtime, Nix devshell, and flake app
or package execution where those contexts are supported by the current
command.

#### CMD-025 `pienv` help and Bash completion

The `pienv` namespace must provide discoverable command help and Bash
completion for the nested command hierarchy.

Help must support, at minimum:

```bash
pienv help
pienv help coord
pienv help coord status
pienv coord status --help
```

Leaf help may delegate to the mapped existing command's `--help` output.
Group help should list available subcommands and the existing command that
each subcommand maps to.

Bash completion must be available as an installed completion file where the
packaging environment supports Bash completion and as a portable command:

```bash
pienv completion bash
source <(pienv completion bash)
```

Completion must suggest top-level commands, nested `sandbox`, `coord`,
`coord rules`, `coord requirements`, `roles`, and `completion` subcommands,
and known options for leaf commands. Path-valued options should keep path
completion. The completion implementation should not require Nix-only tools;
it must work in host-runtime installations as well as Nix-provided shells.

#### CMD-026 pi-env-prefixed low-level commands

All lower-level commands that are called by the `pienv` command collection
must use `pi-env-*` names, without compatibility shims for the old names.
The supported low-level command names are:

- `pi-env`, `pi-env-shell`, `pi-env-bwrap`;
- `pi-env-bootstrap-coordination`;
- `pi-env-coord-init`, `pi-env-coord-clone`, `pi-env-coord-status`,
  `pi-env-coord-list`, `pi-env-coord-cat`, `pi-env-coord-new`,
  `pi-env-coord-claim`, `pi-env-coord-done`, `pi-env-coord-review`,
  `pi-env-coord-verify`, `pi-env-coord-close`, `pi-env-coord-pull`,
  `pi-env-coord-push`, `pi-env-coord-lint`, `pi-env-coord-repo`,
  `pi-env-coord-upgrade-rules`, `pi-env-coord-generate-requirements`, and
  `pi-env-coord-generate-requirements-coverage`;
- `pi-env-serial-roles`;
- `pi-env-install-non-nix` and `pi-env-uninstall`.

Installed Nix packages, flake apps, non-Nix installations, direct-checkout
documentation, tests, and `pienv` help/completion output must use the new
names. The old lower-level commands `pi-bwrap`, `bootstrap-coordination`,
`agent-coord-*`, `pi-serial-roles`, and `install-non-nix` must not remain
supported command entrypoints after the rename.

#### CMD-027 — Canonical flake agent shell integration recipe

pi-env must provide a deterministic user-facing recipe for adding an
agent-oriented devshell to an external project flake.

The recipe must make the pi-env-specific intent explicit: add `pi-env` as a
flake input, include it in `outputs`, preserve existing project devshells,
and add an agent shell with `pi-env.lib.mkPiShell` rather than creating a
project-native shell that only happens to be named `agent`.

The recipe may start as a print-only helper, but its output must be stable
enough for humans and agents to copy into common existing-flake shapes. It
must document when to choose `includeCoordinationHelpers = true` and where to
declare project-specific sandbox tools with `extraPackages`.

The recipe should recommend that pi-env-integrated projects provide the
`.#agent` selector consistently. If the default shell is already pi-env-aware,
the recipe may show `agent` as an alias of that normal `nix develop` shell;
otherwise it should show a separate `pi-env.lib.mkPiShell` agent shell.

### 3.5 Project root and working directory requirements

#### PATH-001 Project root detection

Unless `PI_ENV_BWRAP_PROJECT_ROOT` is set, `pi-env-bwrap` must use `git rev-parse --show-toplevel` when `PI_ENV_BWRAP_USE_GIT_ROOT` is unset or `1`.

If git-root detection fails or is disabled, it must use `$PWD`.

#### PATH-002 Project root override

`PI_ENV_BWRAP_PROJECT_ROOT=/path` must force the mounted project root.

#### PATH-003 Existing project root

If the resolved project root is not a directory, `pi-env-bwrap` must exit with code `2`.

#### PATH-004 Project mount at `/workspace`

The selected project root must be mounted read-write at `/workspace`. The path name is fixed inside the sandbox and does not imply that pi-env manages a host-side multi-project workspace.

#### PATH-005 Sandbox cwd mapping

If the host cwd is inside the project root, the sandbox cwd must be the corresponding path under `/workspace`. Otherwise, the sandbox cwd must be `/workspace`.

#### PATH-006 Conservative host tool path exposure

Host runtime mode must not blindly inherit the caller's full host `PATH`.
It must construct the sandbox `PATH` from a documented allowlist of host
command directories, defaulting to common system locations such as
`/usr/local/bin`, `/usr/bin`, and `/bin` when they exist.

Additional host command directories may be admitted only through an explicit
host-runtime opt-in variable or option. Each admitted directory must be
absolute, canonicalized, exist on the host, and be mounted read-only into
the sandbox. Paths under the host home directory should be rejected by
default or require a separate, clearly documented explicit opt-in.

Nix-mode `PI_ENV_BWRAP_EXTRA_PATH` semantics must remain constrained to
validated `/nix/store` paths. Host-mode extra path semantics must be kept
separate or guarded by explicit runtime-mode checks so Nix safety guarantees
are not weakened accidentally.

### 3.6 Sandbox filesystem requirements

#### FS-001 Home isolation

The sandbox `HOME` must be `/home/pi`; the host home directory must not be mounted wholesale.

#### FS-002 State directory

By default, persistent sandbox state must be stored outside the project under:

```text
$XDG_STATE_HOME/pi-env/<project-hash>
```

or `$HOME/.local/state/pi-env/<project-hash>` when `XDG_STATE_HOME` is unset.

`<project-hash>` must be a deterministic hash of the resolved project root, truncated to 16 hex characters.

#### FS-003 Explicit state directory

`PI_ENV_BWRAP_STATE_DIR=/path` must override the persistent state directory.
Project-local sandbox state must remain opt-in because it may contain copied
auth, sessions, settings, common agent resources, or caches; users may choose
`.pi-env/state` explicitly when they accept that locality and ignore policy.

#### FS-004 Ephemeral home

`PI_ENV_BWRAP_EPHEMERAL_HOME=1` must use a temporary state directory and remove it when the launcher exits.

#### FS-005 State layout

The launcher must create these directories as needed:

- `$state_base/home/.pi/agent`
- `$state_base/home/.cache`
- `$state_base/home/.config/git`
- `$state_base/agent/sessions`
- `$state_base/cache`

#### FS-006 State permissions

Best-effort permissions for private state directories must be `0700`; copied auth and git config files must be best-effort `0600`.

#### FS-007 Nix store

`/nix/store` must be mounted read-only so Nix-provided runtime tools work inside the sandbox.

#### FS-008 Global Pi install support

When present, `/usr/local/bin` and `/usr/local/lib/node_modules/@earendil-works/pi-coding-agent` must be mounted read-only so a global npm-installed `pi` can run.

#### FS-009 System support files

The sandbox must make reasonable read-only host support files available when present, including passwd/group, nsswitch, hosts, resolver config, and certificate locations.

#### FS-010 No sensitive host mounts

The launcher must not mount host `~/.ssh`, cloud credential directories, Docker sockets, or the host home directory by default.

#### FS-011 Host runtime support mounts

Host runtime mode must mount only the host filesystem locations needed to
execute the admitted host tools, Pi, and documented support files. Command
directories and support directories admitted for host runtime must be
read-only unless a requirement explicitly states otherwise.

Host runtime mode may mount common system runtime locations needed by
dynamically linked host binaries, such as system library, loader, share,
certificate, and alternatives directories, when present. It must still avoid
mounting the host home directory, SSH keys, cloud credentials, Docker
sockets, or unrelated project trees by default.

Nix mode must retain the existing read-only `/nix/store` behavior. Host
mode should mount `/nix/store` only when explicitly needed for admitted host
paths or when the selected runtime is Nix-backed.

### 3.7 Pi agent resource requirements

#### AGENT-001 Agent dir inside sandbox

Inside the sandbox:

- `PI_CODING_AGENT_DIR` must be `/home/pi/.pi/agent`
- `PI_CODING_AGENT_SESSION_DIR` must be `/home/pi/.pi/agent/sessions`

#### AGENT-002 Host agent directory detection

The host Pi agent directory must be selected in this order:

1. `PI_ENV_BWRAP_HOST_AGENT_DIR`
2. `PI_CODING_AGENT_DIR`
3. `$HOME/.pi/agent`

#### AGENT-003 Common agent resource directory

The common resource directory must default to the selected host agent directory and be overridable with `PI_ENV_BWRAP_COMMON_AGENT_DIR`.

#### AGENT-004 Common resources imported

When common import is enabled and the common directory exists, the launcher must import only:

- `AGENTS.md`
- `CLAUDE.md`
- `SYSTEM.md`
- `APPEND_SYSTEM.md`
- `skills/`
- `prompts/`
- `roles/`

#### AGENT-005 Common import disable

`PI_ENV_BWRAP_IMPORT_COMMON=0` must disable common resource import.

#### AGENT-006 Common sync policy

`PI_ENV_BWRAP_COMMON_SYNC=always` or unset must refresh common resources each run.

`PI_ENV_BWRAP_COMMON_SYNC=missing` must copy only resources that are absent in sandbox state.

#### AGENT-007 Auth files imported

When auth import is enabled and the host agent directory exists, the launcher must copy only these auth/model files:

- `auth.json`
- `models.json`

#### AGENT-008 Auth import disable

`PI_ENV_BWRAP_IMPORT_AUTH=0` must prevent copying `auth.json` and `models.json`.

#### AGENT-009 Auth sync policy

`PI_ENV_BWRAP_AUTH_SYNC=always` or unset must refresh auth/model files each run.

`PI_ENV_BWRAP_AUTH_SYNC=missing` must copy only absent auth/model files.

#### AGENT-010 Global extensions and packages

When extension import is enabled and the host agent directory exists, the launcher must make globally available Pi extensions and installed Pi packages usable inside the sandbox:

- copy `settings.json` into the sandbox agent directory;
- expose `extensions/`, `npm/`, and `git/` from the host agent directory read-only when present.

Project-local `.pi/extensions`, `.pi/settings.json`, `.pi/npm`, and `.pi/git` are available through the `/workspace` project mount.

#### AGENT-010a Extension import disable

`PI_ENV_BWRAP_IMPORT_EXTENSIONS=0` must prevent copying `settings.json` and exposing host global `extensions/`, `npm/`, and `git/` directories.

#### AGENT-010b Extension sync policy

`PI_ENV_BWRAP_EXTENSIONS_SYNC=always` or unset must refresh the sandbox copy of `settings.json` each run.

`PI_ENV_BWRAP_EXTENSIONS_SYNC=missing` must copy `settings.json` only when it is absent in sandbox state.

#### AGENT-011 Sessions default

Project sessions must be imported/bind-mounted by default for persistent homes, and disabled by default for ephemeral homes.

#### AGENT-012 Sessions override

`PI_ENV_BWRAP_IMPORT_SESSIONS=0` must disable session bind mounting.

`PI_ENV_BWRAP_IMPORT_SESSIONS=1` must enable session bind mounting, including with ephemeral homes.

#### AGENT-013 Session scope

The launcher must bind only the host Pi session directory corresponding to the current host cwd into the sandbox session directory corresponding to the mapped sandbox cwd.

It must not mount all host Pi sessions.

#### AGENT-014 Session naming

Session directory names must be derived by normalizing the path, stripping the leading slash, replacing `/` and `:` with `-`, and surrounding the result with `--`.

#### AGENT-015 Session migration

Before bind-mounting host sessions, the launcher may copy existing sandbox session `*.jsonl` files into the host project session directory without overwriting existing files.

#### AGENT-017 Host Pi and role-manager source policy

Host runtime mode must define how the sandbox reaches the host `pi` command
and optional role-manager package without mounting the host home directory
by default.

The default policy should support system or globally installed Pi paths that
are already covered by host runtime read-only mounts. If `pi` resolves to a
path under the host home directory or another unmounted custom location,
pi-env must fail with an actionable diagnostic or require an explicit
read-only bind opt-in.

Role-manager auto-loading must continue to work in host mode when a safe
package path is available from the pi-env checkout, an installed package, or
an explicit environment variable. Paths outside the project and outside
already mounted runtime locations must be bound read-only and rewritten to
their in-sandbox locations before being passed to Pi.

#### AGENT-016 Fresh role session per serial job

Each serial automation job must start a fresh Pi session for exactly one
coordination issue and one active role. The automation must not use
`--continue` for issue jobs and must not let a developer, reviewer, or
tester job select additional work after the named item is complete.

The job invocation must provide role context for developer, reviewer, and
tester runs. If environment-based role activation is used through the
Bubblewrap launcher, the command must pass the relevant role activation
variable explicitly with `PI_ENV_BWRAP_PASS_ENV`, because the sandbox clears the
ambient host environment by default.

Role prompts must instruct jobs to update coordination through the
appropriate helpers:

- developer jobs claim open work and mark it done with implementation refs;
- reviewer jobs pass or fail review with `pi-env-coord-review`;
- tester jobs pass or fail verification with `pi-env-coord-verify`;
- final close is optional and must only happen after done, reviewed, and
  verified states are all present.

#### AGENT-018 — Packaged flake integration skill

pi-env must provide agent-facing guidance for modifying external flakes to
add pi-env-aware development shells.

The skill must teach agents that a request such as "make `nix develop
.#agent` work for pi-env" means adding the pi-env flake input and using
`pi-env.lib.mkPiShell`, unless the user explicitly asks for a normal
project-native shell. It must instruct agents to preserve existing flake
structure, existing devshells, project package outputs, and project-specific
shell policy.

The skill must prefer the canonical recipe helper from CMD-027 when
available, and must warn against satisfying the request by creating an
unrelated `agentProfile` or `devShells.agent` that lacks `pienv` and the
pi-env sandbox/runtime wiring.

The skill must also teach `.#agent` as the preferred shell selector for
pi-env-integrated projects, including the compatibility pattern where
`agent` aliases the normal default shell when that shell is already
pi-env-aware.

### 3.8 Git configuration requirements

#### GIT-001 Git config import default

Host Git configuration import must be enabled by default.

#### GIT-002 Global git config source

The global Git config source must default to `$HOME/.gitconfig` and be overridable with `PI_ENV_BWRAP_HOST_GITCONFIG`.

#### GIT-003 XDG git config source

The XDG Git config source must default to `$XDG_CONFIG_HOME/git/config` when `XDG_CONFIG_HOME` is set, otherwise `$HOME/.config/git/config`, and be overridable with `PI_ENV_BWRAP_HOST_XDG_GIT_CONFIG`.

#### GIT-004 Git config targets

Copied Git config files must appear inside the sandbox as:

- `/home/pi/.gitconfig`
- `/home/pi/.config/git/config`

#### GIT-005 Git config disable

`PI_ENV_BWRAP_IMPORT_GIT_CONFIG=0` must prevent importing Git config.

#### GIT-006 Git config sync policy

`PI_ENV_BWRAP_GIT_CONFIG_SYNC=always` or unset must refresh copied Git config each run.

`PI_ENV_BWRAP_GIT_CONFIG_SYNC=missing` must preserve existing sandbox copies.

#### GIT-007 No credential import

Git credentials, SSH keys, signing keys, credential helper backing stores, and other referenced files must not be imported automatically.

#### GIT-008 System Git config

The sandbox must set `GIT_CONFIG_NOSYSTEM=1`.

### 3.9 Environment requirements

#### ENV-001 Clear environment

Bubblewrap must be invoked with `--clearenv`.

#### ENV-002 Basic terminal variables

The launcher must set or pass through terminal-related variables:

- set `TERM`, defaulting to `xterm-256color`
- pass `COLORTERM` when set and non-empty
- pass `NO_COLOR` when set and non-empty
- pass `FORCE_COLOR` when set and non-empty

#### ENV-003 Provider credentials

The launcher may pass selected LLM provider variables, including API keys and base URLs listed in `flake.nix`. No arbitrary host environment variable may be passed unless explicitly requested.

#### ENV-004 Extra environment pass-through

`PI_ENV_BWRAP_PASS_ENV` must accept extra environment variable names separated by spaces, commas, or colons and pass through only those names when set and non-empty.

#### ENV-005 Sandbox identity/env

Inside the sandbox the launcher must set:

- `HOME=/home/pi`
- `SHELL=/bin/bash`
- `USER=pi`
- `LOGNAME=pi`
- `PWD` to the mapped sandbox cwd
- `XDG_CACHE_HOME=/home/pi/.cache`
- `TMPDIR=/tmp`
- `PATH` to include the Nix runtime path, `/usr/local/bin`, `/usr/bin`, and `/bin`
- `SSL_CERT_FILE` and `NIX_SSL_CERT_FILE` to Nix `cacert`
- `PI_SKIP_VERSION_CHECK`, defaulting to `1`
- `PI_TELEMETRY`, defaulting to `0`

#### ENV-006 Coordination context

When set or declared in `.pi-env-coordination.yaml`, the launcher must pass
safe coordination context into the sandbox:

- `PI_ENV_COORD_REMOTE`
- `PI_ENV_COORD_ROOT`
- `PI_ENV_COORD_PROJECT`
- `PI_ENV_COORD_AGENT_ID`
- `PI_ENV_COORD_PROJECT_KEY`
- `PI_ENV_COORD_ROLE`

If `PI_ENV_COORD_REMOTE` points inside the selected project, or is read as a
project-local `coordination_remote`, the launcher must pass it into the
sandbox as the corresponding `/workspace/...` path. If explicit
`PI_ENV_COORD_REMOTE` points to an existing local path outside the selected
project, the launcher must bind its parent directory read-write and pass the
sandbox-visible remote path. External local paths read only from project
configuration must not trigger host-path binds unless the user also opts in
with explicit environment context such as `PI_ENV_COORD_REMOTE` or
`PI_ENV_COORD_ROOT`.

If legacy `PI_ENV_COORD_ROOT` points inside the selected project, the launcher
must pass it into the sandbox as the corresponding `/workspace/...` path.
Project-local `.pi-env/agent-remotes` is the default for local bare remotes.

If a coordination clone is detected under the selected project at
`.pi-env/coordination`, or selected with
`PI_ENV_COORD_DIR`/`PI_ENV_BWRAP_COORDINATION_DIR`, the launcher must set
`PI_ENV_COORD_DIR` inside the sandbox to the sandbox-visible path.

`PI_ENV_BWRAP_COORDINATION_DIR=/path/to/coordination` must explicitly bind an
external coordination clone read-write at `/coordination`. The launcher may
print a reminder when a coordination repository is available, but it must
not mutate coordination state.

### 3.10 Network requirements

#### NET-001 Default network

The sandbox must share the host network by default so Pi can reach model providers.

#### NET-002 Disable network

`PI_ENV_BWRAP_NET=0` must avoid adding Bubblewrap `--share-net`.

## 4. Quality requirements

### 4.1 Documentation quality requirements

#### DOC-000 Design documents

Design proposals that are not yet mandatory runtime behavior must be documented separately from requirements/use-case documentation. Implemented coordination behavior is limited to explicit requirements for concrete commands, files, and environment variables in this document.

#### DOC-001 README coverage

`README.md` must document:

- project purpose
- `pi-env`, `pi-env-shell`, and `pi-env-bwrap` commands
- default tool list
- Bubblewrap safety defaults
- environment knobs
- reuse from another project with and without an existing flake
- common vs project-specific rules, skills, prompts, and roles
- optional role-manager package setup, role sources, commands, and tool allowlists
- Git config import behavior
- opt-in coordination helper basics
- safe coordination context/mount behavior
- security notes and limitations

#### DOC-003 Project-specific sandbox tool documentation

The README must explain that pi-env intentionally keeps its default
runtime small and does not include every compiler, build system, or
project test dependency by default.

Documentation must show the recommended way to make project-specific
development tools available inside the sandbox: declare them as Nix
packages in a consuming project's `mkPiShell { extraPackages = ...; }`
configuration, then run `pi-env` from that project devshell.

Documentation must also describe the security boundary for this feature:
extra command directories are explicit Nix-store paths, `/nix/store` is
mounted read-only, host `/bin` and `/usr/bin` are not mounted as the tool
source, and direct `nix run` examples are suitable for inspection but may
lack project build/test tools unless the project integrates pi-env or an
explicit extra path is provided.

#### DOC-005 — Document pi-env flake integration guidance

pi-env documentation must distinguish between a generic project devshell named
`agent` and a pi-env-aware agent shell built with `pi-env.lib.mkPiShell`.

The documentation must show the canonical external-flake edit pattern:
adding the pi-env flake input, adding it to the `outputs` argument set,
preserving existing `devShells`, and merging an `agent` shell that exposes
`pienv` and the pi-env runtime. It must also explain that copied or
agent-generated flake changes should not replace project-specific FHS,
container, build, or test shell policy unless explicitly requested.

Documentation for the helper and skill must include copyable prompts or
commands for users who ask Pi to perform the flake integration from inside an
external project.

Documentation must also explain the runtime selector convention: Nix runtime
startup should prefer `.#agent` when present, fall back to the default shell
only when the selector is absent, and fail visibly rather than hiding an
existing but broken `.#agent` shell.

### 4.1 Documentation requirements

#### DOC-002 Getting started workflows

The main `README.md` must include a concise `Getting started` section near
the top that explains both supported `pi-env` use modes.

The direct-use subsection must show how to start from an arbitrary target
project without editing that project:

```bash
cd /path/to/project
/path/to/pi-env/pi-env
```

It must also include examples for passing a prompt and for raw custom Pi
arguments through `pi-env --raw -- ...`.

The project-integrated subsection must describe when to wire `pi-env` into
a target project's flake, including pinned `pi-env` inputs, shared team
setup, project-specific Nix dependencies, and running from inside the
project devshell:

```bash
nix develop
pi-env
```

The getting-started text must also mention that default `pi-env` startup
loads the role-manager package when available, while
`PI_ENV_ROLE_MANAGER_AUTO=0` disables that behavior.

#### DOC-004 Host default and Nix opt-in documentation

User-facing documentation must describe host runtime mode as the normal
direct-start path and Nix runtime mode as the reproducible pinned opt-in.

Documentation updates must include:

- revised host prerequisites that make Nix optional for direct host-runtime
  use;
- examples for direct host-default startup, explicit `--runtime host`, and
  explicit `--runtime nix`;
- clear statements that host runtime tools are unpinned and supplied by the
  host operating system or user installation;
- conservative host path and mount policy, including how to admit additional
  host tool directories;
- guidance for users whose `pi` command or language-manager tools live
  under the host home directory;
- confirmation that `nix run`, `nix develop`, and flake integration remain
  supported for reproducible team workflows.

### 4.2 Blackbox verification requirements

These tests should be run from outside implementation internals where possible, using a temporary project and temporary host home/agent directories. A fake `pi` executable can be placed early on `PATH` to record argv, cwd, environment, and visible files.

#### TEST-001 Flake metadata

Command:

```bash
nix flake show
```

Expected:

- packages include `default`, `pi-env`, `pi-env-shell`, `pi-env-bwrap`,
  `pi-core`, `pi-env-coordination`, `pi-runtime`, `pi-role-manager`, and
  the coordination helper command packages
- apps include `pi-env`, `pi-env-shell`, `pi-env-bwrap`, and `default`
- checks include core-only and coordination-included package smoke tests
- `devShells.default` exists

#### TEST-002 Flake builds

Commands:

```bash
nix build .#pi-env
nix build .#pi-env-shell
nix build .#pi-env-bwrap
nix build .#pi-core
nix build .#pi-env-coordination
nix build .#pi-runtime
nix build .#pi-role-manager
nix build .#pi-env-coord-init
nix build .#pi-env-coord-clone
nix build .#pi-env-coord-new
nix build .#pi-env-coord-status
nix build .#pi-env-coord-list
nix build .#pi-env-coord-cat
nix build .#pi-env-coord-pull
nix build .#pi-env-coord-push
nix build .#pi-env-coord-claim
nix build .#pi-env-coord-done
nix build .#pi-env-coord-review
nix build .#pi-env-coord-verify
nix build .#pi-env-coord-close
nix build .#pi-env-coord-lint
nix build .#pi-env-coord-generate-requirements
nix build .#pi-env-coord-generate-requirements-coverage
nix build .#pi-env-coord-upgrade-rules
nix build .#pi-env-serial-roles
nix build .#checks.x86_64-linux.pi-core-smoke
nix build .#checks.x86_64-linux.pi-runtime-compat-smoke
nix build .#checks.x86_64-linux.pi-env-coordination-smoke
```

Expected: all builds succeed.

#### TEST-003 Help does not require Pi

Command with `PATH` excluding real/fake `pi`:

```bash
nix run .#pi-env-bwrap -- --help
```

Expected: help text is printed and exit code is `0`.

#### TEST-004 Missing Pi

Run `pi-env-bwrap` where no `pi` executable is on `PATH`.

Expected:

- exit code `127`
- stderr says `pi was not found on PATH before entering the sandbox`

#### TEST-005 Default Pi arguments

With fake `pi` on `PATH`, run:

```bash
pi-env-bwrap
```

Expected fake Pi sees:

```text
--tools read,bash,edit,write,grep,find,ls --continue
```

#### TEST-006 Argument separator

With fake `pi`, run:

```bash
pi-env-bwrap -- --model test/model "hello"
```

Expected fake Pi sees exactly:

```text
--model test/model hello
```

#### TEST-007 `pi-env` preserves extra args

With fake `pi`, run:

```bash
pi-env --model test/model
```

Expected fake Pi sees `--tools <default-tools> --continue --model test/model`.

#### TEST-008 Default tools override

With fake `pi`, run:

```bash
PI_ENV_BWRAP_DEFAULT_TOOLS=read,grep pi-env
```

Expected fake Pi sees `--tools read,grep --continue`.

#### TEST-009 Project root is mounted at `/workspace`

Create a git repo with a subdirectory, run from the subdirectory, and have fake Pi record cwd.

Expected:

- cwd inside sandbox is `/workspace/<subdir>`
- files from git root are visible under `/workspace`

#### TEST-010 Disable git-root detection

From a subdirectory in a git repo, run:

```bash
PI_ENV_BWRAP_USE_GIT_ROOT=0 pi-env-bwrap -- <fake args>
```

Expected `/workspace` corresponds to the subdirectory, not the git root.

#### TEST-011 Project root override

Run with:

```bash
PI_ENV_BWRAP_PROJECT_ROOT=/tmp/other-project pi-env-bwrap
```

Expected `/workspace` contains `/tmp/other-project`.

#### TEST-012 Missing project root

Run with a nonexistent `PI_ENV_BWRAP_PROJECT_ROOT`.

Expected exit code `2`.

#### TEST-013 Persistent state location

With temporary `HOME` and `XDG_STATE_HOME`, run `pi-env-bwrap`.

Expected a deterministic directory is created under `$XDG_STATE_HOME/pi-env/<16-char-hash>` with the required state layout.

#### TEST-014 Explicit state location

Run with `PI_ENV_BWRAP_STATE_DIR=/tmp/pi-state`.

Expected state is created under `/tmp/pi-state` and not under the default state parent.

#### TEST-015 Ephemeral state cleanup

Run with `PI_ENV_BWRAP_EPHEMERAL_HOME=1` and have fake Pi record `$HOME` and create a marker in it.

Expected:

- inside sandbox `HOME=/home/pi`
- temporary state directory is removed after exit
- project session import defaults to disabled

#### TEST-016 Common resource import

Create host common dir containing all supported common files plus unsupported files.

Run with `PI_ENV_BWRAP_COMMON_AGENT_DIR=<dir>`.

Expected inside `/home/pi/.pi/agent`:

- supported files/dirs are present
- unsupported files are absent

#### TEST-017 Common import disabled

Run with `PI_ENV_BWRAP_IMPORT_COMMON=0`.

Expected no common resources are copied into sandbox state.

#### TEST-018 Common sync missing

Pre-create a sandbox common file, then run with `PI_ENV_BWRAP_COMMON_SYNC=missing` and a different host version.

Expected the existing sandbox file is not overwritten.

#### TEST-019 Auth import

Create host `auth.json` and `models.json` plus unrelated files.

Expected only `auth.json` and `models.json` are copied to the sandbox agent state, mode best-effort `0600`.

#### TEST-020 Auth import disabled

Run with `PI_ENV_BWRAP_IMPORT_AUTH=0`.

Expected no auth/model files are copied.

#### TEST-021 Session scope

Create several host session directories, including one for the current cwd and one unrelated.

Expected inside sandbox only the mapped current-cwd session directory is visible/bound; unrelated sessions are not visible.

#### TEST-022 Session import disabled

Run with `PI_ENV_BWRAP_IMPORT_SESSIONS=0`.

Expected no host session directory is bind-mounted.

#### TEST-023 Git config import

Create temporary host `.gitconfig` and `.config/git/config`.

Expected inside sandbox:

- `/home/pi/.gitconfig` exists with same content
- `/home/pi/.config/git/config` exists with same content
- `GIT_CONFIG_NOSYSTEM=1`

#### TEST-024 Git config import disabled

Run with `PI_ENV_BWRAP_IMPORT_GIT_CONFIG=0`.

Expected git config files are absent unless already present from prior state.

#### TEST-025 Git config sync missing

Pre-create sandbox Git config, run with `PI_ENV_BWRAP_GIT_CONFIG_SYNC=missing` and different host config.

Expected sandbox config is preserved.

#### TEST-026 Environment clearing

Set arbitrary host variables and selected pass-through variables.

Expected:

- arbitrary unlisted variable is absent inside sandbox
- selected provider variables are present when non-empty
- `PI_ENV_BWRAP_PASS_ENV` variables are present when non-empty

#### TEST-027 Network flag default and disable

Use a fake `bwrap` wrapper or inspect behavior in an environment where Bubblewrap invocation can be recorded.

Expected:

- default invocation includes `--share-net`
- `PI_ENV_BWRAP_NET=0` invocation does not include `--share-net`

#### TEST-028 Sensitive host filesystem isolation

With fake Pi, attempt to read host-only files such as host home markers, `.ssh`, and Docker socket path.

Expected they are not visible unless they are inside the selected project root or explicitly copied by supported import behavior.

#### TEST-029 Coordination MVP helpers

Run `tests/pi-env-coord-blackbox.sh` from the repository root.

Expected:

- `pi-env-coord-init` creates a bare remote and scaffolded clone;
- generated rules, docs, Pi skill files, and key metadata files exist;
- clone Git settings enable rebase and autostash;
- `pi-env-coord-clone` can clone the same domain;
- `pi-env-coord-new` creates a type-coded timestamp-ID YAML item;
- `pi-env-coord-lint` checks item metadata and item-matched test linkage;
- status, push, claim, done, review, verify, and close helpers perform the
  expected file and Git state transitions;
- rule upgrade preview runs without mutating coordination state.

#### TEST-030 Coordination conflict hardening

Run `tests/pi-env-coord-concurrency.sh` from the repository root.

Expected:

- a stale no-pull claim cannot push over another agent's claim;
- a pulled clone refuses to claim or mark done an item owned by another
  agent;
- a done item cannot be final-closed before both review and verification
  pass;
- reviewers/testers can record pass/fail evidence and other clones can pull
  the final closed result;
- helper-generated commit subjects longer than 72 characters are rejected.

#### TEST-031 Role-manager package and commands

Run the role-manager smoke tests from the repository root:

```bash
tests/role-manager-package.sh
tests/role-manager-schema.sh
tests/role-manager-loader.sh
tests/role-manager-commands.sh
```

Expected:

- the role-manager manifest is a Pi package with the expected extension;
- the flake exposes `pi-role-manager` and the devshell package path;
- common-resource handling includes `roles/` directories;
- bundled and example project roles validate;
- loader precedence, active-role prompt injection, command behavior,
  one-cycle termination, UI setup, and role-aware coordination environment
  behavior pass.

#### TEST-032 Serial automation smoke coverage

The serial automation implementation must have automated coverage that
exercises work selection and command construction without contacting a real
model provider.

Verification should use temporary project and coordination repositories and
a fake `pi` executable or dry-run mode to assert that:

- tester-eligible done/reviewed/unverified work is selected before reviewer
  or developer work;
- reviewer-eligible done/unreviewed work is selected before developer work;
- open developer work is claimed before the developer Pi job is launched;
- no job is launched when all queues are empty;
- each Pi invocation omits `--continue` and names exactly one coordination
  item;
- the serial lock prevents two orchestrators from running in the same
  checkout;
- unexpected dirty project state stops the loop instead of being discarded;
- dirty coordination state during idle pre-selection is treated as a busy
  checkout without pulling, selecting, claiming, stashing, resetting, or
  discarding.

#### TEST-033 Host runtime blackbox coverage

The host runtime implementation must have blackbox-style tests that do not
contact a real model provider and can inspect launcher behavior with fake
`pi` and/or fake `bwrap` commands.

Coverage must verify that:

- direct checkout `pi-env` in default mode does not invoke `nix develop`;
- explicit Nix runtime selection preserves the existing Nix-backed path;
- explicit host runtime selection fails before Bubblewrap when required
  host dependencies are missing;
- host-mode sandbox `PATH` is constructed from documented allowlisted host
  paths rather than arbitrary caller `PATH` inheritance;
- admitted host command and support paths are mounted read-only;
- host `$HOME`, SSH keys, cloud credentials, Docker sockets, and unrelated
  project trees are not mounted by default;
- a `pi` path under host `$HOME` fails closed or requires an explicit
  documented opt-in;
- role-manager and coordination helper behavior either works in host mode
  or fails with clear diagnostics.

## 5. Constraint requirements

### 3.8 Constraint requirements

#### CRQ-011 pi-env launcher layering constraint

The `pi-env` launcher must remain a thin runtime/bootstrapper and must not
duplicate sandbox policy. It may own default Pi startup policy so the separate
`pi-start` command can be removed.

Required layering:

```text
pi-env       = direct/project-integrated UX entrypoint, Nix bootstrap,
               and default Pi invocation policy
pi-env-shell = shell-oriented UX entrypoint using the same runtime selection
pi-env-bwrap     = sandbox boundary and custom Pi argument passthrough
```

Consequences:

- `pi-env` must implement default startup policy by adding the default tool
  allowlist, `--continue`, role-manager default loading, and caller-provided
  Pi arguments before delegating to `pi-env-bwrap`.
- `pi-env --raw` must delegate custom runs to `pi-env-bwrap`.
- `pi-env-shell` must delegate shell runs to `pi-env-bwrap --shell`.
- Project root mapping, sandbox mounts, auth/session import, and environment
  policy must remain owned by `pi-env-bwrap`.
- `pi-env` must not create, claim, mark done, review, verify, close,
  commit, push, or otherwise mutate coordination state automatically.
- `pi-env` must preserve the caller's working directory instead of
  changing into the `pi-env` checkout, so target-project detection stays
  correct.

#### CRQ-013 Single-clone serial execution boundary

The first automation implementation must operate serially over one project
working tree and one coordination working tree. It must not introduce
parallel role execution, tmux orchestration, reviewer/tester leases, or
shared-clone concurrent Git operations.

The implementation must fail closed when the project working tree is dirty
before polling or when either working tree is dirty after a role job. During
idle pre-selection polling only, a dirty coordination checkout may be treated
as a temporary busy condition, but the implementation must not pull, inspect,
select, claim, auto-reset, auto-stash, force-push, rewrite coordination
history, or hide uncommitted source changes in order to keep polling.

Later parallel automation must be designed as a separate phase using
separate clones or worktrees and explicit coordination leases where needed.

#### CRQ-014 Host runtime disclosure boundary

Host runtime mode trades reproducible Nix-pinned tools for lower startup
friction. Documentation and diagnostics must not describe host runtime as
reproducible or version-pinned by pi-env.

The product messaging must distinguish three properties:

- Bubblewrap sandboxing remains enabled by default.
- Host runtime mode uses unpinned host tools and dependencies.
- Nix runtime mode provides the pinned reproducible toolset.

Host runtime support must not weaken the default no-host-home and no-secret
mount guarantees. Any opt-in that admits host paths under `$HOME`, custom
language-manager installations, or other sensitive locations must be
explicit and documented as a broader trust decision.

#### CRQ-015 Stable internal pi-env state and environment names

Introducing the `pienv` user-facing command namespace must not rename or
migrate existing `.pi-env/` operational state paths, coordination attachment
files, support-file layout under `share/pi-env`, or `PI_ENV_*` environment
variables.

The low-level command rename to `pi-env-*` names is a binary, package,
and documentation migration only. Any later proposal to rename internal
state paths, environment variables, support-file layout, package metadata,
or repository naming must be handled as a separate compatibility and
migration decision.

Documentation for the new command namespace must continue to describe
`.pi-env/` and `PI_ENV_*` names accurately where they are the actual storage
paths or configuration interfaces.

#### CRQ-001 — One coordination domain is one bare Git repository

- Type: Constraint requirement
- Requirement kind: architecture boundary

Git-backed coordination support, when enabled, must keep one bare coordination repository as one coordination domain.

#### CRQ-002 — Coordination state uses plain Git text files

- Type: Constraint requirement
- Requirement kind: architecture boundary

Coordination repositories must be plain Git repositories containing Markdown and small metadata blocks. Helper commands must remain thin wrappers around Git and file scaffolding/editing.

#### CRQ-003 — Default startup must not mutate coordination state

- Type: Constraint requirement
- Requirement kind: safety boundary
- Related workflows: UC-023

Default `pi-env` startup and `pi-env-bwrap` may only provide safe context,
reminders, or mounts for coordination repositories. They must not create,
claim, mark done, review, verify, close, commit, push, or otherwise mutate
coordination state automatically.

#### CRQ-004 — No hidden synchronization mechanism

- Type: Constraint requirement
- Requirement kind: architecture boundary
- Related workflows: UC-023

No daemon, database, background push, force-push, hidden lock service, or non-Git synchronization mechanism may be introduced for coordination state.

#### CRQ-005 — Coordination requirements are explicit only

- Type: Constraint requirement
- Requirement kind: product boundary
- Related workflows: UC-023

Coordination behavior becomes mandatory only when a requirement in this document names a concrete command, file, or environment variable.

#### CRQ-006 — Host secrets are not mounted or imported by default

- Type: Constraint requirement
- Requirement kind: security boundary
- Related workflows: UC-004, UC-013, UC-022

Git credential stores, SSH keys, signing keys, cloud credentials, Docker sockets, and the host home directory must not be mounted or imported by default.

#### CRQ-007 — User-specific common Pi resources are external

- Type: Constraint requirement
- Requirement kind: product boundary
- Related workflows: UC-010, UC-011

`pi-env` does not ship user-specific common rules, skills, prompts, roles, or extensions. It imports or exposes them from an external user-controlled directory when configured.

#### CRQ-008 — Bubblewrap network isolation is coarse-grained only

- Type: Constraint requirement
- Requirement kind: limitation
- Related workflows: UC-015, UC-022

Bubblewrap does not provide domain-level network allowlisting. Network behavior is limited to sharing or not sharing the host network namespace.

#### CRQ-009 — Enabled Pi tools are not inherently harmless

- Type: Constraint requirement
- Requirement kind: limitation
- Related workflows: UC-014, UC-022

If `read` or `bash` tools are enabled, copied auth files, exposed global extensions/packages, and bound project sessions may be readable by commands or tools inside the sandbox. Users should use least-privilege API keys, provider proxies, reduced tool allowlists, or `PI_ENV_BWRAP_NET=0` when appropriate.

#### CRQ-010 — Requirement source of truth precedence

- Type: Constraint requirement
- Requirement kind: architecture boundary

Requirement coordination items under root `requirements/` are the preferred
authoritative source of truth for functional, quality, and constraint
requirements when those items exist. Requirement changes for covered
areas must be planned and recorded in those items first, including
stable `requirement_key`, classification, relationships, testability
metadata, and renderable Markdown body text.

`REQUIREMENTS.md` is normally a generated, human-readable reference
rendered from active requirement items. Do not make requirement changes by
editing `REQUIREMENTS.md` first when a corresponding requirement item exists.
Update the source requirement item first, then regenerate `REQUIREMENTS.md`
with the requirements generator. When requirement coordination items do not
yet exist for a project or requirement area, `REQUIREMENTS.md` may serve as
the secondary source of truth until corresponding coordination items are
created. Once items exist, any generated documentation drift must be resolved
by correcting the relevant coordination items or the requirements generator,
then regenerating the document.

#### CRQ-012 Extra PATH entries are explicit Nix-store paths

`pi-env-bwrap` must not discover project build tools by scanning all of
`/nix/store`, inheriting the host `PATH`, or mounting host `/bin` or
`/usr/bin` read-only.

Extra command directories admitted into the sandbox `PATH` must come from
an explicit pi-env input such as `PI_ENV_BWRAP_EXTRA_PATH` or from
`mkPiShell`-derived `extraPackages`. Each admitted path must be
canonicalized and constrained to `/nix/store` by default. Empty path
components may be ignored, but unsafe path components such as `/home/*`,
`/tmp/*`, project-writable directories, host `/bin`, host `/usr/bin`, or
relative paths must be rejected rather than silently accepted.

This constraint preserves the pi-env security and reproducibility model:
project-specific tools may be made available, but only as explicit,
immutable Nix-store tool paths already covered by the read-only
`/nix/store` mount.

## 6. Coordination requirement item structure

Requirement coordination items live under root `requirements/` and keep item-ID filenames. Public requirement identity is stored in `requirement_key`; requirement classification is stored in `requirement_class`, `requirement_kind`, and `domain`. Requirement items are current-state records: they store one renderable top-level `body: |-` block and do not store embedded `current`, `events`, or `messages` history.

Required fields for functional, quality, and constraint requirement items:

```yaml
schema: coordination-item/v1
id: PIENV-FRQ-YYYYMMDD-HHMMSS-NNN
type: functional-requirement
requirement_key: CMD-004
requirement_kind: detailed-behavior
domain: commands
status: active
project: pi-env
title: "`pi-env-bwrap` default invocation"
source_refs:
  - "REQUIREMENTS.md#CMD-004"
related_workflows:
  - UC-002
related_requirements: []
related_tests:
  - TEST-005
testable: yes
testability_note: null
body: |-
  #### CMD-004 Example requirement

  Requirement text...
```

Workflow-level requirements should use:

```yaml
type: functional-requirement
requirement_key: UC-001
requirement_kind: workflow
domain: user-workflows
```

Quality verification requirements should use:

```yaml
type: quality-requirement
requirement_key: TEST-001
requirement_kind: blackbox-test
domain: verification
```

Constraint requirements should use:

```yaml
type: constraint-requirement
requirement_key: CRQ-001
requirement_kind: architecture-boundary
domain: constraints
```

The top-level Markdown `body: |-` field for each requirement item must contain the renderable body for that requirement, including the stable heading, metadata, requirement text, acceptance criteria, and verification notes when applicable. Generated documentation renders stable requirement keys as the primary visible identifiers and may include coordination item IDs as secondary metadata.
