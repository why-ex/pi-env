# pienv command namespace

## Goal

`pienv` is the canonical user-facing command namespace for pi-env. The
namespace keeps existing `.pi-env/` state paths and `PI_ENV_*` environment
variables unchanged, but the lower-level commands that `pienv` delegates to are
hard-renamed to `pi-env-*` names.

The project is not yet widely deployed, so this rename intentionally does not
preserve old command compatibility. The former direct command names such as
`pi-bwrap`, `bootstrap-coordination`, `agent-coord-*`, `pi-serial-roles`, and
`install-non-nix` should disappear from installed profiles, flake outputs, and
direct-checkout command documentation once the implementation lands.

## Command model

`pienv` owns naming, grouping, help, and shell completion. Lower-level
`pi-env-*` commands continue to own behavior. The dispatcher should therefore
resolve a subcommand path and then `exec` the matching low-level command with
unchanged remaining arguments.

`pienv` without a subcommand behaves like `pi-env` default startup. `pienv run`
is an explicit alias for the same behavior. The existing `pi-env` and
`pi-env-shell` names are already in the `pi-env-*` family and remain valid
low-level launchers.

## Low-level hard-rename policy

Rename lower-level command entrypoints as follows:

| Former command | New low-level command |
| --- | --- |
| `pi-bwrap` | `pi-env-bwrap` |
| `bootstrap-coordination` | `pi-env-bootstrap-coordination` |
| `agent-coord-init` | `pi-env-coord-init` |
| `agent-coord-clone` | `pi-env-coord-clone` |
| `agent-coord-status` | `pi-env-coord-status` |
| `agent-coord-list` | `pi-env-coord-list` |
| `agent-coord-cat` | `pi-env-coord-cat` |
| `agent-coord-new` | `pi-env-coord-new` |
| `agent-coord-claim` | `pi-env-coord-claim` |
| `agent-coord-done` | `pi-env-coord-done` |
| `agent-coord-review` | `pi-env-coord-review` |
| `agent-coord-verify` | `pi-env-coord-verify` |
| `agent-coord-close` | `pi-env-coord-close` |
| `agent-coord-pull` | `pi-env-coord-pull` |
| `agent-coord-push` | `pi-env-coord-push` |
| `agent-coord-lint` | `pi-env-coord-lint` |
| `agent-coord-repo` | `pi-env-coord-repo` |
| `agent-coord-upgrade-rules` | `pi-env-coord-upgrade-rules` |
| `agent-coord-generate-requirements` | `pi-env-coord-generate-requirements` |
| `agent-coord-generate-requirements-coverage` | `pi-env-coord-generate-requirements-coverage` |
| `pi-serial-roles` | `pi-env-serial-roles` |
| `install-non-nix` | `pi-env-install-non-nix` |
| `pi-env-uninstall` | `pi-env-uninstall` |

For the coordination helpers, the new names drop the implementation-oriented
`agent-` prefix and preserve the old leaf suffix after `coord-`. This keeps the
hard rename mechanical enough for implementers while aligning the public prefix
with `pienv coord`.

## Canonical command mapping

| Canonical command | Low-level behavior source |
| --- | --- |
| `pienv [pi args...]` | `pi-env [pi args...]` |
| `pienv run [pi args...]` | `pi-env [pi args...]` |
| `pienv raw -- [pi args...]` | `pi-env --raw -- [pi args...]` |
| `pienv shell [shell args...]` | `pi-env-shell [shell args...]` |
| `pienv sandbox [pi args...]` | `pi-env-bwrap [pi args...]` |
| `pienv sandbox shell [shell args...]` | `pi-env-bwrap --shell -- [shell args...]` |
| `pienv coord bootstrap [options]` | `pi-env-bootstrap-coordination [options]` |
| `pienv coord init [options]` | `pi-env-coord-init [options]` |
| `pienv coord clone [options] [remote]` | `pi-env-coord-clone [options] [remote]` |
| `pienv coord status [options]` | `pi-env-coord-status [options]` |
| `pienv coord list [options] TYPE [STATUS]` | `pi-env-coord-list [options] TYPE [STATUS]` |
| `pienv coord show [options] ITEM` | `pi-env-coord-cat [options] ITEM` |
| `pienv coord new [options] "title"` | `pi-env-coord-new [options] "title"` |
| `pienv coord claim [options] ITEM` | `pi-env-coord-claim [options] ITEM` |
| `pienv coord done [options] ITEM` | `pi-env-coord-done [options] ITEM` |
| `pienv coord review [options] ITEM` | `pi-env-coord-review [options] ITEM` |
| `pienv coord verify [options] ITEM` | `pi-env-coord-verify [options] ITEM` |
| `pienv coord close [options] ITEM` | `pi-env-coord-close [options] ITEM` |
| `pienv coord pull [options] [git args...]` | `pi-env-coord-pull [options] [git args...]` |
| `pienv coord push [options] [git args...]` | `pi-env-coord-push [options] [git args...]` |
| `pienv coord lint [options]` | `pi-env-coord-lint [options]` |
| `pienv coord repo ...` | `pi-env-coord-repo ...` |
| `pienv coord rules upgrade [options]` | `pi-env-coord-upgrade-rules [options]` |
| `pienv coord requirements generate [...]` | `pi-env-coord-generate-requirements [...]` |
| `pienv coord requirements coverage [...]` | `pi-env-coord-generate-requirements-coverage [...]` |
| `pienv roles serial [options]` | `pi-env-serial-roles [options]` |
| `pienv install [options]` | `pi-env-install-non-nix [options]` |
| `pienv uninstall [options]` | `pi-env-uninstall [options]` |
| `pienv completion bash` | print Bash completion for `pienv` |

## Behavioral parity rules

After the hard rename, `pienv` replacement commands must honor exactly the same
parameters and behavior as the renamed low-level command after the `pienv`
subcommand path is consumed. This includes exit status, stdout/stderr behavior,
working directory assumptions, environment variable handling, support-file
resolution, and all existing options.

The dispatcher must not reimplement coordination, sandbox, runtime-selection,
or install behavior. It should select the low-level implementation and preserve
argument order. Representative examples:

```bash
pienv coord status --repo-id pi-env
# execs pi-env-coord-status --repo-id pi-env

pienv shell --runtime nix
# execs pi-env-shell --runtime nix

pienv sandbox shell -- -l
# execs pi-env-bwrap --shell -- -l
```

Because `pienv` also means "run Pi", top-level subcommand names are reserved
first arguments. Users who need to pass a first Pi argument that looks like a
subcommand should use `--`:

```bash
pienv -- shell
pienv -- coord status
```

## Runtime and packaging requirements

The `pienv` command set and renamed `pi-env-*` low-level commands must work in
all currently supported entry contexts: a direct checkout, a host-runtime
non-Nix installation, `nix develop`, and `nix run`/flake app usage. Nix and
host wrappers must expose the same command namespace and must resolve the same
support files as the old commands did.

The implementation must keep `.pi-env/` operational state paths and `PI_ENV_*`
environment variables unchanged. Command renaming is a binary/package/documentation
migration, not a storage or configuration migration.

Installed packages and flake outputs should not expose compatibility shims for
the old non-`pi-env-*` command names. Tests should assert the new names are
available and the old names are absent from packaged environments where absence
can be checked reliably.

## Help and Bash completion

The command set should include both installed Bash completion and a portable
completion printer:

```bash
pienv completion bash
source <(pienv completion bash)
```

Completion should cover top-level commands, nested `coord`, `roles`,
`sandbox`, and `completion` subcommands, and known options for leaf commands.
Path-valued options should keep path completion. Rich descriptions are not a
Bash completion requirement; command discovery should rely on completion while
explanatory text comes from help.

Help should support:

```bash
pienv help
pienv help coord
pienv help coord status
pienv coord status --help
```

Leaf help may dispatch to the low-level command's `--help` output. Group help
should list available subcommands and their `pi-env-*` low-level equivalents.

## Compatibility decision

The old lower-level command names are intentionally not compatibility
entrypoints. The hard rename removes `pi-bwrap`, `bootstrap-coordination`,
`agent-coord-*`, `pi-serial-roles`, and `install-non-nix` from the supported
command surface. Users should call `pienv ...` for normal workflows or the
renamed `pi-env-*` command directly only for low-level/debug workflows.

## In-sandbox command surface

Pi TUI shell commands (`!` and `!!`) execute inside the Bubblewrap sandbox,
after `pienv --runtime ...` has already selected the runtime and started Pi.
The canonical namespace should therefore have a sandbox-aware mode rather than
trying to behave like the outer launcher recursively.

`pi-env-bwrap` should set an explicit in-sandbox marker such as
`PI_ENV_INSIDE_SANDBOX=1`. The dispatcher can use that marker to apply an
allow/block table:

- allow non-launcher discovery and diagnostic commands (`help`, grouped help,
  version/doctor-style output, completion printing when harmless, and
  `recipe` commands);
- allow coordination helpers that operate on the mounted project and
  coordination clone, including status/list/show and normal lifecycle helpers;
- allow `pienv coord bootstrap --print-only` for planning, while real
  bootstrap remains constrained by the mounted filesystem and available Git
  authentication;
- block runtime and process-boundary commands (`pienv` default launch,
  `run`, `--runtime ...`, `shell`, `sandbox`, `install`, and `uninstall`) with
  diagnostics that tell users to run the equivalent command in the outer
  terminal.

The implementation should expose the safe `pienv` entrypoint inside the
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

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| CMD-023 | PIENV-FRQ-20260711-092100-001 |
| CMD-024 | PIENV-FRQ-20260711-092100-002 |
| CMD-025 | PIENV-FRQ-20260711-092100-003 |
| CMD-026 | PIENV-FRQ-20260711-170000-001 |
| CMD-028 | PIENV-FRQ-20260725-125507-001 |
| CRQ-015 | PIENV-CRQ-20260711-092100-001 |
