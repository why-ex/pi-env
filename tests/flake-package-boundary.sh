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
const bwrap = readFileSync(join(repoRoot, "scripts", "pi-en-bwrap"), "utf8");
const readme = readFileSync(join(repoRoot, "README.md"), "utf8");
const design = readFileSync(join(repoRoot, "designs", "nix-runtime.md"), "utf8");
const legacyCoordinationPackage = "pi" + "-coordination";
const legacyConfigFile = ".pi" + "-coordination.yaml";

assert.doesNotMatch(flake, new RegExp(`${legacyCoordinationPackage}(?: =|-smoke)`));
assert.doesNotMatch(readme, new RegExp(legacyCoordinationPackage));
assert.doesNotMatch(readme, new RegExp(legacyConfigFile.replace(/\./g, "\\.")));
assert.doesNotMatch(design, new RegExp(legacyCoordinationPackage));

assert.match(flake, /includeCoordinationHelpers \? true/);
assert.match(flake, /mkPien = pkgs: \{ includeCoordinationHelpers \? true \}:/);
assert.match(flake, /pien = mkPien pkgs \{ inherit includeCoordinationHelpers; \};/);
assert.match(flake, /piSandboxCommandPath = pkgs\.lib\.makeBinPath/);
assert.match(flake, /export PI_EN_NIX_SANDBOX_COMMAND_PATH=/);
assert.match(flake, /piCorePien = mkPien pkgs \{ includeCoordinationHelpers = false; \};/);
assert.match(
  flake,
  /coordinationPackages = if includeCoordinationHelpers then agentCoordCommands else \[ \];/,
);
assert.match(flake, /pi-core = piCore;/);
assert.match(flake, /pi-en-coordination = piCoordination;/);
assert.match(flake, /pi-runtime = piRuntime;/);
assert.match(flake, /name = "pi-en-core";/);
assert.match(flake, /name = "pi-en-coordination";/);
assert.match(flake, /paths = coreRuntimePaths;/);
assert.match(flake, /paths = agentCoordCommandPackages;/);
assert.match(flake, /paths = coreRuntimePaths \+\+ agentCoordCommandPackages;/);
assert.match(flake, /"pi-en-coord-generate-requirements-coverage"/);
assert.match(flake, /pi-core-smoke/);
assert.match(flake, /pi-runtime-compat-smoke/);
assert.match(flake, /pi-en-coordination-smoke/);
assert.match(flake, /agent coordination helpers leaked into pi-core/);
assert.match(flake, /pien coord leaked into pi-core/);
assert.match(flake, /pien help run/);
assert.match(flake, /pien help raw/);
assert.match(flake, /pien help shell/);
assert.match(flake, /pien help sandbox/);
assert.match(flake, /pien sandbox --help/);
assert.match(flake, /pien help coord status/);
assert.match(flake, /pien coord requirements coverage --help/);
assert.match(flake, /pien help coord requirements generate/);
assert.match(flake, /pien roles serial --help/);
assert.match(flake, /pien install --help/);
assert.match(flake, /pien uninstall --help/);
assert.match(bwrap, /--setenv PI_EN_INSIDE_SANDBOX 1/);

assert.match(readme, /nix profile install ~\/src\/pi-en#pi-core/);
assert.match(readme, /nix profile install ~\/src\/pi-en#pi-en-coordination/);
assert.match(readme, /nix profile install ~\/src\/pi-en#pi-runtime/);
assert.match(readme, /includeCoordinationHelpers = false;/);
assert.match(readme, /`mkPiShell` defaults `includeCoordinationHelpers` to `true`/);
assert.match(readme, /pi-en\.packages\.\$\{system\}\.pi-core/);
assert.match(readme, /pi-en\.packages\.\$\{system\}\.pi-en-coordination/);
assert.match(readme, /`pi-runtime` continues to include the core runtime plus coordination helpers/);

assert.match(design, /`pi-core` contains `pi-en`, `pi-en-shell`, `pi-en-bwrap`, and the runtime tools/);
assert.match(design, /`pi-en-coordination` contains the Git-backed coordination helper commands/);
assert.match(design, /`pi-runtime` remains the bundle containing both sets of renamed commands/);
assert.match(design, /Projects that only need the sandbox\/runtime set it to `false`/);

console.log("flake package boundary tests passed");
NODE
