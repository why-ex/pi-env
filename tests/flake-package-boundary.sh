#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

REPO_ROOT="$repo_root" node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.env.REPO_ROOT;
const flake = readFileSync(join(repoRoot, "flake.nix"), "utf8");
const bwrap = readFileSync(join(repoRoot, "scripts", "pi-env-bwrap"), "utf8");
const readme = readFileSync(join(repoRoot, "README.md"), "utf8");
const design = readFileSync(join(repoRoot, "designs", "nix-runtime.md"), "utf8");
const legacyCoordinationPackage = "pi" + "-coordination";
const legacyConfigFile = ".pi" + "-coordination.yaml";

assert.doesNotMatch(flake, new RegExp(`${legacyCoordinationPackage}(?: =|-smoke)`));
assert.doesNotMatch(readme, new RegExp(legacyCoordinationPackage));
assert.doesNotMatch(readme, new RegExp(legacyConfigFile.replace(/\./g, "\\.")));
assert.doesNotMatch(design, new RegExp(legacyCoordinationPackage));

assert.match(flake, /includeCoordinationHelpers \? true/);
assert.match(flake, /mkPienv = pkgs: \{ includeCoordinationHelpers \? true \}:/);
assert.match(flake, /pienv = mkPienv pkgs \{ inherit includeCoordinationHelpers; \};/);
assert.match(flake, /piSandboxCommandPath = pkgs\.lib\.makeBinPath/);
assert.match(flake, /export PI_ENV_NIX_SANDBOX_COMMAND_PATH=/);
assert.match(flake, /piCorePienv = mkPienv pkgs \{ includeCoordinationHelpers = false; \};/);
assert.match(
  flake,
  /coordinationPackages = if includeCoordinationHelpers then agentCoordCommands else \[ \];/,
);
assert.match(flake, /pi-core = piCore;/);
assert.match(flake, /pi-env-coordination = piCoordination;/);
assert.match(flake, /pi-runtime = piRuntime;/);
assert.match(flake, /name = "pi-env-core";/);
assert.match(flake, /name = "pi-env-coordination";/);
assert.match(flake, /paths = coreRuntimePaths;/);
assert.match(flake, /paths = agentCoordCommandPackages;/);
assert.match(flake, /paths = coreRuntimePaths \+\+ agentCoordCommandPackages;/);
assert.match(flake, /"pi-env-coord-generate-requirements-coverage"/);
assert.match(flake, /pi-core-smoke/);
assert.match(flake, /pi-runtime-compat-smoke/);
assert.match(flake, /pi-env-coordination-smoke/);
assert.match(flake, /agent coordination helpers leaked into pi-core/);
assert.match(flake, /pienv coord leaked into pi-core/);
assert.match(flake, /pienv help run/);
assert.match(flake, /pienv help raw/);
assert.match(flake, /pienv help shell/);
assert.match(flake, /pienv help sandbox/);
assert.match(flake, /pienv sandbox --help/);
assert.match(flake, /pienv help coord status/);
assert.match(flake, /pienv coord requirements coverage --help/);
assert.match(flake, /pienv help coord requirements generate/);
assert.match(flake, /pienv roles serial --help/);
assert.match(flake, /pienv install --help/);
assert.match(flake, /pienv uninstall --help/);
assert.match(bwrap, /--setenv PI_ENV_INSIDE_SANDBOX 1/);

assert.match(readme, /nix profile install ~\/src\/pi-env#pi-core/);
assert.match(readme, /nix profile install ~\/src\/pi-env#pi-env-coordination/);
assert.match(readme, /nix profile install ~\/src\/pi-env#pi-runtime/);
assert.match(readme, /includeCoordinationHelpers = false;/);
assert.match(readme, /`mkPiShell` defaults `includeCoordinationHelpers` to `true`/);
assert.match(readme, /pi-env\.packages\.\$\{system\}\.pi-core/);
assert.match(readme, /pi-env\.packages\.\$\{system\}\.pi-env-coordination/);
assert.match(readme, /`pi-runtime` continues to include the core runtime plus coordination helpers/);

assert.match(design, /`pi-core` contains `pi-env`, `pi-env-shell`, `pi-env-bwrap`, and the runtime tools/);
assert.match(design, /`pi-env-coordination` contains the Git-backed coordination helper commands/);
assert.match(design, /`pi-runtime` remains the bundle containing both sets of renamed commands/);
assert.match(design, /Projects that only need the sandbox\/runtime set it to `false`/);

console.log("flake package boundary tests passed");
NODE
