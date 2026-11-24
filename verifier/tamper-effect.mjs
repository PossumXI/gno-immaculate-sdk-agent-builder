// Writes a copy of an EffectJSON document with one step receipt changed and the leaves re-hashed from the changed
// fields, so the copy fails on the hash chain rather than on a stale leaf. The acceptance test uses it to show the
// offline verifier refuses a tampered life. Usage: node tamper-effect.mjs <effect.json> <out.json>
import fs from 'node:fs';
import { encodeEvent, leafHash, parseEffectJson } from './verify-effect.mjs';

const [input, output] = process.argv.slice(2);
const doc = parseEffectJson(fs.readFileSync(input, 'utf8'));
const step = doc.events.find((e) => e.kind === 'STEP');
if (!step) throw new Error('no step receipt to change');
step.digest = step.digest.replace(/^./, (c) => (c === '0' ? '1' : '0'));
for (const ev of doc.events) ev.leaf = leafHash(encodeEvent(doc.id, ev)).toString('hex');
fs.writeFileSync(output, JSON.stringify(doc));
