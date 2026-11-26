package assurance

import (
	"strconv"
	"testing"

	"gno.land/p/arobi/signals"
	"gno.land/p/nt/uassert/v0"
)

// Dedicated single-operation and scaling gas benchmarks measured by real Gno v1.8.0 VM (Experiment E3).

func TestBenchSingleGovernedActionGas(t *testing.T) {
	ag, err := NewAgentBuilder("bench-agent").
		WithPrincipal("g1principal000000000000000000000000000000").
		AllowActions("ping").
		WithBudgetCap(1000).
		WithTool(ToolSpec{Name: "ping", RiskTier: RiskLow, MaxBudgetUgnot: 1000},
			func(w EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
				return []byte("pong"), []byte("w"), 100, nil
			}).
		Build()
	uassert.NoError(t, err)
	_, bundle, err := ag.Execute("g1op", "ping", "svc:1", []byte("hi"), nil, 100, 1)
	uassert.NoError(t, err)
	uassert.NoError(t, bundle.Verify())
}

func TestBenchAdaptiveDriftAndCoherenceSingleActionGas(t *testing.T) {
	base := signals.Baseline{MeanFixed: 100 * signals.Scale, SDFixed: 15 * signals.Scale}
	b := NewAgentBuilder("bench-adaptive").
		WithPrincipal("g1principal000000000000000000000000000000").
		AllowActions("rebalance").
		WithBudgetCap(1000).
		WithDriftGuard(base, 5*signals.Scale, signals.Scale, 5, false, true).
		WithCoherenceGuard(750000, false, false, true).
		WithTool(ToolSpec{Name: "rebalance", RiskTier: RiskLow, MaxBudgetUgnot: 1000},
			func(w EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
				return []byte("ok"), []byte("w"), 100, nil
			})
	ag, err := b.Build()
	uassert.NoError(t, err)
	vecs := [][]int64{
		{980000, 199000, 10000, 0, 5000, 0, 0, 0},
		{990000, 141000, 15000, 0, 4000, 0, 0, 0},
		{985000, 170000, 12000, 0, 4500, 0, 0, 0},
		{978000, 205000, 11000, 0, 4200, 0, 0, 0},
	}
	ok, _, _, err := b.CoherenceGuard().StageContext(vecs)
	uassert.NoError(t, err)
	uassert.True(t, ok)
	_, bundle, err := ag.Execute("g1op", "rebalance", "pool:1", []byte("tick"), nil, 100, 1)
	uassert.NoError(t, err)
	uassert.NoError(t, bundle.Verify())
}

func runAccScale(t *testing.T, n uint64, maxProofLen int) {
	var acc Accumulator
	var lastLeaf [32]byte
	for i := uint64(0); i < n; i++ {
		lastLeaf = LeafHash([]byte("scale-" + strconv.FormatUint(i, 10)))
		acc.Append(lastLeaf)
	}
	proof, err := acc.Proof(n-1, n)
	uassert.NoError(t, err)
	uassert.True(t, len(proof) <= maxProofLen)
	uassert.True(t, VerifyInclusion(n-1, n, lastLeaf, proof, acc.Root()))
}

func TestBenchAccumulatorScale10(t *testing.T)  { runAccScale(t, 10, 4) }
func TestBenchAccumulatorScale50(t *testing.T)  { runAccScale(t, 50, 6) }
func TestBenchAccumulatorScale100(t *testing.T) { runAccScale(t, 100, 7) }
func TestBenchAccumulatorScale250(t *testing.T) { runAccScale(t, 250, 8) }

// Golden cross-language parity vector matching verifier/verify-evidence.mjs bit-for-bit (Experiment E1 H1b).
func TestCrossLanguageGoldenVectorParity(t *testing.T) {
	p := PolicyInputProjection{
		ChainID:       "gnoland-testnet",
		Realm:         "gno.land/r/arobi/assurance",
		AgentID:       "golden-agent-1",
		Principal:     "g1principal000000000000000000000000000000",
		Caller:        "g1operator",
		Action:        "summarize",
		Target:        "doc:golden",
		InputDigest:   HashString("golden-input"),
		ContextDigest: HashString("golden-context"),
		BudgetUgnot:   500,
		RiskTier:      RiskLow,
		Height:        42,
	}
	pDig := p.Digest()
	polDig := HashString("golden-policy-v1")
	w := EffectWarrant{
		ID:               1,
		AgentID:          "golden-agent-1",
		ProjectionDigest: pDig,
		PolicyDigest:     polDig,
		Action:           "summarize",
		Target:           "doc:golden",
		MaxSpendUgnot:    500,
		IssuedHeight:     42,
		ExpiryHeight:     52,
	}
	wDig := w.Digest()
	r := DecisionReceipt{
		Seq:              1,
		PrevHash:         ZeroDigest(),
		ChainID:          "gnoland-testnet",
		Realm:            "gno.land/r/arobi/assurance",
		AgentID:          "golden-agent-1",
		Caller:           "g1operator",
		ProjectionDigest: pDig,
		PolicyDigest:     polDig,
		Verdict:          VerdictAllow,
		ReasonCode:       "ALL_RULES_PASSED",
		WarrantDigest:    wDig,
		Height:           42,
	}
	rLeaf := r.LeafHash()
	c := EffectClosure{
		Seq:              2,
		PrevHash:         rLeaf,
		AgentID:          "golden-agent-1",
		WarrantDigest:    wDig,
		DecisionLeafHash: rLeaf,
		OutputDigest:     HashString("golden-output"),
		WitnessDigest:    HashString("golden-witness"),
		Outcome:          OutcomeExecuted,
		SpentUgnot:       100,
		Height:           42,
	}
	cLeaf := c.LeafHash()
	var acc Accumulator
	acc.Append(rLeaf)
	acc.Append(cLeaf)
	root := acc.Root()

	// Print deterministic digests when running `gno test -v` so run_experiments.mjs cross-checks against Node.js!
	println("GOLDEN_PROJ=" + Hex(pDig))
	println("GOLDEN_WARRANT=" + Hex(wDig))
	println("GOLDEN_RECEIPT_LEAF=" + Hex(rLeaf))
	println("GOLDEN_CLOSURE_LEAF=" + Hex(cLeaf))
	println("GOLDEN_ROOT=" + Hex(root))
	uassert.Equal(t, 64, len(Hex(root)))
}

func benchMedianVectors16x8() [][]int64 {
	// 16 exact unit vectors in 8D (||v|| == Scale): 12 clean vectors near +e0 and 4 coordinated outliers near -e0.
	return [][]int64{
		{1000000, 0, 0, 0, 0, 0, 0, 0},
		{800000, 600000, 0, 0, 0, 0, 0, 0},
		{800000, 0, 600000, 0, 0, 0, 0, 0},
		{800000, 360000, 480000, 0, 0, 0, 0, 0},
		{960000, 280000, 0, 0, 0, 0, 0, 0},
		{960000, 0, 280000, 0, 0, 0, 0, 0},
		{960000, 0, 0, 280000, 0, 0, 0, 0},
		{960000, 0, 0, 0, 280000, 0, 0, 0},
		{960000, 0, 0, 0, 0, 280000, 0, 0},
		{960000, 0, 0, 0, 0, 0, 280000, 0},
		{960000, 0, 0, 0, 0, 0, 0, 280000},
		{800000, 0, 0, 360000, 480000, 0, 0, 0},
		{-960000, 280000, 0, 0, 0, 0, 0, 0},
		{-960000, 0, 280000, 0, 0, 0, 0, 0},
		{-800000, 600000, 0, 0, 0, 0, 0, 0},
		{-800000, 0, 600000, 0, 0, 0, 0, 0},
	}
}

func TestBenchGeometricMedian16x8Gas(t *testing.T) {
	vecs := benchMedianVectors16x8()
	gmFixed, err := signals.GeometricMedianFixed(vecs, 8)
	uassert.NoError(t, err)
	gmNorm, err := signals.GeometricMedianNormalizedFixed(vecs, 8)
	uassert.NoError(t, err)
	uassert.Equal(t, 8, len(gmNorm))
	uassert.True(t, gmNorm[0] > 900000)
	for j := range gmFixed {
		uassert.Equal(t, gmFixed[j], gmNorm[j])
	}
}

func TestBenchGeometricMedian16x8FixedGas(t *testing.T) {
	vecs := benchMedianVectors16x8()
	gm, err := signals.GeometricMedianFixed(vecs, 8)
	uassert.NoError(t, err)
	uassert.True(t, gm[0] > 900000)
}

func TestBenchGeometricMedian16x8NormalizedGas(t *testing.T) {
	vecs := benchMedianVectors16x8()
	gm, err := signals.GeometricMedianNormalizedFixed(vecs, 8)
	uassert.NoError(t, err)
	uassert.True(t, gm[0] > 900000)
}

func TestBenchOpacityDriftAndAntipodalStepGas(t *testing.T) {
	base := signals.Baseline{MeanFixed: 100 * signals.Scale, SDFixed: 15 * signals.Scale}
	oa, err := signals.NewOpacityAwareHampelCusum(base, 5*signals.Scale, signals.Scale, 5, 3*signals.Scale, 4*signals.Scale, 24, 3)
	uassert.NoError(t, err)

	alarm, _, ch, ev := oa.Update(100 * signals.Scale)
	uassert.False(t, alarm)
	uassert.Equal(t, "none", ch)
	uassert.False(t, ev.Alarm)

	vecs := [][]int64{
		{980000, 199000, 10000, 0, 5000, 0, 0, 0},
		{990000, 141000, 15000, 0, 4000, 0, 0, 0},
		{985000, 170000, 12000, 0, 4500, 0, 0, 0},
		{978000, 205000, 11000, 0, 4200, 0, 0, 0},
	}
	ok, frac, antipodalEv, err := signals.AntipodalSplitGate(vecs, -500000, 100000)
	uassert.NoError(t, err)
	uassert.True(t, ok)
	uassert.Equal(t, int64(0), frac)
	uassert.False(t, antipodalEv.Alarm)
}

func TestGeometricMedianNormalizedFixedValidationAndParity(t *testing.T) {
	_, err := signals.GeometricMedianNormalizedFixed(nil, 8)
	uassert.Error(t, err)
	_, err = signals.GeometricMedianNormalizedFixed([][]int64{{signals.Scale, 0}}, 8)
	uassert.Error(t, err)
	_, err = signals.GeometricMedianNormalizedFixed([][]int64{{}, {}}, 8)
	uassert.Error(t, err)
	_, err = signals.GeometricMedianNormalizedFixed([][]int64{{signals.Scale, 0}, {signals.Scale}}, 8)
	uassert.Error(t, err)

	// Non-unit inputs normalized once match GeometricMedianFixed bit-for-bit.
	raw := [][]int64{
		{312450, 418920, -192830, 512340, 223110, -334120, 128900, 441230},
		{298120, 391230, -181120, 489120, 210900, -310110, 119800, 430110},
		{305000, 405000, -188000, 501000, 215000, -320000, 124000, 435000},
		{-450000, -380000, 210000, -490000, -190000, 330000, -110000, -410000},
	}
	units := make([][]int64, len(raw))
	for i, v := range raw {
		u, uErr := signals.UnitNormalizeFixed(v)
		uassert.NoError(t, uErr)
		units[i] = u
	}
	gmRaw, err := signals.GeometricMedianFixed(raw, 8)
	uassert.NoError(t, err)
	gmUnits, err := signals.GeometricMedianNormalizedFixed(units, 8)
	uassert.NoError(t, err)
	for j := range gmRaw {
		uassert.Equal(t, gmRaw[j], gmUnits[j])
	}
}
