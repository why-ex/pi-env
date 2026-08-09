# Host Runtime Design

Host runtime mode lets direct `pi-en` users run Pi inside the Bubblewrap
workspace sandbox without first entering Nix. The design keeps the isolation
layer as the product default while making reproducible Nix tool pinning an
explicit opt-in for users and teams that want it.

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-025 | PIEN-FRQ-20260701-110508-001 |
| RUNTIME-004 | PIEN-FRQ-20260701-110510-001 |
| RUNTIME-005 | PIEN-FRQ-20260701-110512-001 |
| INSTALL-001 | PIEN-FRQ-20260701-182129-001 |
| INSTALL-002 | PIEN-FRQ-20260702-064100-001 |
| INSTALL-003 | PIEN-FRQ-20260809-181859-001 |
| PATH-006 | PIEN-FRQ-20260701-110514-001 |
| FS-011 | PIEN-FRQ-20260701-110516-001 |
| AGENT-017 | PIEN-FRQ-20260701-110518-001 |
| CRQ-014 | PIEN-CRQ-20260701-110520-001 |
| TEST-033 | PIEN-QRQ-20260701-110522-001 |
| DOC-004 | PIEN-QRQ-20260701-110524-001 |

## 1. Runtime modes

The launcher should resolve a runtime mode before it performs any fallback
that can enter Nix. Direct checkout usage defaults to `host`; Nix-provided
package, app, profile, and devshell entrypoints keep their existing Nix-backed
behavior unless a future implementation explicitly supports a tested override.

The mode selector should be available both as a CLI option and as an
environment variable, with CLI taking precedence. Host mode failures must be
host-mode failures: if a required host command is missing, the launcher should
print missing tool diagnostics and suggest Nix rather than silently invoking
`nix develop`.

## 2. Conservative host tool exposure

Host mode does not mean inheriting the caller's full environment. It constructs
an in-sandbox PATH from documented allowlisted host command directories, such
as `/usr/local/bin`, `/usr/bin`, and `/bin` when present. Additional host tool
paths need explicit opt-in, canonicalization, existence checks, and read-only
mounts.

The Nix-mode extra path contract remains separate: `PI_EN_BWRAP_EXTRA_PATH` stays
constrained to validated `/nix/store` paths unless a future change deliberately
renames or splits the host-mode interface. This prevents host runtime support
from weakening Nix-mode safety guarantees.

## 3. Filesystem and agent resources

Host mode may need read-only mounts for dynamic loader, library, share,
certificate, and alternatives directories so admitted host binaries run inside
Bubblewrap. These support mounts are not permission to mount host home,
credentials, Docker sockets, or unrelated projects by default.

Pi discovery follows the same rule. System or globally installed Pi paths can
work when covered by default read-only runtime mounts. Pi or role-manager paths
under host home require a fail-closed diagnostic or an explicit read-only bind
opt-in, with any outside path rewritten to its in-sandbox mount point before
being passed to Pi.

## 4. Non-Nix installation

The first non-Nix installation path should package Pi-en files rather than a
runtime toolchain. It should install command wrappers to a conventional prefix
such as `~/.local` or `/usr/local`, install shared support files under a stable
data directory such as `$PREFIX/share/pi-en`, and make installed wrappers
resolve the same support paths Nix currently injects for coordination helpers,
templates, and role-manager package data.

End-user installation should not require cloning the full Pi-en repository.
Direct checkout installation can remain available for contributors, but the
normal non-Nix path should work from a published release archive, downloaded
installer, or equivalent artifact. The installer may operate as a bootstrapper:
when the local payload is absent and the user supplies an explicit remote ref or
artifact URL, it fetches the payload into a temporary directory and installs
from there. `main` branch installs must be explicit and documented as mutable
latest/development installs, while tagged releases or release artifacts remain
the preferred stable channel.

Uninstall should work from installed state, such as an installed uninstall
command or manifest, without needing the original source checkout, network
access, or temporary downloaded artifact.

A later Git-source extension should prefer an explicit `--url URL --ref REF`
mode for arbitrary local or remote Git repositories. This mode should resolve
branches, tags, and `COMMIT@BRANCH` pins in a temporary clone or worktree, then
install from the checked-out payload. Explicit Git source inputs must take
precedence over local payload discovery so an installed updater does not
mistake `$PREFIX/share/pi-en` for the desired source. The installer should
record requested source inputs and the resolved commit in installed origin
metadata, then generate a `pi-en-update` wrapper that reuses those stored
values unless the user supplies replacements.

This keeps the adoption path lightweight while preserving a clear boundary:
non-Nix installs use host-provided tools and are not reproducible or pinned by
Pi-en. Nix remains the pinned runtime for teams that need reproducibility.

## 5. Documentation and verification

Docs must distinguish Bubblewrap sandboxing from runtime pinning: sandboxing is
default; host runtime is unpinned; Nix runtime is reproducible and pinned.
Blackbox tests should use fake `pi` and fake `bwrap` commands to assert mode
selection, missing dependency handling, PATH construction, read-only mounts,
and absence of sensitive default mounts. Installer tests should install into a
temporary prefix from both source-checkout and release/archive-style layouts,
then verify representative installed commands can locate their support files
without invoking Nix.
