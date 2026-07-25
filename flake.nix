{
  description = "Reusable Pi coding-agent runtime with bubblewrap isolation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      defaultTools = "read,bash,edit,write,grep,find,ls";

      mkRuntime = pkgs:
        with pkgs; [
          bash
          bubblewrap
          cacert
          coreutils
          fd
          findutils
          gawk
          git
          gnugrep
          gnused
          gnutar
          gzip
          jq
          nodejs
          ripgrep
          which
        ];

      mkDevShellTools = pkgs:
        with pkgs; [
          diffutils
          patch
        ];

      mkPiBwrap = pkgs:
        let
          runtimePackages = mkRuntime pkgs;
          runtimePath = pkgs.lib.makeBinPath runtimePackages;
        in
        pkgs.writeShellScriptBin "pi-env-bwrap" ''
          set -euo pipefail
          export PI_ENV_RUNTIME_PATH="${runtimePath}"
          export PI_ENV_BWRAP_COMPILED_DEFAULT_TOOLS="${defaultTools}"
          export PI_ENV_BWRAP_BASH="${pkgs.bash}/bin/bash"
          export PI_ENV_BWRAP_ENV="${pkgs.coreutils}/bin/env"
          export PI_ENV_BWRAP_CA_BUNDLE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          export PI_ENV_BWRAP_BWRAP="${pkgs.bubblewrap}/bin/bwrap"
          exec ${pkgs.bash}/bin/bash ${./scripts/pi-env-bwrap} "$@"
        '';

      mkPiEnv = pkgs:
        let
          piBwrap = mkPiBwrap pkgs;
          roleManagerPackage = mkRoleManagerPackage pkgs;
          runtimePath = pkgs.lib.makeBinPath (mkRuntime pkgs);
        in
        pkgs.writeShellScriptBin "pi-env" ''
          set -euo pipefail
          export PATH="${runtimePath}:''${PATH:-}"
          export PI_ENV_BWRAP_COMPILED_DEFAULT_TOOLS="${defaultTools}"
          export PI_ENV_ROLE_MANAGER_PACKAGE="''${PI_ENV_ROLE_MANAGER_PACKAGE:-${roleManagerPackage}}"
          export PI_ENV_PI_ENV_BWRAP="${piBwrap}/bin/pi-env-bwrap"
          exec -a pi-env ${pkgs.bash}/bin/bash ${./scripts/pi-env-launcher} "$@"
        '';

      mkPiEnvShell = pkgs:
        let
          piBwrap = mkPiBwrap pkgs;
          runtimePath = pkgs.lib.makeBinPath (mkRuntime pkgs);
        in
        pkgs.writeShellScriptBin "pi-env-shell" ''
          set -euo pipefail
          export PATH="${runtimePath}:''${PATH:-}"
          export PI_ENV_SHELL_MODE=1
          export PI_ENV_PI_ENV_BWRAP="${piBwrap}/bin/pi-env-bwrap"
          exec -a pi-env-shell ${pkgs.bash}/bin/bash ${./scripts/pi-env-launcher} "$@"
        '';

      mkPienv = pkgs: { includeCoordinationHelpers ? true }:
        let
          coordinationCommands = if includeCoordinationHelpers then builtins.attrValues (mkAgentCoordCommands pkgs) else [ ];
          installCommands = builtins.attrValues (mkInstallNonNixCommands pkgs);
          runtimePath = pkgs.lib.makeBinPath ((mkRuntime pkgs) ++ [
            (mkPiEnv pkgs)
            (mkPiEnvShell pkgs)
            (mkPiBwrap pkgs)
          ] ++ installCommands ++ coordinationCommands);
          pienvBin = pkgs.writeShellScriptBin "pienv" ''
            set -euo pipefail
            export PATH="${runtimePath}:''${PATH:-}"
            exec -a pienv ${pkgs.bash}/bin/bash ${./scripts/pienv} "$@"
          '';
        in
        pkgs.runCommand "pienv" { } ''
          mkdir -p "$out/bin" "$out/share/bash-completion/completions"
          ln -s ${pienvBin}/bin/pienv "$out/bin/pienv"
          ${pkgs.bash}/bin/bash ${./scripts/pienv} completion bash > "$out/share/bash-completion/completions/pienv"
        '';

      agentCoordCommandNames = [
        "pi-env-bootstrap-coordination"
        "pi-env-coord-init"
        "pi-env-coord-clone"
        "pi-env-coord-status"
        "pi-env-coord-list"
        "pi-env-coord-cat"
        "pi-env-coord-pull"
        "pi-env-coord-push"
        "pi-env-coord-new"
        "pi-env-coord-repo"
        "pi-env-coord-claim"
        "pi-env-coord-done"
        "pi-env-coord-review"
        "pi-env-coord-verify"
        "pi-env-coord-close"
        "pi-env-coord-lint"
        "pi-env-coord-generate-requirements"
        "pi-env-coord-generate-requirements-coverage"
        "pi-env-coord-upgrade-rules"
        "pi-env-serial-roles"
      ];

      mkAgentCoordSupport = pkgs:
        pkgs.runCommand "pi-env-agent-coordination-support" { } ''
          mkdir -p "$out/share/pi-env"
          cp -R ${./pi-skill-templates} "$out/share/pi-env/pi-skill-templates"
          cp -R ${./role-manager} "$out/share/pi-env/role-manager"
          cp -R ${./scripts} "$out/share/pi-env/scripts"
          chmod +x "$out/share/pi-env/scripts"/pi-env-coord-* \
            "$out/share/pi-env/scripts/pi-env-bootstrap-coordination" \
            "$out/share/pi-env/scripts/pi-env-serial-roles" \
            "$out/share/pi-env/scripts/pienv" \
            "$out/share/pi-env/scripts/pi-env-install-non-nix"
        '';

      mkInstallNonNixCommands = pkgs:
        let
          runtimePath = pkgs.lib.makeBinPath (mkRuntime pkgs);
          support = mkAgentCoordSupport pkgs;
          installNonNix = pkgs.writeShellScriptBin "pi-env-install-non-nix" ''
            set -euo pipefail
            export PATH="${runtimePath}:''${PATH:-}"
            exec ${pkgs.bash}/bin/bash "${support}/share/pi-env/scripts/pi-env-install-non-nix" "$@"
          '';
          piEnvUninstall = pkgs.writeShellScriptBin "pi-env-uninstall" ''
            set -euo pipefail
            export PATH="${runtimePath}:''${PATH:-}"
            exec ${pkgs.bash}/bin/bash "${support}/share/pi-env/scripts/pi-env-install-non-nix" --uninstall "$@"
          '';
        in
        {
          inherit installNonNix piEnvUninstall;
        };

      mkAgentCoordCommand = pkgs: name:
        let
          runtimePath = pkgs.lib.makeBinPath (mkRuntime pkgs);
          support = mkAgentCoordSupport pkgs;
          roleManagerPackage = mkRoleManagerPackage pkgs;
        in
        pkgs.writeShellScriptBin name ''
          set -euo pipefail
          export PATH="${runtimePath}:''${PATH:-}"
          export PI_ENV_COORD_TEMPLATE_DIR="${support}/share/pi-env/pi-skill-templates/agent-coordination"
          export PI_ENV_COORD_LIB="${support}/share/pi-env/scripts/pi-env-coord-lib.sh"
          export PI_ENV_ROLE_MANAGER_PACKAGE="''${PI_ENV_ROLE_MANAGER_PACKAGE:-${roleManagerPackage}}"
          exec ${pkgs.bash}/bin/bash "${support}/share/pi-env/scripts/${name}" "$@"
        '';

      mkAgentCoordCommands = pkgs:
        builtins.listToAttrs (map (name: {
          inherit name;
          value = mkAgentCoordCommand pkgs name;
        }) agentCoordCommandNames);

      mkRoleManagerPackage = pkgs:
        pkgs.runCommand "pi-env-role-manager" { } ''
          mkdir -p "$out"
          cp -R ${./role-manager}/. "$out/"
        '';

      mkPiShell =
        { pkgs
        , extraPackages ? [ ]
        , shellHook ? ""
        , includeCoordinationHelpers ? true
        }:
        let
          piBwrap = mkPiBwrap pkgs;
          piEnv = mkPiEnv pkgs;
          piEnvShell = mkPiEnvShell pkgs;
          pienv = mkPienv pkgs { inherit includeCoordinationHelpers; };
          agentCoordCommands = builtins.attrValues (mkAgentCoordCommands pkgs);
          coordinationPackages = if includeCoordinationHelpers then agentCoordCommands else [ ];
          roleManagerPackage = mkRoleManagerPackage pkgs;
          piSandboxCommandPath = pkgs.lib.makeBinPath ([
            piBwrap
            piEnv
            piEnvShell
            pienv
          ] ++ coordinationPackages);
          extraPackagePath = pkgs.lib.makeBinPath (extraPackages ++ [
            piBwrap
            piEnv
            piEnvShell
            pienv
          ] ++ coordinationPackages);
        in
        pkgs.mkShell {
          packages = (mkRuntime pkgs) ++ (mkDevShellTools pkgs) ++ [
            piBwrap
            piEnv
            piEnvShell
            pienv
          ] ++ coordinationPackages ++ extraPackages;

          shellHook = ''
            export PS1="(nix-dev) \u@\h:\w$ "
            export PI_ENV_DEV_SHELL_PS1="$PS1"
            export PI_ENV_ROLE_MANAGER_PACKAGE="${roleManagerPackage}"
            export PI_ENV_NIX_PROJECT_BWRAP="${piBwrap}/bin/pi-env-bwrap"
            export PI_ENV_NIX_SANDBOX_COMMAND_PATH="${piSandboxCommandPath}"
            if [ -n "${extraPackagePath}" ]; then
              if [ -n "''${PI_ENV_BWRAP_EXTRA_PATH:-}" ]; then
                export PI_ENV_BWRAP_EXTRA_PATH="${extraPackagePath}:$PI_ENV_BWRAP_EXTRA_PATH"
              else
                export PI_ENV_BWRAP_EXTRA_PATH="${extraPackagePath}"
              fi
            fi
            if [ -z "''${PI_ENV_QUIET:-}" ]; then
              echo "Pi agent runtime loaded"
              echo "Use 'pienv' for default startup, 'pienv shell' for a sandbox shell, or 'pienv raw -- <pi args>' for custom runs."
            fi
          '' + shellHook;
        };
    in
    {
      lib = {
        inherit
          defaultTools
          mkRuntime
          mkDevShellTools
          mkPiBwrap
          mkPiEnv
          mkPiEnvShell
          mkPienv
          mkInstallNonNixCommands
          agentCoordCommandNames
          mkAgentCoordSupport
          mkAgentCoordCommand
          mkAgentCoordCommands
          mkRoleManagerPackage
          mkPiShell;
      };
    }
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        piBwrap = mkPiBwrap pkgs;
        piEnv = mkPiEnv pkgs;
        piEnvShell = mkPiEnvShell pkgs;
        pienv = mkPienv pkgs { };
        agentCoordCommands = mkAgentCoordCommands pkgs;
        agentCoordCommandPackages = builtins.attrValues agentCoordCommands;
        roleManagerPackage = mkRoleManagerPackage pkgs;
        piCorePienv = mkPienv pkgs { includeCoordinationHelpers = false; };
        coreRuntimePaths = (mkRuntime pkgs) ++ [
          piBwrap
          piEnv
          piEnvShell
          piCorePienv
        ];
        piCore = pkgs.buildEnv {
          name = "pi-env-core";
          paths = coreRuntimePaths;
        };
        piCoordination = pkgs.buildEnv {
          name = "pi-env-coordination";
          paths = agentCoordCommandPackages;
        };
        piRuntime = pkgs.buildEnv {
          name = "pi-env-runtime";
          paths = coreRuntimePaths ++ agentCoordCommandPackages;
        };
        smokeCheck = name: nativeBuildInputs: script:
          pkgs.runCommand name { inherit nativeBuildInputs; } ''
            set -euo pipefail
            ${script}
            touch "$out"
          '';
      in
      {
        packages = {
          default = piEnv;
          pi-env = piEnv;
          pienv = pienv;
          pi-env-shell = piEnvShell;
          pi-env-bwrap = piBwrap;
          pi-core = piCore;
          pi-runtime = piRuntime;
          pi-env-coordination = piCoordination;
          pi-role-manager = roleManagerPackage;
        } // agentCoordCommands;

        apps = {
          default = {
            type = "app";
            program = "${piEnv}/bin/pi-env";
          };
          pi-env = {
            type = "app";
            program = "${piEnv}/bin/pi-env";
          };
          pienv = {
            type = "app";
            program = "${pienv}/bin/pienv";
          };
          pi-env-shell = {
            type = "app";
            program = "${piEnvShell}/bin/pi-env-shell";
          };
          pi-env-bwrap = {
            type = "app";
            program = "${piBwrap}/bin/pi-env-bwrap";
          };
        };

        checks = {
          pi-core-smoke = smokeCheck "pi-env-core-smoke" [ piCore ] ''
            command -v pi-env >/dev/null
            command -v pienv >/dev/null
            command -v pi-env-shell >/dev/null
            if command -v pi-start >/dev/null 2>&1; then
              echo "pi-start leaked into pi-core" >&2
              exit 1
            fi
            for legacy in pi-bwrap pi-serial-roles install-non-nix; do
              if command -v "$legacy" >/dev/null 2>&1; then
                echo "$legacy leaked into pi-core" >&2
                exit 1
              fi
            done
            command -v pi-env-bwrap >/dev/null
            pi-env --help >/dev/null
            pienv help >/dev/null
            pienv help run >/dev/null
            pienv help raw >/dev/null
            pienv help shell >/dev/null
            pienv help sandbox >/dev/null
            pienv sandbox --help >/dev/null
            pienv completion bash >/dev/null
            pienv install --help >/dev/null
            pienv uninstall --help >/dev/null
            if pienv coord status --help >/dev/null 2>&1; then
              echo "pienv coord leaked into pi-core" >&2
              exit 1
            fi
            pi-env-shell --help >/dev/null
            pi-env-bwrap --help >/dev/null
            if command -v pi-env-coord-status >/dev/null 2>&1; then
              echo "agent coordination helpers leaked into pi-core" >&2
              exit 1
            fi
          '';

          pi-runtime-compat-smoke = smokeCheck "pi-env-runtime-compat-smoke" [ piRuntime ] ''
            command -v pi-env >/dev/null
            command -v pienv >/dev/null
            command -v pi-env-shell >/dev/null
            if command -v pi-start >/dev/null 2>&1; then
              echo "pi-start leaked into pi-runtime" >&2
              exit 1
            fi
            for legacy in pi-bwrap pi-serial-roles install-non-nix; do
              if command -v "$legacy" >/dev/null 2>&1; then
                echo "$legacy leaked into pi-runtime" >&2
                exit 1
              fi
            done
            command -v pi-env-bwrap >/dev/null
            command -v pi-env-coord-status >/dev/null
            command -v pi-env-bootstrap-coordination >/dev/null
            pi-env --help >/dev/null
            pienv help >/dev/null
            pienv help run >/dev/null
            pienv help raw >/dev/null
            pienv help shell >/dev/null
            pienv help sandbox >/dev/null
            pienv sandbox --help >/dev/null
            pienv coord status --help >/dev/null
            pienv help coord status >/dev/null
            pienv coord requirements coverage --help >/dev/null
            pienv help coord requirements generate >/dev/null
            pienv roles serial --help >/dev/null
            pienv completion bash >/dev/null
            pienv install --help >/dev/null
            pienv uninstall --help >/dev/null
            pi-env-shell --help >/dev/null
            pi-env-coord-status --help >/dev/null
          '';

          pi-env-coordination-smoke = smokeCheck "pi-env-coordination-smoke" [ piCoordination ] ''
            command -v pi-env-coord-status >/dev/null
            command -v pi-env-coord-repo >/dev/null
            command -v pi-env-coord-lint >/dev/null
            command -v pi-env-bootstrap-coordination >/dev/null
            pi-env-coord-lint --help >/dev/null
            pi-env-bootstrap-coordination --help >/dev/null
          '';
        };

        devShells.default = mkPiShell { inherit pkgs; };
      });
}
