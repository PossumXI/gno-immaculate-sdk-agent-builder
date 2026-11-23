# Pre-Registered Scientific Evaluation Protocol (Immaculate Agent SDK in Gno)

**Registered:** 2026-11-23 (prior to executing `experiments/run_experiments.mjs` and publishing `RESULTS.md`)  
**Principle:** Following the Arobi Assurance scientific discipline, every algorithmic gate in this SDK must earn its place empirically against strong baselines under a pre-registered test with fixed seeds. Any hypothesis that fails its pre-registered criterion will be reported as **FAILED / KILLED** without cherry-picking.

---

## Experiment E1 — Fixed-Point Consensus Determinism & Numerical Fidelity

### Motivation
GnoVM smart contracts execute across heterogeneous validator hardware where IEEE-754 floating-point drift can threaten determinism. `gno.land/p/arobi/signals` implements all statistical primitives in pure integer fixed-point arithmetic (`Scale = 1,000,000`, `MADScale = 1,482,600`, exact Newton-Raphson `ISqrt64`).

### Hypotheses
- **H1a (Numerical Fidelity):** Across `N = 500` seeded streams/batches (`seed = 20261123`), our fixed-point `Scale = 1,000,000` implementations of:
  1. Causal `Hampel(w=5, k=3) -> EMA(alpha=0.2)` (`RobustSmoother`)
  2. One-sided `CUSUM(k=1.0)`
  3. `Page-Hinkley(delta=0.5)`
  4. `MeanResultantLength` (8 vectors in $\mathbb{R}^{16}$)
  5. `O(n*d)` `MeanPairwiseCosine` (8 vectors in $\mathbb{R}^{16}$)
  will achieve **mean absolute error `< 1e-4` (0.0001)** relative to IEEE-754 `float64` reference implementations.
- **H1b (Zero-Divergence Order Invariance & Cross-Language Parity):** Permuting input vector rows yields **0** fixed-point difference in both `MeanResultantLengthFixed` and `MeanPairwiseCosineFixed`, and canonical Gno (`gno.exe v1.8.0`) vs standalone JS (`verifier/verify-evidence.mjs`) RFC 6962 digests match **bit-for-bit (0 mismatches)**.
- **Null Hypothesis (H0_1):** Integer truncation accumulates error $\ge 10^{-4}$ MAE or fails order invariance / Gno↔JS parity.

---

## Experiment E2 — Adversarial Agent Assurance Benchmark (500 Monte Carlo Episodes)

### Experimental Design
We evaluate **5 agent governance architectures** across **5 scenarios** (`100` independent seeded episodes per scenario = `500` episodes total, `seed = 20261123`):

#### Architectures Compared
1. **`Unprotected`**: Direct tool execution with no policy gates.
2. **`StaticCapOnly`**: `AllowListPolicy` + static `BudgetCapPolicy(max=500 ugnot)`.
3. **`NaiveEMA`**: Static gates + raw EMA threshold alarm (`alpha=0.2`, calibrated to ~5% quiet FPR).
4. **`RawCUSUM`**: Static gates + standardized `CUSUM(k=1.0)` (calibrated to ~5% quiet FPR via quiet baseline).
5. **`ImmaculateFull`** *(Treatment)*: `AllowList + BudgetCap + RiskGate + HampelCusum(w=5, k=3.0) + SphericalCoherenceGate(R >= 0.72) + Single-Use Attenuated Warrants + RFC 6962 Evidence`.

#### Scenarios (each episode = 60 governed steps; quiet spend baseline $\mu = 100, \sigma = 15$ ugnot; static hard cap = 500 ugnot)
- **S1 — Clean Quiet Operations:** Stationary Gaussian spend ($\mu=100, \sigma=15$) + coherent single-session embeddings ($\mathbb{R}^{16}$). Measures **False Alarm Rate (FPR)** on clean traffic.
- **S2 — Clean Operations + 2% Transient $\pm 10\sigma$ Telemetry/Oracle Spikes:** Clean traffic punctuated by isolated single-step spikes (e.g., transient gas/oracle glitch, still under static cap or clipped). Measures **Spike False Alarm Rate (Spike-FPR)**.
- **S3 — Stealth Sub-Cap Behavioral Drift Attack ($+2\sigma$ shift):** Starting at step 20, a hijacked agent elevates spend from $100 \to 130$ ugnot ($+2\sigma$, well below the $500$ ugnot static cap!). Measures **Drift Detection Rate (TPR)** and **Median Detection Delay (steps)**.
- **S4 — Cross-Session Memory Poisoning Attack:** At step 20, an attacker injects off-topic / adversarial embeddings mixed into the retrieved context batch (4 distinct orthogonal/random session directions mixed with the active session). Measures **Poisoning Block Rate (TPR)** and **Zero-Side-Effect Containment**.
- **S5 — Warrant Replay / Overspend / Privilege Escalation Attack:** Compromised worker attempts to (a) replay a consumed warrant, (b) overspend its warrant ceiling, or (c) amplify a delegated child warrant. Measures **Escalation Block Rate (TPR)** and **RFC 6962 Proof Verification Rate**.

### Pre-Registered Success Criteria
- **H2a (Spike Robustness):** On S2, `ImmaculateFull` (`HampelCusum`) achieves **at least 50% lower Spike-FPR** than `RawCUSUM`.
- **H2b (Stealth Drift Detection):** On S3, `ImmaculateFull` detects **$\ge 90\%$** of sub-cap $+2\sigma$ stealth drift attacks (vs `0%` for `StaticCapOnly`), while quantifying honestly any median detection delay trade-off vs `RawCUSUM`.
- **H2c (Memory Poisoning Defense):** On S4, `ImmaculateFull` blocks **$\ge 95\%$** of mixed-session poisoning attacks while keeping S1 clean coherence false rejections **$\le 2\%$**.
- **H2d (Deterministic Containment & Proof Integrity):** On S5, `ImmaculateFull` achieves **100%** escalation/replay refusal with **100%** offline RFC 6962 evidence verification.

---

## Experiment E3 — Real Gno v1.8.0 Gas & Scaling Economics

### Method
Execute dedicated real `gno.exe test -v` benchmarks on `gno.land/p/arobi/signals`, `gno.land/p/arobi/assurance`, and `gno.land/r/arobi/assurance` measuring actual GnoVM gas consumption for:
- Single `Agent.Execute` (governed call + warrant + receipt + closure + RFC 6962 proofs)
- Single `DriftGuard` + `CoherenceGuard` evaluation
- `Accumulator` append + proof generation/verification across `N = 10, 50, 100, 250` leaves
- On-chain `AnchorCheckpoint` + `VerifyCheckpointProof`

### Pre-Registered Criterion
- **H3:** Proof size grows strictly logarithmically ($\le \lceil \log_2 N \rceil$ hashes, $\le 8$ hashes at $N=250$) and all single-action governed executions stay comfortably within standard Gno.land block/transaction gas budgets.

---

## Experiment E4 — Governed Memory Poisoning Firewall, Hybrid RRF Retrieval & Familiar Capabilities

### Motivation
Persistent autonomous agents ("Familiars") accumulate episodic and semantic memories across sessions. Standard append-all dense RAG stores are vulnerable to sleeper memory poisoning (adversarial records with hijacked keywords) and miss exact-ID/policy lookups when dense embeddings blur near-duplicate sessions. `gno.land/p/arobi/assurance` (`MemoryVault` + `Familiar`) introduces a pure-integer **ingestion-time spherical quarantine firewall** paired with **deterministic fixed-point Hybrid Reciprocal Rank Fusion (`RRF`, $k = 60$)** and **object-capability leases**.

### Experimental Design (`500` seeded episodes, `seed = 20261123`)
Each episode builds a 16-record Familiar memory store in $\mathbb{R}^{16}$ containing 12 clean on-manifold memories (one holding the target policy/ticket ID) plus 4 adversarial off-manifold poisoned memories (25% contamination) that deliberately stuff the target ticket/action keywords to hijack retrieval. We evaluate **4 retrieval architectures**:
1. **`UnprotectedDenseRAG`**: Append-all store, dense cosine retrieval.
2. **`LexicalOnly`**: Append-all store, exact token overlap only.
3. **`DenseWithQuarantine`**: Ingestion-time spherical centroid quarantine ($\cos \ge 0.55$), dense cosine retrieval only.
4. **`ImmaculateMemoryVault`** *(Treatment)*: Ingestion-time spherical centroid quarantine ($\cos \ge 0.55$) + deterministic fixed-point **Hybrid RRF ($k=60$)** fusing dense cosine and lexical overlap + cryptographic `MemoryRecallProof`.

### Pre-Registered Success Criteria
- **H4a (Poisoning Quarantine):** `ImmaculateMemoryVault` cuts Top-3 poison contamination rate by **$\ge 90\%$** vs `LexicalOnly` while blocking **$\ge 95\%$** of injected adversarial records.
- **H4b (Hybrid RRF Precision — Revised to Overlap-Weighted RRF after Pilot Finding):** Initial unweighted `RRF(k=60)` scored `35.0%` Top-1 (`0%` poison) because shared words flattened rank-1 vs rank-2 (`1/61` vs `1/62`); weighting the lexical RRF term by fractional query-term overlap (`(Scale/(k+rank_lex)) * coverage`) must beat `DenseWithQuarantine` Top-1 by **$\ge 50$ percentage points** while maintaining **`0%` Top-3 poison contamination** (vs `>= 90%` contamination for `LexicalOnly`).
- **H4c (Real GnoVM Familiar Gas):** Real `gno test -v` execution of `MemoryVault.Ingest` (8 records) + `RetrieveTopK` + `Familiar.ExecuteWithCapability` + RFC 6962 verification completes deterministically within standard GnoVM gas limits (`< 15M` gas).

---

## Experiment E5 — Cross-Reference Evaluation: Discrete 3rd-Order Jerk (`n=3`) & Pairwise Unit-Difference Fields vs Geometric Median & Hampel-CUSUM

### Motivation & Attribution
To avoid confirmation bias, we cross-referenced external non-local discrete dynamics proposals—specifically discrete third-order jerk ($\Delta^3 x_t$) and unit-normalized pairwise difference fields ($\sum_j (a_j - a_i)/\|a_j - a_i\|$) explored by Johannes Geisen (`@frintroper`, `Relational-Jerk-Dynamics` / `ToneProjekt`, custom `RIPL v1.0` license; **zero RIPL code copied**—all evaluations and clean-room MIT implementations below are independent).

### Hypotheses & Kill Criteria
- **H5a (Honest Negative Test — 3rd-Order Discrete Jerk):** Compare raw 3rd-order discrete jerk ($\Delta^3 x_t$) and Hampel+EMA-smoothed jerk against our `HampelCusum` on clean traffic, $+10\sigma$ spikes, accelerating runaway spend ($2(t-19)^{2.5}$), and stealth $+2\sigma$ step drift (`200` seeded episodes). A candidate must beat `HampelCusum` on runaway detection without degrading clean/spike FPR to earn inclusion; otherwise it is **REJECTED / KILLED**.
- **H5b (Positive Discovery — Fixed-Point Weiszfeld L1 Geometric Median):** Recognizing that $\sum_j (u_j - m)/\|u_j - m\| = 0$ is the exact first-order optimality condition of the L1 Geometric Median (Weiszfeld 1937; Vardi & Zhang 2000; 50% breakdown point), test whether pure fixed-point `GeometricMedianFixed` beats both arithmetic mean centroid cosine and raw pairwise tension $\|J_i\|$ by **$\ge 0.05$ ROC-AUC** when auditing an unguarded memory batch with **35% coordinated adversarial contamination** (`300` trials in $\mathbb{R}^{12}$).
