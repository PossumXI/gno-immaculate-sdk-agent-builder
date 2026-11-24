# Immaculate SDK Agent Builder

*(Repository: `PossumXI/immaculate-sdk-agent-builder` · Build Name: **Immaculate SDK Agent Builder**)*

**Deterministic, consensus-safe autonomous agent SDK and fluent builder, built on Gno.land — implementing the Arobi Assurance Architecture with out-of-the-box RFC 6962 cryptographic evidence, fixed-point behavioral drift circuit breakers, spherical memory-poisoning gates, and attenuated multi-agent delegation.**

Built by [Arobi Technology Alliance, Inc.](https://aura-genesis.org).

- **1080p Demo Video (2m 45s):** [Watch / Download MP4](https://github.com/PossumXI/immaculate-sdk-agent-builder/releases/download/v1.0.0-gnome-tavern/Immaculate_Agent_SDK_Builder_Demo_1080p.mp4)
- **Live Browser Playground (100/100/100 PageSpeed):** [possumxi.github.io/immaculate-sdk-agent-builder/web/](https://possumxi.github.io/immaculate-sdk-agent-builder/web/)
- **Public Benchmarks on Hugging Face Hub:** [Dataset (JSONL)](https://huggingface.co/datasets/TruLumecreator/immaculate-agent-gno-benchmarks) · [Interactive Space](https://huggingface.co/spaces/TruLumecreator/immaculate-agent-gno-benchmarks)

---

## Run it locally in 5 minutes

Same flow as the [Gno quick start](https://docs.gno.land/builders/quickstart). `gno mod init` on current master writes `gnomod.toml` (`module` plus `gno = "0.9"`). The empty `gnowork.toml` at the repo root lets `gno test ./...` and `gnodev .` resolve the local packages and the realm together.

```bash
# 1. Install the toolchain (gno, gnokey, gnodev).
curl -fsSL https://raw.githubusercontent.com/gnolang/gno/master/misc/install.sh | sh
export PATH="$PATH:$HOME/.gno/bin"
# Current master instead of the latest release:
# curl -fsSL https://raw.githubusercontent.com/gnolang/gno/master/misc/install.sh | sh -s -- --from-source

# 2. Clone and test every package and realm
git clone https://github.com/PossumXI/immaculate-sdk-agent-builder.git
cd immaculate-sdk-agent-builder
gno test ./...

# 3. Local chain with hot reload
gnodev .
# open http://localhost:8888/r/arobi/assurance

# 4. Key for a testnet deploy. gnokey prints a mnemonic; store it offline.
gnokey add dev
gnokey list
```

---

### Reproduce everything in one command

`scripts/reproduce.sh` runs all three CI stages — Node module tests, `gno lint` +
unit tests, and the pre-registered E1–E14 experiments — then prints a summary and
exits non-zero on any failure. It finds a built `gno` via `GNO_BIN`, `GNO_SRC`
or `PATH`, and otherwise clones and builds Gno `v1.8.0` itself.

```bash
bash scripts/reproduce.sh
```

Or in a container, with no local toolchain at all:

```bash
docker build -t immaculate-verify . && docker run --rm immaculate-verify
```

---

## What Makes This Different

Most agent frameworks log mutable text after an action has already fired — and standard blockchain contracts rely only on static spend caps that miss stealth prompt-injection drift, break under oracle/telemetry spikes, and offer zero defense against cross-session memory poisoning.

**Immaculate SDK Agent Builder** moves the entire assurance spine on-chain, in consensus-safe fixed-point code (zero floating-point operations):

1. **Evidence by Default (`gno.land/p/arobi/assurance`):** Every action passes through `PolicyInputProjection -> Fail-Closed PolicyEngine -> Single-Use EffectWarrant -> ToolHandler -> EffectClosure -> RFC 6962 / RFC 9162 Merkle Accumulator`, returning a self-verifying `EvidenceBundle` whose digests verify **bit-for-bit identically** in Gno and off-chain JavaScript.
2. **Deterministic Fixed-Point Statistical Assurance (`gno.land/p/arobi/signals`):** Pure integer (`Scale = 1,000,000`) implementations of Arobi's scientifically measured signal primitives:
   - **Causal `Hampel(w=5, k=3) -> EMA(α=0.2)` (`RobustSmoother`)**: Rejects transient $\pm 10\sigma$ telemetry/oracle spikes causally.
   - **`HampelCusum` & `Page-Hinkley` Behavioral Drift Circuit Breakers (`DriftGuardPolicy`)**: Eliminates 96% of transient spike false alarms while catching stealth sub-cap $+2\sigma$ behavioral drift in a median of **3 steps**, automatically latching the circuit breaker until principal reset.
   - **Order-Invariant $O(n \cdot d)$ Spherical Coherence Gate (`CoherenceGuardPolicy`) & Fixed-Point L1 Geometric Median (`GeometricMedianFixed`)**: Computes deterministic `MeanResultantLength`, `MeanPairwiseCosine`, and 50%-breakdown-point Weiszfeld L1 Geometric Median over quantized embeddings to block and purge coordinated cross-session memory poisoning.
3. **Immaculate Familiars, Poison-Resistant Governed Memory & Object-Capabilities (`memory.gno`, `familiar.gno`):**
   - **`MemoryVault`**: Pure fixed-point episodic/semantic memory store featuring an **ingestion-time spherical quarantine firewall**, **Overlap-Weighted Fixed-Point Hybrid Reciprocal Rank Fusion (`RRF`, $k=60$)** fusing dense cosine + exact lexical terms (`100%` Top-1 clean recall with `0%` poison contamination in E4!), `AuditAndPurgeWithGeometricMedian()`, and cryptographic `MemoryRecallProof` digests folded into every action's `ContextDigest`.
   - **`Familiar` & `CapabilityToken`**: Persistent owner-bonded autonomous companions governed by strictly attenuable bitmask object-capabilities (`CapReadMemory`, `CapWriteMemory`, `CapInvokeTool`, `CapDelegate`, `CapSendWhisper`, `CapManageEscrow`), sliding-window rate pacing, and a pure-integer **95% Wilson Score Trust Lower Bound (`WilsonLowerBoundFixed`)** that auto-suspends misbehaving agents.
4. **Attenuated Multi-Agent Delegation (`DelegatedWarrant`):** A coordinator agent can delegate strictly attenuated child warrants to specialist workers (`maxSpend <= parent`, `expiry <= parent`, exact action/target scope) with cryptographic parent-to-child provenance chaining.
5. **Native `Ullumii`, `gnosh.ai`, and Sovereign Local GPU LLM Interoperability (`harness.gno` + `adapters/`):** Govern and wrap live turns from **`gnosh.ai`** (`adapters/gnosh-adapter.mjs`), **`Ullumii`** (`adapters/ullumii-adapter.mjs`), and **any local `llama-server` / Ollama / OpenAI-compatible GPU backend** (`adapters/local-llm-adapter.mjs`, verified live against `Inkling-2-Mini-Uncensored` on local CUDA!) directly into RFC 6962 `EvidenceBundle`s and on-chain `AnchorCheckpoint` calls.
6. **On-Chain Registry, Anti-Equivocation Anchor, GNOT Service Plans & Live Demo (`gno.land/r/arobi/assurance`):** Owner-bound `AgentPassport`s, strict `prevRoot`-chained `AnchorCheckpoint`s, on-chain `VerifyCheckpointProof`, live `RunAdaptiveDemoAction`, live `RunFamiliarDemoMemory` / `RunFamiliarDemoAction`, `gnoweb` explorer (`/`, `/agent/<id>`, `/checkpoint/<id>`, `/demo`, `/familiar`, `/obligations`, `/benchmarks`), and built-in **GNOT service billing** (`AnchorFeeUgnot` per checkpoint, 30-day Pro Agent Plan via `SubscribeAgent` in GNOT for 1-block high-frequency anchoring). The deploying account becomes `operator` atomically inside `init()` (zero post-deploy front-running window); `Render` and events do not print operator/settlement addresses, while on a public chain realm state and bank transfers remain publicly inspectable.
7. **Partly-Run Actions Lifecycle — Detect, Own, Reverse (`effect_lifecycle.gno`, `r/arobi/assurance/effects.gno`, `verifier/verify-evidence.mjs`, local `mcp/immaculate-mcp-server.mjs`):**
   - **State machine:** `AUTHORIZED -> STARTED -> (step receipts) -> COMMITTED | ABORTED | PARTIAL`, with deadline-driven `IN_DOUBT` and linked `COMPENSATED` / human `ACCEPTED` resolution, sealed in an RFC 6962 hash chain (`arobi-assurance-effect-event-v1`, bit-exact Gno ↔ Node.js parity).
   - **On-chain Gno package & realm (`p/arobi/assurance`, `r/arobi/assurance`):** `EffectSpecBuilder` fails closed if deadline, cleanup owner, postcondition, or reversal class (`REVERSIBLE` / `COMPENSABLE` / `IRREVERSIBLE`) is missing, and denies `IRREVERSIBLE` without prior human approval. Realm exposes `BeginEffect`, `RecordStep`, `CloseEffect` (checks downstream read-back; exit-0 with no state change closes `ABORTED`, never `COMMITTED`), `Compensate` (seals linked superseding reversal effect with restored read-back), `AcceptPartial`, permissionless `MarkInDoubt` (callable by anyone once `runtime.ChainHeight() >= deadlineHeight`), and `Render("obligations")`.
   - **Local MCP stdio server (`mcp/immaculate-mcp-server.mjs`, local in-process engine):** Exposes `arobi_begin_effect`, `arobi_record_step`, `arobi_close_effect`, `arobi_list_open_effects`, and `arobi_compensate`, running an automatic overdue clock sweep on every MCP call, fencing open effect keys, deduplicating retries by `idempotencyKey`, and verifying complete lifecycle chains offline via `verifyEffectLifecycleChain()`.

---

## Measured Scientific Evaluation (Pre-Registered Experiments E1–E14)

All pre-registered evaluations in [experiments/PROTOCOL.md](experiments/PROTOCOL.md) ran on seed `20261123` (full report in [experiments/RESULTS.md](experiments/RESULTS.md)):

### Adversarial Agent Benchmark (E2: 500 Held-Out Monte Carlo Episodes, 5 Architectures)

| Architecture | S1 Clean FPR | S2 +10σ Spike FPR | S3 Stealth +2σ Drift TPR | S3 Median Delay | S4 Memory Poison Block | S5 Escalation Block | S5 RFC 6962 Proof |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Unprotected | 0% | 0% | 0% | N/A | 0% | 0% | 0% |
| StaticCapOnly | 0% | 0% | 0% | N/A | 0% | 33% | 0% |
| NaiveEMA | 4% | 91% | 100% | 7 steps | 0% | 33% | 0% |
| RawCUSUM | 5% | 100% | 100% | 2 steps | 0% | 33% | 0% |
| **ImmaculateFull** | **8%** | **4%** *(25× lower)* | **100%** | **3 steps** | **100%** *(0% clean FPR)* | **100%** | **100%** |

- **Fixed-Point Consensus Fidelity (E1):** MAE `1.9e-6 .. 7.2e-6` vs IEEE-754 `float64` across 500 streams/batches, `0` vector-permutation mismatches, and **`5/5` bit-exact Gno v1.8.0 ↔ Node.js RFC 6962 parity**.
- **Real Gno v1.8.0 VM Gas (E3):** `2,659,102` gas per governed action (`4,971,378` gas adaptive; `14,418,924` gas Familiar + 8-record `MemoryVault` ingest + Hybrid RRF Top-3 recall + capability check), and strictly logarithmic proofs (`<= 8` hashes at `250` leaves).
- **Governed Familiar MemoryVault & Poison Firewall (E4, 500 episodes):** Overlap-Weighted Fixed-Point Hybrid RRF (`k=60`) + Spherical Quarantine hits **`100%` Top-1 exact-target recall** with **`0%` Top-3 poison contamination** and **`100%` poison quarantine** (vs `7.6%` Top-1 for dense-only and `100%` Top-3 poison contamination for lexical-only).
- **Independent Cross-Reference of External Dynamics (E5):** Following strict scientific method (zero external non-MIT code copied), we tested discrete 3rd-order jerk ($\Delta^3 x_t$) and pairwise unit-difference fields ($\sum_j (a_j - a_i)/\|a_j - a_i\|$, cross-referencing Johannes Geisen / `@frintroper`, `Relational-Jerk-Dynamics`):
  - **Rejected:** Raw 3rd-order jerk (`n=3`) amplified noise $20\times$ (`100%` spike FPR, `2.5%` runaway TPR vs `HampelCusum`'s `99%` TPR & `5%` spike FPR) and was **KILLED**.
  - **Adopted:** Recognizing $\sum_j (u_j - m)/\|u_j - m\| = 0$ as the optimality condition of the **L1 Geometric Median** (Weiszfeld 1937; Vardi & Zhang 2000; 50% breakdown point), our clean-room fixed-point **`GeometricMedianFixed`** achieved **`0.9299` ROC-AUC** under 35% coordinated memory poisoning vs `0.8640` arithmetic centroid (`+6.59` pts AUC) and was adopted into `gno.land/p/arobi/signals`.
- **Extended Scientific Leaps (E6–E12, Cross-Referencing `@frintroper`, Wildberger 2005 & Arobi Labs — zero non-MIT code copied):**
  - **E6 (`@frintroper/horse_fallacy` — `k=1 → k=2` Cold-Start Gap):** Uncovered that `MinTrustedAnchors = 2` let step-2 poison cause `36.03%` downstream clean rejections. Variance-calibrated pairwise cold-start ($\tau_{\text{pair}} = \tau^2 = 0.3025$) cuts downstream rejects `30×` (`97%` block, `0.33%` clean FPR), and owner-pinned `GenesisAnchor` hits **`100%` block / `0%` clean FPR** — adopted in `MemoryVault`, `BuildFamiliar`, and `immaculate-mcp-server.mjs`.
  - **E7 (`@frintroper/Symmetry-No-Symmetry` — Exact $180^\circ$ Symmetry Stasis):** Exposed a `50/100` permutation bug in arithmetic-mean fallback when $\sum u_i = 0$. Upgrading `GeometricMedianFixed` to **Discrete L1 Medoid initialization** (SHA-256 tie-break) yields **`0/100` divergences**, and **`AntipodalSplitGate`** (wired into `CoherenceGuardPolicy.EnableAntipodalSplitGuard`) detects **`100%` of balanced $180^\circ$ split-brain batches at `0%` clean FPR**.
  - **E8 (`@frintroper/Astrometric-Filter-Opacity` — Filter Opacity under Period-6 Attacks):** Proved raw $\Delta^2/\Delta^3$ fail (`100%` spike FPR, `3.7–5%` drift TPR), while period $P = 6 > w = 5$ bursts dropped single-channel `HampelCusum` to `72.3%` TPR. Adopted **`OpacityAwareHampelCusumDetector`** (`AgentBuilder.WithOpacityAwareDriftGuard`): jumps period-6 TPR **`72.3% → 100%`** with **`+0.0%`** clean or single-spike FPR regression!
  - **E9 (Arobi Labs Anisotropy — Common-Average-Reference & Dispersion-Gated RRF):** Under real-world anisotropic cone collapse (`w = 0.78`), raw `MemoryVault` quarantined only `23.5%` of poison (`87.7%` Top-3 contamination). Adopted fixed-point **`CommonAverageReferenceDebiasFixed`** + Dispersion-Gated RRF: **`23.5% → 100.0%` poison quarantine**, **`87.7% → 0.0%` Top-3 contamination**, and **`99.7%` Top-1 recall**!
  - **E10 (`@frintroper/wildberger-math` / N. J. Wildberger 2005 — Rational Quadrance & Spread Without `ISqrt64`):** Replaced square-root cosine threshold checks with Cauchy-Schwarz overflow-safe **Signed Quadrance Alignment** (`SignedQuadranceCosSqFixed`, `RationalSpreadFixed`, `RationalCosGateFixed`): **`100%` float64 threshold decision equivalence** across 4,000 checks (`maxSpreadAbsError = 2.38e-6`) with **zero `ISqrt64` calls** and **`48.72%` real GnoVM gas reduction** (`41,781,999 → 21,425,899` gas per 100 pairs).
  - **E11 (Arobi Labs `arobi-primitives` — Causal $\text{AR}(1)$ Innovation Prewhitening & On-Chain Youden-$J$ Calibration):** Under positive lag-1 autocorrelation ($\rho = 0.70$), white-noise `HampelCusum` suffered `42.0%` clean false alarms (`42.3%` spike FPR); **`AR1PrewhitenedHampelCusumDetector`** (`WithAR1DriftGuard`) cuts clean $\text{AR}(1)$ FPR **`7.4×`** down to **`5.7%`** (`5.3%` spike FPR) while keeping **`98.3%`** $+2.5\sigma$ drift TPR. On-chain **`CalibrateThresholdYoudenFixed`** matches `float64` Youden's $J$ (`1.11e-16` max error) and Mann-Whitney ROC-AUC (`0` error).
  - **E12 (RFC 6962 / RFC 9162 §2.1.4.2 Logarithmic Merkle Consistency Proofs — `SUBPROOF`):** Added `Accumulator.ConsistencyProof` / `VerifyConsistency` in Gno and `consistencyProof` / `verifyConsistencyProof` in `verifier/verify-evidence.mjs` + MCP tool `verify_consistency_proof`: verified **`2,080/2,080` (`100%`)** prefix pairs ($1 \le N_1 \le N_2 \le 64$) and $N_1=103 \to N_2=250$ in `9` hashes with **`100%` tamper rejection**.
  - **E13 (Hubness Z-Score Calibration & Steady-State Scalar Random-Walk Kalman Filter — Pure Fixed-Point Gno, Cross-Ref Radovanović et al. JMLR 2010 / Kalman 1960 / Wu et al. NeurIPS 2002 / Arobi Labs P3 & P6):**
    - **E13a (`FitHubStatsFixed` / `HubNormalizeScoreFixed` wired into `MemoryVault.SetHubnessCalibration`):** Under adversarial universal-hub memory injection (300 episodes in $\mathbb{R}^{16}$), rescues Top-1 exact-target recall **`0% → 100%`** (`100% → 0%` hub hijack) while maintaining **`100%`** clean no-hub recall.
    - **E13b (`KalmanRWGainFixed` / `KalmanRWTracker`):** One-shot integer algebraic Riccati solution (`maxGainAbsError = 1.77e-6`, `maxStateAbsError = 1.67e-5` across 48,000 updates over $q/r \in \{0.01, 0.10, 1.00\}$) cuts multi-regime RMSE **`-42.4%`** vs raw observations (`0.9965 → 0.5741`, matching IEEE-754 `float64` `0.5741` and outperforming mismatched fixed-$\alpha$ EWMAs `1.4526` / `0.6699`).
  - **E14 (Canonical Cross-Chain Checkpoint & Strictly-Ordered Execution Receipt Commitments):** Added `CanonicalCheckpoint`, `ExecutionReceipt`, `BuildOrderedReceiptTree`, and `ErrNonCanonicalOrder` in `gno.land/p/arobi/assurance/checkpoint.gno`, exact Node.js parity in `verifier/verify-evidence.mjs`, and the **11th MCP tool `verify_cross_chain_checkpoint`**: **`3/3`** bit-exact live Gno v1.8.0 ↔ Node.js golden hash parity, **`100/100`** ordered batches verified, and **`500/500` (`100%`)** adversarial reorder/duplicate/mixed-chain/tamper mutations rejected.

### Live Public System Benchmarks ([experiments/LIVE_BENCHMARKS.md](experiments/LIVE_BENCHMARKS.md))

Measured against **real running systems** (reproducible via `node experiments/run_live_benchmarks.mjs`):

| Live System / Subsystem | Real Measurement |
| --- | --- |
| **Gno.land Onyx Testnet (`onyx-1`) RPC** | `/status` p50 `54.6 ms` (`abci_query` `43.6 ms`) at block `1344098`; `3` pkgs + `2` realms verified on-chain |
| **Stdio MCP Server (`mcp/immaculate-mcp-server.mjs`)** | `governed_execute` p50 `1.284 ms`, `familiar_quarantine` `0.220 ms`, `familiar_recall` `0.232 ms`, `verify_evidence` `0.357 ms` |
| **Whisper Agent Bus Crypto (X25519 + ChaCha20-Poly1305)** | **1,209 ops/s** (256 B), **1,221 ops/s** (4 KiB), **1,104 ops/s** (16 KiB) — `100%` verified |
| **Sovereign Local GPU (`Inkling-2-Mini-Uncensored`, MX150 CUDA + CPU MoE)** | Allowed turns `5.22–5.63` prompt / `2.14–2.18` gen tok/s; **fail-closed budget & action refusals complete in `0.76–2.28 ms` (`0.97 ms` median across 5/5 adversarial probes, `100%` GPU saved)**; `100%` RFC 6962 proofs PASS |
| **Public Third-Party Platforms** | **Hugging Face Hub:** [Dataset](https://huggingface.co/datasets/TruLumecreator/immaculate-agent-gno-benchmarks) & [Live Space](https://huggingface.co/spaces/TruLumecreator/immaculate-agent-gno-benchmarks) · **Google PageSpeed Insights:** [**100 Perf / 100 BP / 100 SEO** (LCP `0.2s`, TBT `0ms`, CLS `0`)](https://pagespeed.web.dev/analysis/https-possumxi-github-io-immaculate-sdk-agent-builder-web/s7l82mro32?form_factor=desktop) · **Live Playground:** [possumxi.github.io/immaculate-sdk-agent-builder/web/](https://possumxi.github.io/immaculate-sdk-agent-builder/web/) |

---

## Live Gno.land Onyx Testnet (`onyx-1`) Submission Proof

Submitted on-chain to `onyx-1` (`https://rpc.onyx.testnets.gno.land:443`; currently parked in Onyx's `code_submission_policy = "inert"` approver activation queue — verifiable via `gnokey query vm/qinertpaths`).

The live Onyx package and realm paths used a deployer-address namespace (`gno.land/p/<namespace>/...` and `gno.land/r/<namespace>/...`). Those on-chain paths, transaction hashes, and deploy block heights are omitted from this public README because they identify the deployer account. To review and run the code, use the in-repo paths `gno.land/p/arobi/signals`, `gno.land/p/arobi/assurance`, and `gno.land/r/arobi/assurance`. After `enablepkg`, the public `gnoweb` URL will be `https://onyx.testnets.gno.land/r/<namespace>/assurance`.

---

## Repository Layout

| Path | Description |
| --- | --- |
| `gno.land/p/arobi/signals` | Pure integer (`Scale = 1,000,000`) deterministic signal assurance primitives: `RobustSmoother` (Hampel+EMA), `CausalMedian`, `CusumDetector`, `PageHinkleyDetector`, `HampelCusumDetector`, `OpacityAwareHampelCusumDetector`, `AR1PrewhitenedHampelCusumDetector`, `KalmanRWGainFixed` / `KalmanRWTracker`, `MeanResultantLengthFixed`, `MeanPairwiseCosineFixed`, `GeometricMedianFixed` (L1 50%-breakdown w/ Medoid init), `CommonAverageReferenceDebiasFixed`, `FitHubStatsFixed` / `HubNormalizeScoreFixed`, Wildberger `RationalCosGateFixed` / `RationalSpreadFixed`, `CalibrateThresholdYoudenFixed`, `CoherenceGate`, `SignalEvidence`. |
| `gno.land/p/arobi/assurance` | Core Agent & Familiar SDK (`NewAgentBuilder`, `BuildFamiliar`): fail-closed policies (`AllowList`, `BudgetCap`, `RiskGate`, `DriftGuard`, `CoherenceGuard`, `Composite`), `MemoryVault` (Spherical Quarantine + CAR + Hubness Z-Score + Overlap-Weighted Hybrid RRF `k=60`), `Familiar` + `CapabilityToken` + `WilsonLowerBoundFixed`, single-use `EffectWarrant`, `DelegatedWarrant`, `HarnessFrame`, `CanonicalCheckpoint` & `BuildOrderedReceiptTree`, RFC 6962 `Accumulator` (inclusion + `SUBPROOF` consistency). |
| `gno.land/r/arobi/assurance` | Stateful Gno.land realm: atomic `init()` deployer-operator binding, `AgentPassport` registry, anti-equivocation `AnchorCheckpoint`, GNOT anchor fees & 30-day Pro Agent `SubscribeAgent` plan (enforcing `cur.Previous().IsUserCall()`), `RunDemoAction` / `RunAdaptiveDemoAction` / `RunFamiliarDemoMemory` / `RunFamiliarDemoAction`, and `gnoweb` UI. |
| `mcp/` | Zero-dependency **Model Context Protocol (MCP) JSON-RPC 2.0 stdio server** (`immaculate-mcp-server.mjs`) exposing 11 governed tools (`governed_execute`, `familiar_remember`, `familiar_recall`, `verify_evidence_bundle`, `build_anchor_tx`, `export_whisper_handoff`, `estimate_context_budget`, `inspect_skill_preflight`, `gnosh_peers_plan`, `verify_consistency_proof`, `verify_cross_chain_checkpoint`) + `--print-gnosh-mcp` one-liner for Claude, Antigravity, `Ullumii`, `gnosh.ai`, and `gnomcp` clients. |
| `adapters/` | Zero-dependency Node.js adapters for **`gnosh.ai`** (`gnosh-adapter.mjs` — native `stream-json` `init`/`tool_use`/`tool_result`/`compact_boundary`/`permission_denials` ingestion, pre-send context budgeting, monotone skill preflight, and `gnomem/v2` `.Parallel()` peers plan generator), **`Ullumii`** (`ullumii-adapter.mjs`), and **Sovereign Local GPU LLMs** (`local-llm-adapter.mjs`, live-tested on `Inkling-2-Mini-Uncensored`). |
| `web/index.html` | Interactive browser RFC 6962 verifier, Familiar MemoryVault poison-quarantine simulator, Adena tx builder, and live `onyx-1` RPC explorer. |
| `examples/` | Runnable, GnoVM-tested end-to-end examples: DeFi Treasury Rebalancer (`BuildDeFiTreasuryAgent`) and Multi-Agent Attenuated Delegation (`BuildCoordinatorAndWorker`). |
| `verifier/` | Zero-dependency standalone Node.js RFC 6962 offline evidence verifier (`verify-evidence.mjs`). |
| `experiments/` | Pre-registered scientific protocol (`PROTOCOL.md`), reproducible E1–E5 benchmark runner (`run_experiments.mjs` → `RESULTS.md`), and **Live Public Benchmarks** (`run_live_benchmarks.mjs` → `LIVE_BENCHMARKS.md`). |
| `CONTRIBUTORS.md` / `HACKATHON_SUBMISSION.md` | Team roles, GitHub task assignments (`@iShowLinux`, `@JonDevOps`, `@canderson777`), and compliant Gnome Tavern submission guide. |

---

## Quick Start — Fluent builder

```go
package myagent

import (
    "gno.land/p/arobi/assurance"
    "gno.land/p/arobi/signals"
)

func BuildDeFiAgent(owner string) (*assurance.Agent, *assurance.DriftGuardPolicy, *assurance.CoherenceGuardPolicy, error) {
    base := signals.Baseline{MeanFixed: 100 * signals.Scale, SDFixed: 15 * signals.Scale}
    b := assurance.NewAgentBuilder("defi-treasury-rebalancer").
        WithChain("gnoland-testnet", "gno.land/r/arobi/assurance").
        WithPrincipal(owner).
        AllowActions("rebalance").
        AllowTargets("pool:gnot-usdc").
        WithBudgetCap(5000).
        WithRiskGate(false, true).
        WithDriftGuard(base, 5*signals.Scale, signals.Scale, 5, false, true).
        WithCoherenceGuard(750000, false, false, true).
        WithTool(assurance.ToolSpec{
            Name:           "rebalance",
            RiskTier:       assurance.RiskLow,
            MaxBudgetUgnot: 5000,
        }, func(w assurance.EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
            return []byte("rebalanced"), []byte("pool-proof"), w.MaxSpendUgnot, nil
        })
    ag, err := b.Build()
    return ag, b.DriftGuard(), b.CoherenceGuard(), err
}
```

---

## Reproducing All Tests & Scientific Experiments

```bash
# 1. Real Gno v1.8.0 lint & unit tests across signals, assurance, realm, and examples
bash scripts/run-gno-tests.sh

# 2. Standalone zero-dependency offline verifier, Ullumii / gnosh.ai / Local-LLM adapters & stdio MCP server tests (Node.js >= 20)
node --test verifier/verify-evidence.test.mjs adapters/adapters.test.mjs mcp/immaculate-mcp-server.test.mjs

# 3. Full pre-registered scientific evaluation (Experiments E1–E5) & Live Public Benchmarks
node experiments/run_experiments.mjs
node experiments/run_live_benchmarks.mjs
```

---

## Using with `gnosh.ai` and `Ullumii`

Connect Immaculate Agent SDK directly into `gnosh.ai` as a native stdio MCP server (9 tools including pre-send context budgeting, monotone skill preflight, and `gnomem/v2` `.Parallel()` peer plan generation):

```bash
node mcp/immaculate-mcp-server.mjs --print-gnosh-mcp
```

Or consume real `gnosh -p --output-format stream-json --verbose` output programmatically:

```js
import { GnoshAssuranceSession } from './adapters/gnosh-adapter.mjs';
import { UllumiiAssuranceBridge } from './adapters/ullumii-adapter.mjs';

// 1. Govern a gnosh.ai (`gnosh -p --output-format stream-json`) NDJSON stream and build an AnchorCheckpoint tx
const gnosh = new GnoshAssuranceSession({
  agentId: 'gnosh-ops-agent',
  principal: 'g1youraddress...',
  caller: 'g1youraddress...',
  sessionId: 'gnosh-session-1',
});
gnosh.ingestNdjsonStream(JSON.stringify({
  type: 'tool_result',
  frame_id: 'frame-1',
  tool: 'rebalance',
  target: 'pool:gnot-usdc',
  budget_ugnot: 1000,
  spent_ugnot: 1000,
  output: 'ok',
}));
const anchorTx = gnosh.buildAnchorCheckpointTx(1000);

// 2. Wrap an Ullumii governed MCP action and export a Whisper cross-harness handoff packet
const ullumii = new UllumiiAssuranceBridge({
  agentId: 'ullumii-coordinator',
  workspaceId: 'ws-alpha',
  principal: 'g1youraddress...',
  caller: 'g1youraddress...',
});
const bundle = ullumii.recordUllumiiAction({
  handoffId: 'handoff-1',
  mcpServer: 'immaculate-mcp',
  toolName: 'delegate_task',
  budgetUgnot: 500,
  spentUgnot: 500,
});
const handoffPacket = ullumii.exportWhisperHandoff({
  toHarness: 'gnosh.ai',
  toAgentId: 'gnosh-ops-agent',
  taskPayload: { action: 'rebalance', target: 'pool:gnot-usdc' },
});
```

---

## On-Chain Service Tiers & Private Settlement Security

| Plan / Operation | Default Fee (GNOT) | Capabilities |
| --- | --- | --- |
| Standard Checkpoint (`AnchorCheckpoint`) | `0.001 GNOT` (`1,000 ugnot`) + network gas | Anti-equivocation RFC 6962 root anchor, on-chain proof verification, `gnoweb` explorer |
| Pro Agent Plan (`SubscribeAgent`, 30 days) | `10 GNOT` / 30 days + network gas | High-frequency 1-block anchor cadence (`ProMinAnchorInterval = 1`) for continuous `Ullumii` & `gnosh.ai` fleets |

> **Operator & Settlement:** No operator or payout wallet address is hardcoded in source code, rendered in `gnoweb`, or emitted in `chain.Emit` events. During deployment, the deploying account becomes `operator` atomically inside `init()` (no post-deploy claim race), may configure a settlement sink via `SetSettlementSink`, and may withdraw accrued service fees via `CollectServiceFees`. Note that on a public chain, realm state and bank transfers remain publicly inspectable.

---

## Deploying to Gno.land Onyx Testnet (`onyx-1`)

```bash
gnokey maketx addpkg --pkgpath gno.land/p/<your-namespace>/signals --pkgdir ./gno.land/p/arobi/signals \
  -remote https://rpc.onyx.testnets.gno.land:443 -chainid onyx-1 \
  --gas-fee 1000000ugnot --gas-wanted 10000000 --broadcast <your-testnet-key>

gnokey maketx addpkg --pkgpath gno.land/p/<your-namespace>/assurance --pkgdir ./gno.land/p/arobi/assurance \
  -remote https://rpc.onyx.testnets.gno.land:443 -chainid onyx-1 \
  --gas-fee 1000000ugnot --gas-wanted 10000000 --broadcast <your-testnet-key>

gnokey maketx addpkg --pkgpath gno.land/r/<your-namespace>/assurance --pkgdir ./gno.land/r/arobi/assurance \
  -remote https://rpc.onyx.testnets.gno.land:443 -chainid onyx-1 \
  --gas-fee 1000000ugnot --gas-wanted 10000000 --broadcast <your-testnet-key>
```

---

## License

MIT — Copyright (c) 2026 Arobi Technology Alliance, Inc.
