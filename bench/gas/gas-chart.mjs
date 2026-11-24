// SVG chart of gas per SendMessage against prior messages, before and after, on one axis,
// with each series' least-squares line. Arobi look: ink surface, the Hue stripe band, spectrum series colours
// (pink, then the spectrum orange stepped to the dark-mode lightness band; validated with the dataviz checks),
// mono labels. Identity is never colour alone: direct labels, a legend and different marker shapes.
// Usage: node gas-chart.mjs <before.json> <after.json> <out.svg> [title]
import fs from 'node:fs';

const [beforePath, afterPath, out, title = 'Whisper SendMessage gas as history grows', unit = 'message', call = 'SendMessage'] = process.argv.slice(2);
// unit: what one step of history is ('message', 'anchor'); call: the measured function, for the axis and subtitle.
const load = (p) => JSON.parse(fs.readFileSync(p, 'utf8')).gas.map((g, i) => ({ x: i, y: g })).filter((p) => Number.isFinite(p.y));
const series = [
  { key: 'before', label: 'before: slices', color: '#ff2d95', shape: 'circle', pts: load(beforePath) },
  { key: 'after', label: 'after: AVL trees', color: '#e86428', shape: 'square', pts: load(afterPath) },
];
const fit = (pts) => {
  const n = pts.length, sx = pts.reduce((s, p) => s + p.x, 0), sy = pts.reduce((s, p) => s + p.y, 0);
  const sxx = pts.reduce((s, p) => s + p.x * p.x, 0), sxy = pts.reduce((s, p) => s + p.x * p.y, 0);
  const b = (n * sxy - sx * sy) / (n * sxx - sx * sx), a = (sy - b * sx) / n;
  const ssr = pts.reduce((s, p) => s + (p.y - (a + b * p.x)) ** 2, 0), mean = sy / n;
  const sst = pts.reduce((s, p) => s + (p.y - mean) ** 2, 0);
  return { a, b, r2: sst > 0 ? 1 - ssr / sst : 1 };
};
// Each series gets the better of two models, by R²: linear (y = a + b·x) or logarithmic (y = a + b·log2(x + 1)).
// The legend says which, so a logarithmic curve is never presented as flat or as linear.
for (const s of series) {
  const lin = fit(s.pts);
  const lg = fit(s.pts.map((p) => ({ x: Math.log2(p.x + 1), y: p.y })));
  s.fit = lg.r2 > lin.r2 ? { ...lg, log: true } : { ...lin, log: false };
  s.at = (x) => s.fit.a + s.fit.b * (s.fit.log ? Math.log2(x + 1) : x);
}
const usedLabelY = [];

const W = 960, H = 560, L = 96, R = 250, T = 92, B = 64;
const PW = W - L - R, PH = H - T - B;
const xMax = Math.max(...series.flatMap((s) => s.pts.map((p) => p.x)));
const yMaxRaw = Math.max(...series.flatMap((s) => s.pts.map((p) => p.y)));
const yStep = [1e6, 2e6, 5e6, 1e7, 2e7, 5e7, 1e8, 2e8, 5e8].find((st) => yMaxRaw / st <= 8);
const yMax = Math.ceil(yMaxRaw / yStep) * yStep;
const X = (x) => L + (x / xMax) * PW, Y = (y) => T + PH - (y / yMax) * PH;
const M = (y) => `${(y / 1e6).toFixed(y >= 1e8 ? 0 : 1)}M`;
const font = 'ui-monospace, \'JetBrains Mono\', Consolas, monospace';
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
let svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-labelledby="t d">\n`;
svg += `<title id="t">${esc(title)}</title><desc id="d">Gas used by one ${call} transaction against the number of ${unit}s already in the realm, before (slices) and after (AVL trees), with least-squares lines.</desc>\n`;
svg += `<rect width="${W}" height="${H}" fill="#0e0e16"/>\n`;
['#ff2d95', '#ffe34d', '#2de2ff', '#5cff7a'].forEach((c, i) => { svg += `<rect x="${(W / 4) * i}" y="0" width="${W / 4}" height="6" fill="${c}"/>\n`; });
svg += `<text x="${L}" y="42" fill="#f4f4fb" font-family="${font}" font-size="20" font-weight="700">${esc(title)}</text>\n`;
svg += `<text x="${L}" y="66" fill="#b9b9d3" font-family="${font}" font-size="13">gno v1.8.0 in-memory gno.land node · one transaction per ${unit} · GAS USED as the node reports it</text>\n`;
svg += `<rect x="${L}" y="${T}" width="${PW}" height="${PH}" fill="#15151f"/>\n`;
for (let y = 0; y <= yMax; y += yStep) {
  svg += `<line x1="${L}" x2="${L + PW}" y1="${Y(y)}" y2="${Y(y)}" stroke="#2f2f46" stroke-width="1"/>`;
  svg += `<text x="${L - 10}" y="${Y(y) + 4}" fill="#b9b9d3" font-family="${font}" font-size="12" text-anchor="end">${M(y)}</text>\n`;
}
const xTicks = xMax >= 500 ? 200 : xMax >= 100 ? 20 : 2;
for (let x = 0; x <= xMax; x += xTicks) {
  svg += `<text x="${X(x)}" y="${T + PH + 22}" fill="#b9b9d3" font-family="${font}" font-size="12" text-anchor="middle">${x}</text>\n`;
}
svg += `<text x="${L + PW / 2}" y="${H - 16}" fill="#b9b9d3" font-family="${font}" font-size="13" text-anchor="middle">${unit}s already in the realm</text>\n`;
svg += `<text x="22" y="${T + PH / 2}" fill="#b9b9d3" font-family="${font}" font-size="13" text-anchor="middle" transform="rotate(-90 22 ${T + PH / 2})">gas per ${call}</text>\n`;
for (const s of series) {
  const d = s.pts.map((p, i) => `${i ? 'L' : 'M'}${X(p.x).toFixed(1)},${Y(p.y).toFixed(1)}`).join('');
  svg += `<path d="${d}" fill="none" stroke="${s.color}" stroke-width="2" stroke-linejoin="round"/>\n`;
  const x0 = s.pts[0].x, x1 = s.pts[s.pts.length - 1].x;
  const fd = Array.from({ length: 101 }, (_, i) => x0 + ((x1 - x0) * i) / 100)
    .map((x, i) => `${i ? 'L' : 'M'}${X(x).toFixed(1)},${Y(s.at(x)).toFixed(1)}`).join('');
  svg += `<path d="${fd}" fill="none" stroke="${s.color}" stroke-width="1.5" stroke-dasharray="6 5" opacity="0.75"/>\n`;
  for (const at of [1, 100, 1000]) {
    const p = s.pts.find((q) => q.x === at);
    if (!p) continue;
    const cx = X(p.x), cy = Y(p.y);
    const mark = s.shape === 'circle'
      ? `<circle cx="${cx}" cy="${cy}" r="5" fill="${s.color}" stroke="#0e0e16" stroke-width="2"/>`
      : `<rect x="${cx - 5}" y="${cy - 5}" width="10" height="10" rx="2" fill="${s.color}" stroke="#0e0e16" stroke-width="2"/>`;
    svg += `<g>${mark}<title>${esc(s.label)}: ${p.y.toLocaleString('en-US')} gas after ${p.x} prior messages</title></g>\n`;
  }
  const last = s.pts[s.pts.length - 1];
  const slope = Math.round(s.fit.log ? s.at(last.x) - s.at(last.x - 1) : s.fit.b);
  let ly = Math.min(Math.max(Y(last.y), T + 14), T + PH - 24);
  // Keep the two end labels (two lines each, about 34px) from overlapping.
  for (const u of usedLabelY) if (Math.abs(ly - u) < 38) ly = u + (ly >= u ? 38 : -38);
  usedLabelY.push(ly);
  svg += `<text x="${X(last.x) + 12}" y="${ly}" fill="#f4f4fb" font-family="${font}" font-size="13" font-weight="700">${esc(s.label)}</text>\n`;
  svg += `<text x="${X(last.x) + 12}" y="${ly + 17}" fill="#b9b9d3" font-family="${font}" font-size="12">${slope >= 0 ? '+' : ''}${slope.toLocaleString('en-US')} gas per ${unit}${s.fit.log ? ' here' : ''}</text>\n`;
}
// Legend (always present for two series), with the same shapes as the markers.
// Top left: the "before" line starts low and climbs right, and "after" stays low, so this corner stays clear.
let legendY = T + 46;
svg += `<text x="${L + 16}" y="${T + 22}" fill="#b9b9d3" font-family="${font}" font-size="12">dashed: least-squares line</text>\n`;
for (const s of series) {
  const mark = s.shape === 'circle' ? `<circle cx="${L + 22}" cy="${legendY - 4}" r="5" fill="${s.color}"/>` : `<rect x="${L + 17}" y="${legendY - 9}" width="10" height="10" rx="2" fill="${s.color}"/>`;
  const term = s.fit.log ? `${M(s.fit.b)}·log2(x+1)` : `${Math.round(s.fit.b).toLocaleString('en-US')}·x`;
  svg += `${mark}<text x="${L + 36}" y="${legendY}" fill="#f4f4fb" font-family="${font}" font-size="12">${esc(s.label)}  y = ${M(s.fit.a)} + ${term}  (R² ${s.fit.r2.toFixed(3)})</text>\n`;
  legendY += 22;
}
svg += '</svg>\n';
fs.writeFileSync(out, svg);
for (const s of series) console.log(`${s.key}: ${s.pts.length} points, ${s.fit.log ? 'log' : 'linear'} fit y = ${Math.round(s.fit.a)} + ${s.fit.b.toFixed(1)}·${s.fit.log ? 'log2(x+1)' : 'x'}, R² ${s.fit.r2.toFixed(4)}`);
