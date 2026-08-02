#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

node <<'JS'
const fs = require('fs');
const path = require('path');

const coordRoots = ['.pi-en/coordination', 'coordination']
  .filter((dir) => fs.existsSync(dir));
const reqDirs = coordRoots.flatMap((root) => [
  path.join(root, 'requirements'),
  path.join(root, 'projects', 'pi-en', 'requirements'),
]).filter((dir) => fs.existsSync(dir));
const designsDir = 'designs';
const reqByKey = new Map();
let failed = false;

function fail(message) {
  console.error(message);
  failed = true;
}

for (const reqDir of reqDirs) {
  for (const file of fs.readdirSync(reqDir).filter((name) => name.endsWith('.yaml'))) {
    const text = fs.readFileSync(path.join(reqDir, file), 'utf8');
    const id = text.match(/^id: (.+)$/m)?.[1];
    const status = text.match(/^status: (.+)$/m)?.[1];
    const key = text.match(/^requirement_key: (.+)$/m)?.[1];
    if (!id || !key || status !== 'active' || reqByKey.has(key)) continue;
    reqByKey.set(key, id);
  }
}

const itemIdPattern = /\bPIEN-(?:ISS|FRQ|QRQ|CRQ|REQ|DEC|NOTE)-\d{8}-\d{6}-\d{3}\b/;
const rowPattern = /^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|$/;
const designFiles = fs.readdirSync(designsDir)
  .filter((name) => name.endsWith('.md'))
  .sort();

for (const file of designFiles) {
  const designPath = path.join(designsDir, file);
  const lines = fs.readFileSync(designPath, 'utf8').split(/\r?\n/);
  const coversIndexes = lines
    .map((line, index) => line === '## Covers' ? index : -1)
    .filter((index) => index >= 0);

  if (coversIndexes.length !== 1) {
    fail(`${designPath}: expected exactly one ## Covers section, found ${coversIndexes.length}`);
    continue;
  }

  const start = coversIndexes[0];
  if (lines[start + 1] !== '' ||
      lines[start + 2] !== '| Requirement | Coordination item |' ||
      lines[start + 3] !== '|-------------|-------------------|') {
    fail(`${designPath}: ## Covers must use the normalized table header`);
  }

  const tableLineIndexes = new Set([start + 2, start + 3]);
  let rowCount = 0;
  for (let i = start + 4; i < lines.length; i += 1) {
    const line = lines[i];
    if (!line.startsWith('|')) break;
    tableLineIndexes.add(i);
    rowCount += 1;
    const match = line.match(rowPattern);
    if (!match) {
      fail(`${designPath}:${i + 1}: malformed Covers row`);
      continue;
    }
    const key = match[1].trim();
    const itemId = match[2].trim();
    const activeId = reqByKey.get(key);
    if (!activeId) {
      fail(`${designPath}:${i + 1}: unknown or inactive requirement key ${key}`);
    } else if (activeId !== itemId) {
      fail(`${designPath}:${i + 1}: stale coordination item for ${key}: expected ${activeId}, got ${itemId}`);
    }
  }

  if (rowCount === 0) {
    fail(`${designPath}: ## Covers table must list at least one requirement`);
  }

  for (let i = 0; i < lines.length; i += 1) {
    if (tableLineIndexes.has(i)) continue;
    const match = lines[i].match(itemIdPattern);
    if (match) {
      fail(`${designPath}:${i + 1}: timestamped coordination item ID outside ## Covers table: ${match[0]}`);
    }
  }
}

if (failed) process.exit(1);
JS
