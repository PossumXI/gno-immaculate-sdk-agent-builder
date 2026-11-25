// Runs the effect lifecycle's acceptance tests (gno.land/r/arobi/effects/testdata/accept_*.txtar) in gno's own
// integration harness, on an in-memory gno.land node. Each scenario gets the loadpkg lines and this repository's
// packages (non-test files) and offline verifier appended, is copied into <gno>/gno.land/pkg/integration/testdata as
// sdk_effects_<name>.txtar, and runs as TestTestdata/sdk_effects_<name>. The copies are removed afterwards.
//
//   node scripts/run-effects-txtars.mjs <gno checkout> [integration test binary]
//
// With no binary it runs `go test` in the harness package. On Windows the harness of gno v1.8.0 needs
// gnolang/gno#6522 (its account query path); Linux needs nothing.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [gno, binary] = process.argv.slice(2);
if (!gno) throw new Error('usage: run-effects-txtars.mjs <gno checkout> [integration test binary]');
const harness = path.join(gno, 'gno.land', 'pkg', 'integration');
if (!fs.existsSync(path.join(harness, 'testscript_gnoland.go'))) throw new Error(`no gno integration harness under ${gno}`);

const packages = [
  ['gno.land/p/arobi/signals', 'gno.land/p/arobi/signals', 'signals'],
  ['gno.land/p/arobi/assurance', 'gno.land/p/arobi/assurance', 'passurance'],
  ['gno.land/r/arobi/assurance', 'gno.land/r/arobi/assurance', 'rassurance'],
  ['gno.land/r/arobi/effects', 'gno.land/r/arobi/effects', 'reffects'],
];
const verifierFiles = ['verify-effect.mjs', 'verify-evidence.mjs', 'tamper-effect.mjs'];

const section = (name, raw) => {
  const text = raw.replace(/\r\n/g, '\n'); // a Windows checkout may hold CRLF; the archive is LF throughout
  if (/^-- .* --$/m.test(text)) throw new Error(`${name} has a line that txtar would read as a file header`);
  return `-- ${name} --\n${text.endsWith('\n') ? text : `${text}\n`}`;
};
let archive = '';
for (const [, dir, as] of packages) {
  const src = path.join(repo, dir);
  for (const f of fs.readdirSync(src).sort()) {
    if (f === 'gnomod.toml' || (f.endsWith('.gno') && !f.endsWith('_test.gno'))) archive += section(`${as}/${f}`, fs.readFileSync(path.join(src, f), 'utf8'));
  }
}
for (const f of verifierFiles) archive += section(`verifier/${f}`, fs.readFileSync(path.join(repo, 'verifier', f), 'utf8'));
const loads = ['loadpkg gno.land/p/nt/avl/v0', ...packages.map(([p, , as]) => `loadpkg ${p} $WORK/${as}`)].join('\n');

const dataDir = path.join(repo, 'gno.land', 'r', 'arobi', 'effects', 'testdata');
const scenarios = fs.readdirSync(dataDir).filter((f) => /^accept_.*\.txtar$/.test(f)).sort();
const written = [];
try {
  for (const f of scenarios) {
    const name = `sdk_effects_${f.replace(/\.txtar$/, '')}`;
    const body = fs.readFileSync(path.join(dataDir, f), 'utf8').replace(/\r\n/g, '\n');
    const out = path.join(harness, 'testdata', `${name}.txtar`);
    fs.writeFileSync(out, `${loads}\n\n${body}\n${archive}`);
    written.push(out);
  }
  const run = '^TestTestdata$/^sdk_effects_';
  const r = binary
    ? spawnSync(binary, ['-test.run', run, '-test.v', '-test.timeout', '30m'], { cwd: harness, stdio: 'inherit', env: { ...process.env, GNOROOT: gno } })
    : spawnSync('go', ['test', '-run', run, '-v', '-timeout', '30m', '.'], { cwd: harness, stdio: 'inherit', env: { ...process.env, GNOROOT: gno } });
  process.exitCode = r.status ?? 1;
} finally {
  for (const f of written) fs.rmSync(f, { force: true });
}
