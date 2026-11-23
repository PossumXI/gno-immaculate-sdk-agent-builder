# Immaculate Agent SDK Builder (`gno-immaculate-sdk-agent-builder`)

**Deterministic, consensus-safe autonomous agent SDK & fluent builder in Gno — implementing the Arobi Assurance Architecture with out-of-the-box RFC 6962 cryptographic evidence, fixed-point behavioral drift circuit breakers, spherical memory-poisoning gates, and attenuated multi-agent delegation anchored directly on Gno.land.**

Built by [Arobi Technology Alliance, Inc.](https://aura-genesis.org).

---

## What Makes This Different

Most agent frameworks log mutable text after an action has already fired — and standard blockchain contracts rely only on static spend caps that miss stealth prompt-injection drift, break under oracle/telemetry spikes, and offer zero defense against cross-session memory poisoning.

**Immaculate Agent SDK Builder** moves the entire assurance spine into **consensus-safe pure Gno (zero floating-point operations)**:

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
6. **On-Chain Registry, Anti-Equivocation Anchor, GNOT Service Plans & Live Demo (`gno.land/r/arobi/assurance`):** Owner-bound `AgentPassport`s, strict `prevRoot`-chained `AnchorCheckpoint`s, on-chain `VerifyCheckpointProof`, live `RunAdaptiveDemoAction`, live `RunFamiliarDemoMemory` / `RunFamiliarDemoAction`, `gnoweb` explorer (`/`, `/agent/<id>`, `/checkpoint/<id>`, `/demo`, `/familiar`, `/benchmarks`), and built-in **GNOT service billing** (`AnchorFeeUgnot` per checkpoint, 30-day Pro Agent Plan via `SubscribeAgent` in GNOT for 1-block high-frequency anchoring, with private deployer-administered settlement routing that never exposes payout addresses on-chain).

---

## Measured Scientific Evaluation (Pre-Registered Experiments E1–E5)

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

---

## Live Gno.land Onyx Testnet (`onyx-1`) Submission Proof

Submitted on-chain to `onyx-1` (`https://rpc.onyx.testnets.gno.land:443`; currently parked in Onyx's `code_submission_policy = "inert"` approver activation queue — verifiable via `gnokey query vm/qinertpaths`):

| Package / Realm Path | Block Height | Transaction Hash |
| --- | ---: | --- |
| `gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/signals` | `1343642` | `QLBPtPOpBUapHouk+hNHIWjkWarDH383MZhhbmlOOtA=` |
| `gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/assurance` | `1343646` | `+k7hjislNZ1B2uC0bnk6MihvsoqaeczUtp8OwVDdkK8=` |
| `gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/assurance` | `1343648` | `DzU5Dt7AyZbFb8Glx79GbJ+ZWXs3s+G4n4906FoDqsc=` |

---

## Repository Layout

| Path | Description |
| --- | --- |
| `gno.land/p/arobi/signals` | Pure integer (`Scale = 1,000,000`) deterministic signal assurance primitives: `RobustSmoother` (Hampel+EMA), `CausalMedian`, `CusumDetector`, `PageHinkleyDetector`, `HampelCusumDetector`, `MeanResultantLengthFixed`, `MeanPairwiseCosineFixed`, `CoherenceGate`, `SignalEvidence`. |
| `gno.land/p/arobi/assurance` | Core Agent SDK & fluent `NewAgentBuilder`: fail-closed policies (`AllowList`, `BudgetCap`, `RiskGate`, `DriftGuard`, `CoherenceGuard`, `Composite`), single-use `EffectWarrant`, `DelegatedWarrant` attenuation, `HarnessFrame` (`gnosh.ai`, `ullumii`, `whisper-bus`, `gno-realm`), `DecisionReceipt`, `EffectClosure`, RFC 6962 `Accumulator`, `EvidenceBundle.Verify()`, measured `AssuranceMetrics`. |
| `gno.land/r/arobi/assurance` | Stateful Gno.land realm: `AgentPassport` registry, anti-equivocation `AnchorCheckpoint`, GNOT anchor fees & 30-day Pro Agent `SubscribeAgent` plan with private opaque operator settlement, on-chain `VerifyCheckpointProof`, interactive `RunDemoAction` / `RunAdaptiveDemoAction`, and `gnoweb` UI. |
| `adapters/` | Zero-dependency Node.js adapters for **`gnosh.ai`** (`gnosh-adapter.mjs`, NDJSON frame ingestion → RFC 6962 proofs + anchor txs) and **`Ullumii`** (`ullumii-adapter.mjs`, governed session bridge + Whisper Agent Bus handoff). |
| `examples/` | Runnable, GnoVM-tested end-to-end examples: DeFi Treasury Rebalancer (`BuildDeFiTreasuryAgent`) and Multi-Agent Attenuated Delegation (`BuildCoordinatorAndWorker`). |
| `verifier/` | Zero-dependency standalone Node.js RFC 6962 offline evidence verifier (`verify-evidence.mjs`). |
| `experiments/` | Pre-registered scientific protocol (`PROTOCOL.md`), reproducible benchmark runner (`run_experiments.mjs`), and empirical results (`RESULTS.md`, `results.json`). |

---

## Quick Start — Fluent Immaculate Agent Builder in Gno

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

# 2. Standalone zero-dependency offline verifier + Ullumii & gnosh.ai adapter tests (Node.js >= 20)
node --test verifier/verify-evidence.test.mjs adapters/adapters.test.mjs

# 3. Full pre-registered scientific evaluation (Experiments E1, E2, E3)
node experiments/run_experiments.mjs
```

---

## Using with `gnosh.ai` and `Ullumii`

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

> **Settlement Privacy:** No operator or payout wallet address is ever hardcoded in source code, rendered in `gnoweb`, or emitted in `chain.Emit` events. After deployment, the deployer initializes operator governance privately via `InitOperator`, configures an opaque settlement sink via `SetSettlementSink`, and settles accumulated service fees via `CollectServiceFees`.

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
