# Launcher Layering Design

`pi-en` exposes a small launcher stack that separates environment setup,
interactive agent startup, and sandbox execution. The boundary keeps each
entrypoint understandable and limits privileged or host-sensitive behavior to
the layer that needs it.

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-001 | PIEN-FRQ-20260612-210000-001 |
| UC-002 | PIEN-FRQ-20260612-210000-002 |
| UC-014 | PIEN-FRQ-20260612-210000-014 |
| UC-016 | PIEN-FRQ-20260612-210000-016 |
| CRQ-011 | PIEN-CRQ-20260613-183419-001 |
| CMD-001 | PIEN-FRQ-20260612-210000-032 |
| CMD-002 | PIEN-FRQ-20260612-210000-033 |
| CMD-003 | PIEN-FRQ-20260612-210000-034 |
| CMD-004 | PIEN-FRQ-20260612-210000-035 |
| CMD-005 | PIEN-FRQ-20260612-210000-036 |
| CMD-006 | PIEN-FRQ-20260612-210000-037 |
| CMD-007 | PIEN-FRQ-20260612-210000-038 |
| CMD-008 | PIEN-FRQ-20260612-210000-039 |
| CMD-018 | PIEN-FRQ-20260613-183404-001 |
| CMD-019 | PIEN-FRQ-20260613-183411-001 |
| CMD-021 | PIEN-FRQ-20260706-202632-001 |
| CMD-022 | PIEN-FRQ-20260706-202634-001 |

## 1. Layer responsibilities

`pi-en` is the outer entrypoint. It prepares paths, validates one selected
project root, and chooses whether the user wants a shell, a command, or an
agent launch. It owns argument compatibility for the command families covered
by `CMD-001` through `CMD-008`. The selected project root is the only primary
project for the run and is later mounted at `/workspace`; Pi-en does not manage
a host-side collection of projects.

`pi-en-shell` is the shell-oriented outer entrypoint. It should share the
same runtime-selection and flake bootstrap logic as `pi-en`, then pass an
explicit shell intent to the sandbox layer rather than constructing its own
Bubblewrap command.

Default `pi-en` startup is the agent-facing startup layer. After runtime
selection, `pi-en` translates the prepared workspace into the final `pi`
invocation policy: default tool allowlist, `--continue`, role-manager package
loading, and caller-supplied Pi arguments. This keeps startup ergonomics in the
user-facing command while still keeping sandbox construction separate.

`pi-en-bwrap` is the sandbox construction layer. It builds the Bubblewrap command
line and is the only layer that should assemble mount, environment, network,
and home-state isolation flags. Shell mode belongs here as a final-payload
switch: the sandbox setup remains identical, while the final process changes
from `pi` to Bash.

## 2. Command flow

The launchers pass structured intent downward rather than sharing hidden global
state. `pi-en` resolves the single project root and runtime inputs, applies the
default `UC-001` agent startup policy itself, then calls `pi-en-bwrap`. For the
custom-argument `UC-002` path, `pi-en --raw` calls `pi-en-bwrap` directly.
`pi-en-shell` resolves the same runtime inputs, then calls `pi-en-bwrap` shell
mode.

This shape lets `CMD-018` and the launcher-facing part of `CMD-019` add role
manager integration without changing the sandbox contract. Role selection is
interpreted before the final `pi` process starts; sandboxing still receives a
normal command and environment policy. Tool allowlist overrides for `UC-014`
and globally-installed Pi discovery for `UC-016` are launcher inputs that are
translated into normal Pi arguments and read-only runtime mounts.

## 3. Command stability and diagnostics

Launchers should fail early for unsupported arguments, missing project roots, or
missing runtime tools. Error messages should identify the layer that rejected
the request so users know whether to adjust launch flags, Pi startup options,
or sandbox settings.

The layering intentionally removes `pi-start` as a user-visible command because
this project has no known external users and the command adds unnecessary
surface area. The same early-stage policy permits hard-renaming the sandbox
layer to `pi-en-bwrap` without old-name shims. Command semantics should remain
stable while implementation detail moves between scripts as long as the
ownership boundaries above are maintained.
