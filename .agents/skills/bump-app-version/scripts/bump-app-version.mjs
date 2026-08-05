#!/usr/bin/env node
/**
 * Bump AppScope/app.json5 versionName and versionCode for JustPDF.
 *
 * Usage:
 *   node bump-app-version.mjs --version-name 1.3.0
 *   node bump-app-version.mjs --version-name 1.3.0 --version-code 1000011
 *   node bump-app-version.mjs --version-name 1.3.0 --dry-run
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../../../..');
const appJsonPath = path.join(repoRoot, 'AppScope', 'app.json5');

function parseArgs(argv) {
  const out = {
    versionName: undefined,
    versionCode: undefined,
    dryRun: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--version-name' || arg === '-n') {
      out.versionName = argv[++i];
    } else if (arg === '--version-code' || arg === '-c') {
      out.versionCode = argv[++i];
    } else if (arg === '--dry-run') {
      out.dryRun = true;
    } else if (arg === '--help' || arg === '-h') {
      out.help = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return out;
}

function normalizeVersionName(raw) {
  if (raw === undefined || raw === null) {
    throw new Error('Missing --version-name (e.g. 1.3.0)');
  }
  let s = String(raw).trim();
  if (s.startsWith('v') || s.startsWith('V')) {
    s = s.slice(1);
  }
  // Accept compact forms like 130 -> 1.3.0 when exactly 3 digits
  if (/^\d{3}$/.test(s)) {
    s = `${s[0]}.${s[1]}.${s[2]}`;
  }
  if (!/^\d+\.\d+\.\d+$/.test(s)) {
    throw new Error(`Invalid versionName "${raw}". Expected X.Y.Z (or compact 130).`);
  }
  return s;
}

function extractField(text, field) {
  const re = new RegExp(`"${field}"\\s*:\\s*([^,\\n]+)`);
  const m = text.match(re);
  if (!m) {
    throw new Error(`Could not find "${field}" in ${appJsonPath}`);
  }
  return m[1].trim();
}

function replaceField(text, field, valueLiteral) {
  const re = new RegExp(`("${field}"\\s*:\\s*)([^,\\n]+)`);
  if (!re.test(text)) {
    throw new Error(`Could not replace "${field}" in ${appJsonPath}`);
  }
  return text.replace(re, `$1${valueLiteral}`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(`Usage:
  node bump-app-version.mjs --version-name 1.3.0
  node bump-app-version.mjs --version-name 1.3.0 --version-code 1000011
  node bump-app-version.mjs --version-name 1.3.0 --dry-run`);
    process.exit(0);
  }

  const nextName = normalizeVersionName(args.versionName);
  const text = fs.readFileSync(appJsonPath, 'utf8');
  const oldNameRaw = extractField(text, 'versionName');
  const oldCodeRaw = extractField(text, 'versionCode');
  const oldName = oldNameRaw.replace(/^"|"$/g, '');
  const oldCode = Number.parseInt(oldCodeRaw, 10);
  if (!Number.isFinite(oldCode)) {
    throw new Error(`Invalid current versionCode: ${oldCodeRaw}`);
  }

  let nextCode;
  if (args.versionCode !== undefined) {
    nextCode = Number.parseInt(String(args.versionCode), 10);
    if (!Number.isFinite(nextCode)) {
      throw new Error(`Invalid --version-code: ${args.versionCode}`);
    }
  } else {
    nextCode = oldCode + 1;
  }

  if (nextCode <= oldCode) {
    throw new Error(`versionCode must increase (current ${oldCode}, requested ${nextCode})`);
  }

  let next = text;
  next = replaceField(next, 'versionName', `"${nextName}"`);
  next = replaceField(next, 'versionCode', String(nextCode));

  const summary = {
    file: path.relative(repoRoot, appJsonPath).replace(/\\/g, '/'),
    versionName: { from: oldName, to: nextName },
    versionCode: { from: oldCode, to: nextCode },
    dryRun: args.dryRun,
  };

  if (!args.dryRun) {
    fs.writeFileSync(appJsonPath, next, 'utf8');
  }

  console.log(JSON.stringify(summary, null, 2));
}

try {
  main();
} catch (err) {
  console.error(String(err && err.message ? err.message : err));
  process.exit(1);
}
