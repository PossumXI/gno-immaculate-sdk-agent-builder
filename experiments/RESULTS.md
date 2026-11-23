# Scientific Evaluation Results — Immaculate SDK Agent Builder

**Protocol:** [PROTOCOL.md](PROTOCOL.md) | **Seed:** `20261123` | **Generated:** `2026-11-23T04:57:30.422Z`

---

## Summary of Pre-Registered Verdicts

| Hypothesis | Criterion | Verdict |
| --- | --- | --- |
| **H1a** Fixed-Point Fidelity | MAE < 1e-4 vs float64 across 500 streams/batches | **PASS** |
| **H1b** Order Invariance & Gno↔JS Parity | 0 permutation diffs & 0 Gno↔JS digest mismatches | **PASS** |
| **H2a** Spike Robustness | HampelCusum Spike-FPR <= 50% of RawCUSUM on +10σ spikes | **PASS** |
| **H2b** Stealth Drift Detection | >= 90% TPR on sub-cap +2σ drift (vs 0% static cap) | **PASS** |
| **H2c** Memory Poisoning Defense | >= 95% block TPR & <= 2% clean coherence FPR | **PASS** |
| **H2d** Escalation & Proof Integrity | 100% replay/overspend/delegation block & 100% RFC 6962 verify | **PASS** |
| **H3** Real GnoVM Gas Scaling | Logarithmic RFC 6962 proofs (<= 8 hashes @ N=250) on Gno v1.8.0 | **PASS** |
| **H4a** Memory Quarantine Firewall | >= 95% poison quarantine & >= 90% Top-3 contamination reduction | **PASS** |
| **H4b** Overlap-Weighted Hybrid RRF | Clean Top-1 exact-target recall beats dense by >= 50 pts with 0% poison (vs 100% lexical poison) | **PASS** |
| **H4c** Real GnoVM Familiar Gas | 8-record MemoryVault ingest + RRF recall + Familiar action < 15M gas | **PASS** |
| **H5a** Cross-Ref: 3rd-Order Jerk (`n=3`) | Tested honestly vs HampelCusum on spikes & runaway drift | **KILLED_JERK_KEPT_HAMPEL_CUSUM** |
| **H5b** Cross-Ref: Geometric Median (`L1`) | >= +0.05 ROC-AUC over Mean Centroid & RJD tension @ 35% poison | **PASS** |

---

## Experiment E1 — Fixed-Point (`Scale = 1,000,000`) vs IEEE-754 Float64 Fidelity

| Primitive | MAE vs Float64 | Max Abs Error | Evaluated Samples |
| --- | ---: | ---: | ---: |
| `robustSmooth` | `0.000003486` | `0.000006565` | 20000 |
| `cusum` | `0.000001913` | `0.00001297` | 20000 |
| `pageHinkley` | `0.000007238` | `0.0001065` | 20000 |
| `meanResultantLength` | `0.000002821` | `0.00000435` | 500 |
| `meanPairwiseCosine` | `0.000002392` | `0.000004462` | 500 |

- **Vector Permutation Invariance (100 batches × 2 measures):** `0` mismatches.
- **Live Gno v1.8.0 ↔ Node.js RFC 6962 Parity:** `5/5` exact matches (`GOLDEN_ROOT = 0063b52374e4586986e90d50fd5b6cdd3615a94b63d98cd639fa1ee771555443`).

---

## Experiment E2 — 500-Episode Adversarial Agent Assurance Benchmark

Calibrated on 400 quiet 60-step episodes (target 5% FPR): EMA threshold `125.393`, Raw CUSUM `h = 2.656336`, Hampel-Guarded CUSUM `h = 3.002874`, Spherical Coherence `R >= 0.72`.

| Architecture | S1 Clean FPR | S2 +10σ Spike FPR | S3 Stealth +2σ Drift TPR | S3 Median Delay | S4 Memory Poison Block TPR | S5 Escalation Block | S5 Offline Proof Verified |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **Unprotected** | 0% | 0% | 0% | N/A steps | 0% | 0% | 0% |
| **StaticCapOnly** | 0% | 0% | 0% | N/A steps | 0% | 33% | 0% |
| **NaiveEMA** | 4% | 91% | 100% | 7 steps | 0% | 33% | 0% |
| **RawCUSUM** | 5% | 100% | 100% | 2 steps | 0% | 33% | 0% |
| **ImmaculateFull** | 8% | 4% | 100% | 3 steps | 100% | 100% | 100% |

*(ImmaculateFull S1 clean spherical coherence false-rejection rate: `0%`.)*

---

## Experiment E3 — Real Gno v1.8.0 VM Gas & Scaling Measurements

Measured directly via `gno test -v` on Gno v1.8.0:

- **Single Governed Action (`Agent.Execute` + Warrant + Receipt + Closure + RFC 6962 Proofs):** `2,659,102` gas
- **Single Adaptive Action (`HampelCusum DriftGuard` + 8D `CoherenceGuard` + `Agent.Execute` + Proofs):** `4,971,378` gas
- **Familiar + 8-Record Governed MemoryVault Ingest + Hybrid RRF Top-3 Recall + Capability Action:** `14,418,924` gas

| Accumulator Leaves (N) | Max RFC 6962 Proof Hashes | Cumulative Append + Proof + Verify Gas | Avg Gas / Leaf |
| ---: | ---: | ---: | ---: |
| 10 | 4 | 1,462,219 | 146,222 |
| 50 | 6 | 6,105,853 | 122,117 |
| 100 | 7 | 12,022,205 | 120,222 |
| 250 | 8 | 32,636,865 | 130,547 |

---

## Experiment E4 — 500-Episode Governed Memory Poisoning & Hybrid RRF Benchmark

| Architecture | Top-1 Exact-Target Recall | Top-3 Exact-Target Recall | Top-3 Poison Contamination | Poison Quarantine TPR |
| --- | ---: | ---: | ---: | ---: |
| **UnprotectedDenseRAG** | 7.6% | 21.4% | 0% | 0% |
| **LexicalOnly** | 100% | 100% | 100% | 0% |
| **DenseWithQuarantine** | 7.6% | 21.4% | 0% | 100% |
| **ImmaculateMemoryVault** | 100% | 100% | 0% | 100% |

---

## Experiment E5 — Independent Cross-Reference: 3rd-Order Jerk (`n=3`) & Pairwise Unit-Difference Fields vs Geometric Median & Hampel-CUSUM

Cross-referenced external discrete non-local dynamics concepts (Johannes Geisen / `@frintroper`, `Relational-Jerk-Dynamics` / `ToneProjekt`; clean-room MIT evaluation, zero `RIPL v1.0` code copied):

### E5a — Telemetry Drift & Accelerating Runaway (200 Episodes Each — Jerk Rejected)

| Detector | Clean FPR | +10σ Spike FPR | Accelerating Runaway TPR | +2σ Step-Drift TPR | Decision |
| --- | ---: | ---: | ---: | ---: | --- |
| Raw 3rd-Order Jerk (`Δ³x`) | 5% | 100% | 2.5% | 3% | **REJECTED** (20× noise variance amplification) |
| Hampel+EMA Jerk | 6% | 9% | 34% | 6% | **REJECTED** (low drift recall) |
| **Immaculate `HampelCusum`** | **2.5%** | **5%** | **99%** | **99%** | **RETAINED** |

### E5b — 35% Coordinated Poison Memory Batch Audit (300 Trials in R^12 — Geometric Median Adopted)

| Estimator | Poison Separation ROC-AUC | Decision |
| --- | ---: | --- |
| Raw Pairwise Unit-Difference Tension (`||J_i||`) | `0.7477` | Cross-referenced inspiration |
| Arithmetic Mean Centroid Cosine | `0.864` | Baseline (0% breakdown point) |
| **Fixed-Point Weiszfeld L1 Geometric Median (`GeometricMedianFixed`)** | **`0.9299`** | **ADOPTED** into `gno.land/p/arobi/signals` (+6.8 pts AUC; 50% breakdown point) |
