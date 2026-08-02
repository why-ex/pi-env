# Pi-env Flake Integration

Use this skill when a user asks you to add, fix, review, or explain pi-env
integration in an external project's `flake.nix`, especially when they want a
`nix develop .#agent` entrypoint for running `pienv` inside that project.

## Goal

Pi-env flake integration means wiring the project to pi-env's flake and making
`devShells.<system>.agent` / `nix develop .#agent` a pi-env-aware entrypoint.
Add or preserve the `.#agent` selector, and avoid replacing project-owned
default shells. Do not satisfy this request by creating a
project-native devshell that is merely named `agent`; the shell must expose
`pienv`, the pi-env runtime, and any explicitly requested coordination helpers
through `mkPiShell` or equivalent pi-env package outputs.

## Preferred helper

Before editing, prefer the canonical non-mutating recipe when it is available:

```bash
pienv recipe flake-agent-shell
```

Use the recipe output as the stable source for copyable snippets and wording.
If `pienv` is not on `PATH`, continue only when the existing project flake is
simple enough to edit safely from local context; otherwise ask how pi-env should
be referenced and where the agent shell should be merged.

## Suggested user prompt

When users want Pi to make this edit from inside an external project with a
complex flake, recommend this canonical wording:

```text
Use the pi-env-flake-integration skill. Modify flake.nix to add
devShells.${system}.agent using pi-env.lib.mkPiShell. Add pi-env as a
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
  pi-env-aware, preserve it and add an alias such as
  `agent = existingDevShells.default;` instead of replacing the default shell.
  Wrap a default devshell with `mkPiShell` only when the user asks for that
  style.
- Add `pi-env` as a flake input and include it in the outputs argument set
  without renaming unrelated inputs or changing the project's pins. Use
  `follows` only when it matches inputs already present in the project.
- Use `pi-env.lib.mkPiShell { inherit pkgs; ... }` for a dedicated pi-env-aware
  shell, or preserve an already pi-env-aware default shell and expose it as
  `.#agent` with an alias. Set `includeCoordinationHelpers` according to the
  user's needs; omit it or set it to `true` for projects using pi-env
  coordination helpers, and set it to `false` for a core-only shell.
- Put project-specific build/test tools in `extraPackages` only when the user
  asks for them or they are clearly part of the existing shell being preserved.
- Ask clarifying questions when the flake shape is too complex for a safe
  textual edit, when there are multiple plausible systems/devshell layers, or
  when adding pi-env would require choosing between conflicting project
  policies.

## Validation

After editing, run the narrowest practical checks for the project, for example:

```bash
nix flake check
nix develop .#agent --command pienv --help
```

If those checks are too expensive or unavailable, explain exactly what was not
run and why.
