#!/usr/bin/env node
/**
 * Verdict check for the pre-registered experiments.
 *
 * Reads experiments/results.json and fails unless every recorded verdict is an
 * expected outcome. Kept next to the runner so `scripts/reproduce.sh` and CI
 * assert against the same list.
 *
 *   node experiments/check-verdicts.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const resultsPath = path.join(here, 'results.json');

// KILLED_JERK_KEPT_HAMPEL_CUSUM and DIAGNOSED_VARIANCE_DOUBLING are the two
// documented negative results (an adopted idea that lost to the incumbent).
const EXPECTED = new Set([
  'PASS',
  'KILLED_JERK_KEPT_HAMPEL_CUSUM',
  'DIAGNOSED_VARIANCE_DOUBLING',
]);

if (!fs.existsSync(resultsPath)) {
  console.error(`missing ${resultsPath} — run: node experiments/run_experiments.mjs`);
  process.exit(1);
}

const raw = JSON.parse(fs.readFileSync(resultsPath, 'utf8'));
const all = {};
for (const [group, payload] of Object.entries(raw)) {
  if (payload && typeof payload === 'object' && payload.verdicts) {
    Object.assign(all, payload.verdicts);
  }
}

const entries = Object.entries(all);
const unexpected = entries.filter(([, v]) => !EXPECTED.has(v));

console.log(`experiment groups: ${Object.keys(raw).length}`);
console.log(`verdicts: ${entries.length}  expected: ${entries.length - unexpected.length}  unexpected: ${unexpected.length}`);

if (unexpected.length > 0) {
  console.error('unexpected verdicts:');
  for (const [name, value] of unexpected) {
    console.error(`  ${name}: ${value}`);
  }
  process.exit(1);
}

console.log('all experiment verdicts are expected outcomes.');
