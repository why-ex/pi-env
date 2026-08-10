# Pi-en Flake Integration

Use this skill when a user asks you to add, fix, review, or explain Pi-en
integration in an external project's `flake.nix`, especially when they want a
`nix develop .#agent` entrypoint for running `pien` inside that project.

## Goal

Pi-en flake integration means wiring the project to Pi-en's flake and making
`devShells.<system>.agent` / `nix develop .#agent` a Pi-en-aware entrypoint.
Add or preserve the `.#agent` selector, and avoid replacing project-owned
default shells. Do not satisfy this request by creating a
project-native devshell that is merely named `agent`; the shell must expose
`pien`, the Pi-en runtime, and any explicitly requested coordination helpers
through `mkPiShell` or equivalent Pi-en package outputs.

## Preferred helper

Before editing, prefer the canonical non-mutating recipe when it is available:

```bash
pien recipe flake-agent-shell
```

Use the recipe output as the stable source for copyable snippets and wording.
If `pien` is not on `PATH`, continue only when the existing project flake is
simple enough to edit safely from local context; otherwise ask how Pi-en should
be referenced and where the agent shell should be merged.

## Suggested user prompt

When users want Pi to make this edit from inside an external project with a
complex flake, recommend this canonical wording:

```text
Use the pi-en-flake-integration skill. Modify flake.nix to add
devShells.${system}.agent using pi-en.lib.mkPiShell. Add pi-en as a
flake input, add it to outputs, preserve existing devShells and package
outputs, and do not create a project-native agentProfile unless I
explicitly ask for one.
```

## Editing rules

- Preserve the existing flake structure. Keep current `outputs` layout,
  `eachDefaultSystem`, flake-parts, devenv, FHS/container builders, overlays,
  package outputs, formatter/check outputs, and other project policy unless the
  user explicitly requests a larger refactor.
- Preserve existing devshells, shell hooks, environment variables, and package
  lists. Add a dedicated `agent` shell by merging into the existing devshell
  attrset at the smallest safe point. If the existing default shell is already
  Pi-en-aware, preserve it and add an alias such as
  `agent = existingDevShells.default;` instead of replacing the default shell.
  Wrap a default devshell with `mkPiShell` only when the user asks for that
  style.
- Add `pi-en` as a flake input and include it in the outputs argument set
  without renaming unrelated inputs or changing the project's pins. Use
  `follows` only when it matches inputs already present in the project.
- Use `pi-en.lib.mkPiShell { inherit pkgs; ... }` for a dedicated Pi-en-aware
  shell, or preserve an already Pi-en-aware default shell and expose it as
  `.#agent` with an alias. Set `includeCoordinationHelpers` according to the
  user's needs; omit it or set it to `true` for projects using Pi-en
  coordination helpers, and set it to `false` for a core-only shell.
- Put project-specific build/test tools in `extraPackages` only when the user
  asks for them or they are clearly part of the existing shell being preserved.
- Ask clarifying questions when the flake shape is too complex for a safe
  textual edit, when there are multiple plausible systems/devshell layers, or
  when adding Pi-en would require choosing between conflicting project
  policies.

## Pi-en input updates

When a Pi-en-enabled Nix shell provides `pi-en-update`, use it only for the
narrow task of updating the consuming project's `pi-en` flake input. Inside
`pi-en.lib.mkPiShell`, `pi-en-update` / `pien update` uses normal Nix-shell
`PATH` precedence and accepts only `--url`, `--ref`, and help. Omitted source
parts stay unchanged, no source options is a no-op, and any explicit source
option still refreshes the lock even when `flake.nix` is unchanged. Outside
that shell, the same command name refers to the non-Nix installed-prefix updater
and should not be recommended for editing project flakes.

For pinned branch commits, prefer the shared `COMMIT@BRANCH` user syntax, for
example `pi-en-update --url https://github.com/u2up/pi-en.git --ref abc123@main`.
The updater translates that form to a Nix Git flake URL with both `ref=main`
and `rev=abc123`. It rewrites supported direct URL assignments such as
`pi-en.url`, `inputs.pi-en.url`, and `"pi-en".url`; if the project flake defines
its `pi-en` input dynamically or in another unsupported form, ask for guidance
or make a small manual edit instead of relying on broad automated rewriting.
After either helper-driven or manual updates, review and commit the resulting
`flake.nix` and/or `flake.lock` changes.

## Validation

After editing, run the narrowest practical checks for the project, for example:

```bash
nix flake check
nix develop .#agent --command pien --help
```

If those checks are too expensive or unavailable, explain exactly what was not
run and why.
