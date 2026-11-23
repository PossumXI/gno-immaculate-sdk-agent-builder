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
   - **Order-Invariant $O(n \cdot d)$ Spherical Coherence Gate (`CoherenceGuardPolicy`)**: Computes deterministic `MeanResultantLength` & `MeanPairwiseCosine` over quantized context embeddings to block cross-session memory poisoning before any tool executes.
3. **Attenuated Multi-Agent Delegation (`DelegatedWarrant`):** A coordinator agent can delegate strictly attenuated child warrants to specialist workers (`maxSpend <= parent`, `expiry <= parent`, exact action/target scope) with cryptographic parent-to-child provenance chaining.
4. **On-Chain Registry, Anti-Equivocation Anchor & Live Demo (`gno.land/r/arobi/assurance`):** Owner-bound `AgentPassport`s, strict `prevRoot`-chained `AnchorCheckpoint`s, on-chain `VerifyCheckpointProof`, live `RunAdaptiveDemoAction`, and `gnoweb` explorer (`/`, `/agent/<id>`, `/checkpoint/<id>`, `/demo`, `/benchmarks`).

---

## Measured Scientific Evaluation (Pre-Registered Experiments E1–E3)

All 7 pre-registered hypotheses in [experiments/PROTOCOL.md](experiments/PROTOCOL.md) passed on seed `20261123` (full report in [experiments/RESULTS.md](experiments/RESULTS.md)):

### Adversarial Agent Benchmark (500 Held-Out Monte Carlo Episodes, 5 Architectures)

| Architecture | S1 Clean FPR | S2 +10σ Spike FPR | S3 Stealth +2σ Drift TPR | S3 Median Delay | S4 Memory Poison Block | S5 Escalation Block | S5 RFC 6962 Proof |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Unprotected | 0% | 0% | 0% | N/A | 0% | 0% | 0% |
| StaticCapOnly | 0% | 0% | 0% | N/A | 0% | 33% | 0% |
| NaiveEMA | 4% | 91% | 100% | 7 steps | 0% | 33% | 0% |
| RawCUSUM | 5% | 100% | 100% | 2 steps | 0% | 33% | 0% |
| **ImmaculateFull** | **8%** | **4%** *(25× lower)* | **100%** | **3 steps** | **100%** *(0% clean FPR)* | **100%** | **100%** |

- **Fixed-Point Consensus Fidelity (E1):** MAE `1.9e-6 .. 7.2e-6` vs IEEE-754 `float64` across 500 streams/batches, `0` vector-permutation mismatches, and **`5/5` bit-exact Gno v1.8.0 ↔ Node.js RFC 6962 parity**.
- **Real Gno v1.8.0 VM Gas (E3):** `2,659,078` gas for a full governed action with RFC 6962 proofs (`4,971,344` gas including `HampelCusum` + 8D `CoherenceGuard`), and strictly logarithmic proofs (`<= 8` hashes at `250` leaves, `~120k–130k` gas/leaf).

---

## Repository Layout

| Path | Description |
| --- | --- |
| `gno.land/p/arobi/signals` | Pure integer (`Scale = 1,000,000`) deterministic signal assurance primitives: `RobustSmoother` (Hampel+EMA), `CausalMedian`, `CusumDetector`, `PageHinkleyDetector`, `HampelCusumDetector`, `MeanResultantLengthFixed`, `MeanPairwiseCosineFixed`, `CoherenceGate`, `SignalEvidence`. |
| `gno.land/p/arobi/assurance` | Core Agent SDK & fluent `NewAgentBuilder`: fail-closed policies (`AllowList`, `BudgetCap`, `RiskGate`, `DriftGuard`, `CoherenceGuard`, `Composite`), single-use `EffectWarrant`, `DelegatedWarrant` attenuation, `DecisionReceipt`, `EffectClosure`, RFC 6962 `Accumulator`, `EvidenceBundle.Verify()`, measured `AssuranceMetrics`. |
| `gno.land/r/arobi/assurance` | Stateful Gno.land realm: `AgentPassport` registry, anti-equivocation `AnchorCheckpoint`, on-chain `VerifyCheckpointProof`, interactive `RunDemoAction` / `RunAdaptiveDemoAction`, and `gnoweb` UI. |
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

# 2. Standalone zero-dependency offline verifier tests (Node.js >= 20)
node --test verifier/verify-evidence.test.mjs

# 3. Full pre-registered scientific evaluation (Experiments E1, E2, E3)
node experiments/run_experiments.mjs
```

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
