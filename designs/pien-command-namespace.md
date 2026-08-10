# pien command namespace

## Goal

`pien` is the canonical user-facing command namespace for Pi-en. The
namespace keeps existing `.pi-en/` state paths and `PI_EN_*` environment
variables unchanged, but the lower-level commands that `pien` delegates to are
hard-renamed to `pi-en-*` names.

The project is not yet widely deployed, so this rename intentionally does not
preserve old command compatibility. The former direct command names such as
`pi-bwrap`, `bootstrap-coordination`, `agent-coord-*`, `pi-serial-roles`, and
`install-non-nix` should disappear from installed profiles, flake outputs, and
direct-checkout command documentation once the implementation lands.

## Command model

`pien` owns naming, grouping, help, and shell completion. Lower-level
`pi-en-*` commands continue to own behavior. The dispatcher should therefore
resolve a subcommand path and then `exec` the matching low-level command with
unchanged remaining arguments.

`pien` without a subcommand behaves like `pi-en` default startup. `pien run`
is an explicit alias for the same behavior. The existing `pi-en` and
`pi-en-shell` names are already in the `pi-en-*` family and remain valid
low-level launchers.

## Low-level hard-rename policy

Rename lower-level command entrypoints as follows:

| Former command | New low-level command |
| --- | --- |
| `pi-bwrap` | `pi-en-bwrap` |
| `bootstrap-coordination` | `pi-en-bootstrap-coordination` |
| `agent-coord-init` | `pi-en-coord-init` |
| `agent-coord-clone` | `pi-en-coord-clone` |
| `agent-coord-status` | `pi-en-coord-status` |
| `agent-coord-list` | `pi-en-coord-list` |
| `agent-coord-cat` | `pi-en-coord-cat` |
| `agent-coord-new` | `pi-en-coord-new` |
| `agent-coord-claim` | `pi-en-coord-claim` |
| `agent-coord-done` | `pi-en-coord-done` |
| `agent-coord-review` | `pi-en-coord-review` |
| `agent-coord-verify` | `pi-en-coord-verify` |
| `agent-coord-close` | `pi-en-coord-close` |
| `agent-coord-pull` | `pi-en-coord-pull` |
| `agent-coord-push` | `pi-en-coord-push` |
| `agent-coord-lint` | `pi-en-coord-lint` |
| `agent-coord-repo` | `pi-en-coord-repo` |
| `agent-coord-upgrade-rules` | `pi-en-coord-upgrade-rules` |
| `agent-coord-generate-requirements` | `pi-en-coord-generate-requirements` |
| `agent-coord-generate-requirements-coverage` | `pi-en-coord-generate-requirements-coverage` |
| `pi-serial-roles` | `pi-en-serial-roles` |
| `install-non-nix` | `pi-en-install-non-nix` |
| `pi-en-uninstall` | `pi-en-uninstall` |

For the coordination helpers, the new names drop the implementation-oriented
`agent-` prefix and preserve the old leaf suffix after `coord-`. This keeps the
hard rename mechanical enough for implementers while aligning the public prefix
with `pien coord`.

## Canonical command mapping

| Canonical command | Low-level behavior source |
| --- | --- |
| `pien [pi args...]` | `pi-en [pi args...]` |
| `pien run [pi args...]` | `pi-en [pi args...]` |
| `pien raw -- [pi args...]` | `pi-en --raw -- [pi args...]` |
| `pien shell [shell args...]` | `pi-en-shell [shell args...]` |
| `pien sandbox [pi args...]` | `pi-en-bwrap [pi args...]` |
| `pien sandbox shell [shell args...]` | `pi-en-bwrap --shell -- [shell args...]` |
| `pien coord bootstrap [options]` | `pi-en-bootstrap-coordination [options]` |
| `pien coord init [options]` | `pi-en-coord-init [options]` |
| `pien coord clone [options] [remote]` | `pi-en-coord-clone [options] [remote]` |
| `pien coord status [options]` | `pi-en-coord-status [options]` |
| `pien coord list [options] TYPE [STATUS]` | `pi-en-coord-list [options] TYPE [STATUS]` |
| `pien coord show [options] ITEM` | `pi-en-coord-cat [options] ITEM` |
| `pien coord new [options] "title"` | `pi-en-coord-new [options] "title"` |
| `pien coord claim [options] ITEM` | `pi-en-coord-claim [options] ITEM` |
| `pien coord done [options] ITEM` | `pi-en-coord-done [options] ITEM` |
| `pien coord review [options] ITEM` | `pi-en-coord-review [options] ITEM` |
| `pien coord verify [options] ITEM` | `pi-en-coord-verify [options] ITEM` |
| `pien coord close [options] ITEM` | `pi-en-coord-close [options] ITEM` |
| `pien coord pull [options] [git args...]` | `pi-en-coord-pull [options] [git args...]` |
| `pien coord push [options] [git args...]` | `pi-en-coord-push [options] [git args...]` |
| `pien coord lint [options]` | `pi-en-coord-lint [options]` |
| `pien coord repo ...` | `pi-en-coord-repo ...` |
| `pien coord rules upgrade [options]` | `pi-en-coord-upgrade-rules [options]` |
| `pien coord requirements generate [...]` | `pi-en-coord-generate-requirements [...]` |
| `pien coord requirements coverage [...]` | `pi-en-coord-generate-requirements-coverage [...]` |
| `pien roles serial [options]` | `pi-en-serial-roles [options]` |
| `pien install [options]` | `pi-en-install-non-nix [options]` |
| `pien update [options]` | context-specific `pi-en-update [options]` |
| `pien uninstall [options]` | `pi-en-uninstall [options]` |
| `pien completion bash` | print Bash completion for `pien` |

## Behavioral parity rules

After the hard rename, `pien` replacement commands must honor exactly the same
parameters and behavior as the renamed low-level command after the `pien`
subcommand path is consumed. This includes exit status, stdout/stderr behavior,
working directory assumptions, environment variable handling, support-file
resolution, and all existing options.

The dispatcher must not reimplement coordination, sandbox, runtime-selection,
or install behavior. It should select the low-level implementation and preserve
argument order. Representative examples:

```bash
pien coord status --repo-id pi-en
# execs pi-en-coord-status --repo-id pi-en

pien shell --runtime nix
# execs pi-en-shell --runtime nix

pien sandbox shell -- -l
# execs pi-en-bwrap --shell -- -l
```

Because `pien` also means "run Pi", top-level subcommand names are reserved
first arguments. Users who need to pass a first Pi argument that looks like a
subcommand should use `--`:

```bash
pien -- shell
pien -- coord status
```

## Runtime and packaging requirements

The `pien` command set and renamed `pi-en-*` low-level commands must work in
all currently supported entry contexts: a direct checkout, a host-runtime
non-Nix installation, `nix develop`, and `nix run`/flake app usage. Nix and
host wrappers must expose the same command namespace and must resolve the same
support files as the old commands did.

The implementation must keep `.pi-en/` operational state paths and `PI_EN_*`
environment variables unchanged. Command renaming is a binary/package/documentation
migration, not a storage or configuration migration.

Installed packages and flake outputs should not expose compatibility shims for
the old non-`pi-en-*` command names. Tests should assert the new names are
available and the old names are absent from packaged environments where absence
can be checked reliably.

## Help and Bash completion

The command set should include both installed Bash completion and a portable
completion printer:

```bash
pien completion bash
source <(pien completion bash)
```

Completion should cover top-level commands, nested `coord`, `roles`,
`sandbox`, and `completion` subcommands, and known options for leaf commands.
Path-valued options should keep path completion. Rich descriptions are not a
Bash completion requirement; command discovery should rely on completion while
explanatory text comes from help.

Help should support:

```bash
pien help
pien help coord
pien help coord status
pien coord status --help
```

Leaf help may dispatch to the low-level command's `--help` output. Group help
should list available subcommands and their `pi-en-*` low-level equivalents.

## Compatibility decision

The old lower-level command names are intentionally not compatibility
entrypoints. The hard rename removes `pi-bwrap`, `bootstrap-coordination`,
`agent-coord-*`, `pi-serial-roles`, and `install-non-nix` from the supported
command surface. Users should call `pien ...` for normal workflows or the
renamed `pi-en-*` command directly only for low-level/debug workflows.

## In-sandbox command surface

Pi TUI shell commands (`!` and `!!`) execute inside the Bubblewrap sandbox,
after `pien --runtime ...` has already selected the runtime and started Pi.
The canonical namespace should therefore have a sandbox-aware mode rather than
trying to behave like the outer launcher recursively.

`pi-en-bwrap` should set an explicit in-sandbox marker such as
`PI_EN_INSIDE_SANDBOX=1`. The dispatcher can use that marker to apply an
allow/block table:

- allow non-launcher discovery and diagnostic commands (`help`, grouped help,
  version/doctor-style output, completion printing when harmless, and
  `recipe` commands);
- allow coordination helpers that operate on the mounted project and
  coordination clone, including status/list/show and normal lifecycle helpers;
- allow `pien coord bootstrap --print-only` for planning, while real
  bootstrap remains constrained by the mounted filesystem and available Git
  authentication;
- block runtime and process-boundary commands (`pien` default launch,
  `run`, `--runtime ...`, `shell`, `sandbox`, `install`, planned `update`, and
  `uninstall`) with diagnostics that tell users to run the equivalent command
  in the outer terminal.

The implementation should expose the safe `pien` entrypoint inside the
sandbox only when the selected runtime or devshell supplies it. In Nix
`mkPiShell` environments, the sandbox PATH can be extended with Nix-store
package paths for the dispatcher and, when `includeCoordinationHelpers = true`,
the coordination helpers. This keeps the existing no-host-home and explicit
PATH policies intact while making human and agent commands symmetric for
coordination workflows.

Remote coordination operations from inside Pi should not relax credential
policy. If SSH keys, credential helpers, or host-home files are unavailable,
commands should fail clearly and documentation should recommend running the
remote-authenticated operation from the outer terminal or using an existing
explicit sandbox opt-in, not broad default mounts.

## Context-specific update command

`pien update` should remain a dispatcher, not an updater implementation. It
should resolve the active `pi-en-update` in the current execution context and
preserve the remaining arguments.

Outside Pi-en-enabled Nix shells, `pi-en-update` is the non-Nix installed-prefix
updater created by INSTALL-003. It updates files under a prefix from stored
install-origin metadata and supports the non-Nix installer source options.

Inside `pi-en.lib.mkPiShell`, the planned RUNTIME-007 updater should be a
Nix-store `pi-en-update` placed earlier on `PATH`. It updates the consuming
project's `pi-en` flake input and should expose only `--url`, `--ref`, and help
options. The dispatcher should therefore avoid hard-coding a bundled non-Nix
updater ahead of normal command resolution when the Nix-shell updater is
available.

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| CMD-023 | PIEN-FRQ-20260711-092100-001 |
| CMD-024 | PIEN-FRQ-20260711-092100-002 |
| CMD-025 | PIEN-FRQ-20260711-092100-003 |
| CMD-026 | PIEN-FRQ-20260711-170000-001 |
| CMD-028 | PIEN-FRQ-20260725-125507-001 |
| CRQ-015 | PIEN-CRQ-20260711-092100-001 |
