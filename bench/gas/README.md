# Gas per AnchorCheckpoint as anchor history grows

![AnchorCheckpoint gas before and after](sdk-anchor-gas.svg)

The realm used to keep its anchors in a slice of `AnchorRecord` values, and the evidence accumulator kept every leaf in a slice of `[32]byte`. A slice's backing array is one stored object, loaded and saved again in full on every append. Every anchor therefore paid for the realm's whole history.

The anchors are now an AVL tree plus a counter, and the accumulator keeps its leaves in an AVL tree keyed by index. An append writes O(log n) small nodes. Root, leaf and proof results are unchanged: the cross-language golden vectors still pass.

## Results

These are real transactions in an in-memory gno.land node: gno v1.8.0 (`fc79041`), one transaction per anchor, `GAS USED` as the node reports it. Five Pro agents anchor in turn, because an agent's anchors must be at least a block apart. The realm's anchor tree and accumulator grow with every anchor.

| Anchors already in the realm | Before (slices) | After (AVL trees) |
|---:|---:|---:|
| 0 | 15,524,975 | 16,812,512 |
| 1 | 16,651,818 | 17,740,657 |
| 10 | 21,465,945 | 22,233,920 |
| 100 | 67,250,900 | 25,646,149 |
| 500 | 270,350,444 | 28,260,852 |
| 1,000 | 523,930,400 | 29,209,290 |

- **Before** is linear: `y = 16,786,528 + 507,370.3·x`, R² 1.000. Residual RMSE is 368,001 gas and the largest residual 1,382,831.
- **After** is logarithmic, not constant: `y = 18,359,919 + 1,158,159.0·log2(x+1)`, R² 0.942. Residual RMSE is 409,148 gas and the largest residual 1,777,421.
- From 12 prior anchors on, the trees cost less. Below that they cost up to 2.4M gas more (at 5 prior anchors).
- At 1,000 anchors an anchor costs 17.9× less. From 100 to 1,000 anchors the old cost grew 7.8× and the new one 1.14×.

The raw per-anchor gas is in `results/sdk-anchor-gas-{before,after}.json`: entry `i` is anchor `i+1`, which saw `i` prior anchors.

## Reproduce

1. Get the harness.
   ```sh
   git clone --depth 1 --branch v1.8.0 https://github.com/gnolang/gno
   ```
   gno v1.8.0's testscript harness needs two changes to its own test code for this run. Neither touches gas accounting; gno's `compute_map_key_restore_gas.txtar`, which pins an exact `GAS USED`, still passes after them.
   - `gno.land/pkg/integration/testscript_gnoland.go`: `nodeMaxLifespan` is 120 s. 1,001 anchors take about 3-5 minutes, so raise it (we used 2 h).
   - On Windows only, `loadUserEnv` builds the ABCI path with `filepath.Join`, which gives `auth\accounts\<addr>`, and the node answers "unknown request". Use `path + "/" + addr` (as the same file's other query does).
2. Build: `cd gno/gno.land/pkg/integration && go test -c -o integration.test .`
3. Generate the script from this repository at the commit you want to measure:
   ```sh
   node bench/gas/gen-sdk-txtar.mjs <this repo> 1001 after <gno>/gno.land/pkg/integration/testdata/sdk_anchor_gas.txtar
   ```
4. Run. The script ends on a deliberate non-match, so testscript prints every anchor's `GAS USED`:
   ```sh
   GNOROOT=<gno> ./integration.test -test.run 'TestTestdata/sdk_anchor_gas$' -test.v > run.log
   ```
5. Read the curve and draw the chart:
   ```sh
   node bench/gas/gas-curve.mjs run.log after.json
   node bench/gas/gas-chart.mjs before.json after.json chart.svg "SDK AnchorCheckpoint gas as anchor history grows" anchor AnchorCheckpoint
   ```

The scripts measured here:

| File | sha256 |
|---|---|
| `sdk_anchor_gas.txtar`, before | `0d1d5487744a818b937e60cb0fa24323effcd66d7206c2a9f53f6021972bc640` |
| `sdk_anchor_gas.txtar`, after | `70a38d0a4ff9e118455089598f8d03f35920f966ad0bbf5b0bf06610661e53f1` |
