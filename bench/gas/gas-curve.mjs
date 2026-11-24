// reads a gno.land testscript log and prints GAS USED for each "# send i" transaction, with the
// gas at given history sizes and the growth between them. Usage: node gas-curve.mjs <log> [out.json]
import fs from 'node:fs';

const [log, outJson] = process.argv.slice(2);
const lines = fs.readFileSync(log, 'utf8').split(/\r?\n/u);
const gas = [];
let current = null;
for (const line of lines) {
  const m = line.match(/# send (\d+)/u);
  if (m) { current = Number(m[1]); continue; }
  const g = line.match(/GAS USED:\s+(\d+)/u);
  if (g && current !== null) { gas[current] = Number(g[1]); current = null; }
}
const sends = gas.length - 1;
const at = (i) => gas[i] ?? null;
const points = [1, 2, 11, 101, 501, 1001].filter((i) => i <= sends);
console.log(`sends with a reading: ${gas.filter((v) => v !== undefined).length} of ${sends}`);
for (const i of points) console.log(`send ${String(i).padStart(4)} (prior ${String(i - 1).padStart(4)}): ${at(i)}`);
if (at(2) && at(sends)) {
  console.log(`growth from send 2 to send ${sends}: ${at(sends) - at(2)} gas (${(((at(sends) / at(2)) - 1) * 100).toFixed(1)}%)`);
  const tail = gas.slice(Math.max(2, sends - 99)).filter(Boolean);
  const slope = tail.length > 1 ? (tail[tail.length - 1] - tail[0]) / (tail.length - 1) : 0;
  console.log(`gas per extra prior message over the last ${tail.length} sends: ${slope.toFixed(1)}`);
}
if (outJson) fs.writeFileSync(outJson, JSON.stringify({ sends, gas: gas.slice(1) }, null, 0));
