# Nix Runtime Design

The Nix runtime provides reproducible development and launcher tooling while
keeping the project usable from direct shell scripts. The flake is the shared
contract for packages, apps, shells, and reusable shell construction.

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-003 | PIEN-FRQ-20260612-210000-003 |
| UC-017 | PIEN-FRQ-20260612-210000-017 |
| UC-018 | PIEN-FRQ-20260612-210000-018 |
| UC-019 | PIEN-FRQ-20260612-210000-019 |
| UC-020 | PIEN-FRQ-20260612-210000-020 |
| FLAKE-001 | PIEN-FRQ-20260612-210000-024 |
| FLAKE-002 | PIEN-FRQ-20260612-210000-025 |
| FLAKE-003 | PIEN-FRQ-20260612-210000-026 |
| FLAKE-004 | PIEN-FRQ-20260612-210000-027 |
| FLAKE-005 | PIEN-FRQ-20260612-210000-028 |
| FLAKE-006 | PIEN-FRQ-20260612-210000-029 |
| RUNTIME-001 | PIEN-FRQ-20260612-210000-030 |
| RUNTIME-002 | PIEN-FRQ-20260612-210000-031 |
| RUNTIME-003 | PIEN-FRQ-20260614-180306-001 |
| RUNTIME-006 | PIEN-FRQ-20260720-094621-001 |
| RUNTIME-007 | PIEN-FRQ-20260810-165351-001 |
| CMD-027 | PIEN-FRQ-20260720-091901-001 |
| AGENT-018 | PIEN-FRQ-20260720-091904-001 |
| DOC-005 | PIEN-QRQ-20260720-091907-001 |

## 1. Flake outputs

The flake exposes first-class package and app outputs for the launcher tools so
users and tests can invoke the same artifacts. Packages provide installable
programs; apps provide convenient `nix run` entrypoints.

The package boundary separates the core sandbox runtime from optional
coordination helpers while using the current `pi-en-*` command names:

- `pi-core` contains `pi-en`, `pi-en-shell`, `pi-en-bwrap`, and the runtime tools.
- `pi-en-coordination` contains the Git-backed coordination helper commands.
- `pi-runtime` remains the bundle containing both sets of renamed commands for
  consumers that want the full runtime in one package.

Development shells include all tools needed for local validation: shell
utilities, Bubblewrap, Node where required by scripts, and test dependencies.
The shell contract is intentionally broader than a single launcher so
blackbox tests and documentation tooling use one reproducible environment.

## 2. Reusable shell construction

`mkPiShell` is the reusable interface for downstream projects. It packages the
common runtime dependencies and shell initialization while letting callers add
project-specific inputs. The function is the preferred extension point instead
of duplicating package lists across flakes.

`mkPiShell` keeps `includeCoordinationHelpers = true` by default so project
shell consumers receive `pi-en-bootstrap-coordination` and `pi-en-coord-*`
commands. Projects that only need the sandbox/runtime set it to `false` for a
core-only shell.

The reusable shell must remain deterministic. Host-specific state such as auth
files, Git preferences, and Pi resources is imported at launcher runtime rather
than baked into Nix derivations.

`mkPiShell` also exposes shell-local lifecycle helpers that act on the
consuming project rather than on an installed Pi-en prefix. The `pi-en-update`
helper belongs in this category: inside a Pi-en-enabled Nix shell it updates
the consuming flake's `pi-en` input URL/ref and refreshes only that lock input.
Omitted source parts are preserved. Invoking it without `--url` or `--ref`
leaves `flake.nix` unchanged and refreshes the current lock input; explicit
source options also refresh the lock even if the computed URL is already present
in `flake.nix`. Outside the shell the same command name
continues to mean the non-Nix installed-prefix updater. Normal Nix-shell `PATH`
precedence selects the Nix-store updater inside `mkPiShell`. The shell marks
this context explicitly so the Nix-store updater refuses to mutate files when
run outside a Pi-en-enabled Nix shell.

## 3. Runtime tools

`RUNTIME-001` and `RUNTIME-002` are satisfied by keeping command execution and
tool discovery inside the flake-defined environment when users opt into Nix.
Scripts should still report clear missing-tool errors when run outside that
environment, but the supported path is the reproducible flake shell.

Project-specific build and test tools are not added to the global Pi-en
runtime by default. Instead, `RUNTIME-003` extends the `mkPiShell` contract:
callers declare project tools with `extraPackages`, and the shell exports the
corresponding Nix-store `bin` path for the Bubblewrap launcher to validate and
include inside the sandbox. This keeps the default runtime small while making
project-specific tools reproducible and explicit.

The exported path is an interface between the Nix layer and the sandbox layer,
not a host-path inheritance mechanism. Nix computes package paths;
`pi-en-bwrap` decides whether they are safe to admit.

Nix runtime startup may also populate a generated agent-bin shadow directory for
curated command names such as `rg` and `fd`. The shadow entries are symlinks to
executables resolved only from `PI_EN_RUNTIME_PATH` or validated
`PI_EN_BWRAP_EXTRA_PATH` paths that canonicalize under `/nix/store`. Binding
that directory over `/home/pi/.pi/agent/bin` prevents Pi's own host-provided bin
precedence from selecting stale or non-reproducible tools inside the sandbox;
it does not delete or mutate user agent state. Users can disable the bind with
`PI_EN_BWRAP_AGENT_BIN_SHADOW=0` or replace the curated tool list with
`PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS`.

## 4. Agent-oriented flake integration recipes

External project flakes often already encode domain-specific shell policy:
profile maps, FHS environments, container targets, or custom shell hooks. When a
user asks an agent to make `nix develop .#agent` work for Pi-en, the intended
architecture is not a generic project shell named `agent`; it is a Pi-en-aware
shell that exposes `pien`, the Nix-backed Pi-en runtime, and optional
coordination helpers.

The stable integration target is therefore additive:

1. add `pi-en` as a flake input and make it follow the project's `nixpkgs`
   input when practical;
2. include `pi-en` in the `outputs` argument set;
3. preserve existing `devShells`, package outputs, FHS/container outputs, and
   project-specific shell policy;
4. expose `devShells.<system>.agent` either by merging a dedicated agent shell
   using `pi-en.lib.mkPiShell` or by aliasing it to an already Pi-en-aware
   default shell such as `existingDevShells.default`; and
5. declare only explicit project tools in `extraPackages`.

A deterministic recipe helper should expose this target shape for humans and
agents. The first version should be non-mutating and print copyable examples
instead of attempting broad AST edits across arbitrary flakes. A packaged skill
should teach agents to consult that helper, to avoid inventing unrelated
`agentProfile` shells, and to ask for clarification when a flake shape cannot
be changed safely with a small textual patch.

The same conservative edit scope should apply to the planned Nix-shell updater.
It should support common direct `pi-en` input URL assignment forms, preserve
any source component the user did not ask to change, convert `COMMIT@BRANCH` to
a Nix Git flake URL with both `ref` and `rev`, run the narrow `pi-en` input
lock update for source changes and no-source refreshes, and fail with
manual-edit guidance for dynamic or generated input definitions when a rewrite
is requested rather than guessing.

The `.#agent` selector should become the conventional target for Pi-en-aware
project shells. Projects that do not need a separate agent shell can keep
backward-compatible human behavior by defining `agent` as an alias of the
normal default shell, provided that default shell is already Pi-en-aware.
Launcher behavior should mirror that convention: Nix runtime startup may probe
for the agent devshell and prefer it when present, fall back to the default
shell when absent, and fail visibly when a present or explicitly selected agent
shell is broken. An existing but broken `.#agent` is treated as a configuration
error rather than ignored, because silently falling back could run an agent in a
less isolated or under-provisioned shell. An explicit selector override keeps
advanced projects in control of non-default shell names and lets users force
legacy default-shell behavior.

## 5. Compatibility

The Nix layer is an enablement layer, not the source of policy for sandboxing,
Git import, or agent resources. Those policies live in the launcher and sandbox
designs. This keeps `UC-017` through `UC-020` focused on distribution and
reproducibility rather than operational side effects.

The flake recipe helper and skill are additive guidance surfaces. They do not
change the `mkPiShell` contract, existing package outputs, default runtime
selection, or Bubblewrap policy. Future apply modes, if any, must be explicit
and must not silently rewrite project-owned flake structure.
