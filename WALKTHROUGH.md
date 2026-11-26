# Technical Walkthrough & Independent Reproduction Guide

This guide documents how Gno.land developers, judges, and external evaluators can reproduce every test, deterministic signal benchmark, flat-gas storage curve, and partial-effect proof in **`immaculate-sdk-agent-builder`**, along with the exact live status on the **Gno.land Onyx (`onyx-1`)** testnet and clear scope boundaries.

---

## 1. One-Command Reproduction (Linux, macOS, Windows Git-Bash, or Docker)

No API keys, cloud accounts, or external model endpoints are required:

```bash
# Option A — Host reproduction (clones & builds Gno v1.8.0 if GNO_BIN is unset)
bash scripts/reproduce.sh

# Option B — Hermetic Linux container reproduction
docker build -t immaculate-verify .
docker run --rm immaculate-verify
```

### What `reproduce.sh` Runs & Checks
1. **Zero-dependency Node.js verifiers, harness adapters, & stdio MCP server (`19/19` tests):**
   - `node --test verifier/verify-evidence.test.mjs verifier/verify-effect.test.mjs adapters/adapters.test.mjs mcp/immaculate-mcp-server.test.mjs`
   - Includes replay of a real scrubbed `gnosh.ai` `stream-json` capture (`adapters/fixtures/gnosh-live-stream.ndjson`), RFC 6962 inclusion + `SUBPROOF` consistency verification, tampered-effect rejection, and clean stdio MCP shutdown (`exit 0`).
2. **Gno v1.8.0 Lint, Unit Tests, & Effect-Lifecycle Acceptance Txtars:**
   - `bash scripts/run-gno-tests.sh` (`gno lint` = 0 diagnostics across all packages/realms; unit tests across `p/arobi/signals`, `p/arobi/assurance`, `r/arobi/assurance`, `r/arobi/effects`, and `examples/`).
   - `node scripts/run-effects-txtars.mjs` (runs the 6 end-to-end `testdata/*.txtar` partial-effect scenarios on `gno`, verifying computed closes, single-use `IRREVERSIBLE` human holds, retry idempotence, and read-back compensation).
3. **Pre-Registered Deterministic Benchmarks (`E1–E14`, `27/27` verdicts):**
   - `node experiments/run_experiments.mjs && node experiments/check-verdicts.mjs`
   - Confirms bit-exact cross-language RFC 6962 `GOLDEN_ROOT = 0063b52374e4586986e90d50fd5b6cdd3615a94b63d98cd639fa1ee771555443`.
4. **AVL Flat-Gas Anchor Curve (`17.8×` gas reduction at `1,000` anchors):**
   - `node bench/gas/gas-curve.mjs` (re-derives the `523.9M → 29.5M` gas improvement from replacing flat slices with Gno AVL trees and running counters).

Both **Ubuntu (`gno-tests`)** and **Windows (`gno-tests-windows`)** GitHub Actions jobs run this exact pipeline on every push and pull request (`.github/workflows/verify.yml`).

---

## 2. Live Gno.land Onyx (`onyx-1`) Deployment Status

Onyx (`onyx-1`) places newly uploaded packages/realms that depend on cross-package imports or realm state into its `inert` approval queue (`vm/qinertpaths`) until an Onyx network approver executes `gnokey maketx enablepkg`.

You can inspect live `onyx-1` block height, active package files, and `vm/qinertpaths` status at any time with:

```bash
node scripts/check-onyx-status.mjs --offline-self-test
node scripts/check-onyx-status.mjs --namespace <deployer-g1-address>
```

### Verified On-Chain State (checked `2026-11-26 19:03 UTC`, Onyx block `1,433,003`)
- **`gno.land/p/<namespace>/signals` — `ACTIVE` on `onyx-1`:** Live and queryable right now via `gnokey query vm/qfile -data gno.land/p/<namespace>/signals -remote https://rpc.onyx.testnets.gno.land:443` (`coherence.gno`, `drift.gno`, `filters.gno`, `gnomod.toml`, `math.gno`).
- **`gno.land/p/<namespace>/assurance` & `gno.land/r/<namespace>/assurance` — `SUBMITTED_INERT` on `onyx-1`:** Confirmed on-chain in `vm/qinertpaths`, awaiting Onyx approver `enablepkg` activation.
- **Versioned `/v2` Upgrade (`scripts/deploy-onyx.sh`):** Because Gno package paths are immutable once submitted, `scripts/deploy-onyx.sh` stages and deploys the latest flat-gas AVL storage (`#11`) and checked-not-asserted `r/arobi/effects` realm (`#16`) cleanly under `/v2` paths (`p/<ns>/signals/v2`, `p/<ns>/assurance/v2`, `r/<ns>/assurance/v2`, `r/<ns>/effects/v2`).

---

## 3. Scope, Attribution, & Product Boundaries

To keep evaluation crisp for Gno developers, judges, and auditors:

1. **First-Party Benchmark Attribution:** The public dataset and interactive viewer at `huggingface.co/datasets/TruLumecreator/immaculate-agent-gno-benchmarks` and `huggingface.co/spaces/TruLumecreator/immaculate-agent-gno-benchmarks` are published by Arobi's founder (`TruLumecreator`) so anyone can inspect raw outputs and re-run scorers; they are first-party reproducible artifacts, not an independent third-party audit.
2. **Software Agent SDK vs. Robot Assurance Passport:** `immaculate-sdk-agent-builder` is an open-source (MIT) **software-agent governance and cryptographic evidence SDK in Gno** (for DeFi agents, coding harnesses like `gnosh.ai` and `Ullumii`, and multi-agent workflows). It is distinct from Arobi's **Robot Assurance Passport** (an R&D hardware/robotics release-evidence system under separate development) — they share RFC 6962 cryptographic principles, but this repository makes zero claims of physical robotics qualification or safety certification.
3. **3-Month & 6-Month Gnome Tavern Roadmap:**
   - **Month 1–3:** Complete `onyx-1` `/v2` `enablepkg` activation (`assurance/v2` + `effects/v2`), publish standalone Gno package imports for external Gno DeFi/DAO realms, and expand live cross-harness `gnosh.ai` ↔ `Ullumii` ↔ `arobi-whisper` multi-agent sessions.
   - **Month 3–6:** Ship Gno.land mainnet realms upon mainnet launch, add multi-approver threshold governance for `IRREVERSIBLE` effects in `r/arobi/effects`, and onboard external Gno builder integrations.
