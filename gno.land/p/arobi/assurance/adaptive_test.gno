package assurance

import (
	"strconv"
	"testing"

	"gno.land/p/arobi/signals"
	"gno.land/p/nt/uassert/v0"
)

func TestAdaptiveDriftAndCoherenceCircuitBreaker(t *testing.T) {
	// Baseline: quiet agent spends ~100ugnot (SD ~= 15ugnot).
	base := signals.Baseline{
		MeanFixed: 100 * signals.Scale,
		SDFixed:   15 * signals.Scale,
	}

	b := NewAgentBuilder("adaptive-defi-agent").
		WithChain("gnoland-testnet", "gno.land/r/arobi/assurance").
		WithPrincipal("g1principal000000000000000000000000000000").
		AllowActions("rebalance").
		WithBudgetCap(5000).
		WithDriftGuard(base, 5*signals.Scale, signals.Scale, 5, false, true).
		WithCoherenceGuard(750000, false, false, true).
		WithTool(ToolSpec{
			Name:           "rebalance",
			RiskTier:       RiskLow,
			MaxBudgetUgnot: 5000,
		}, func(w EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
			return []byte("rebalanced"), []byte("pool:ok"), w.MaxSpendUgnot, nil
		})

	ag, err := b.Build()
	uassert.NoError(t, err)
	dg := b.DriftGuard()
	cg := b.CoherenceGuard()

	coherentCtx := [][]int64{
		{980000, 199000, 10000, 0},
		{990000, 141000, 15000, 0},
		{985000, 170000, 12000, 0},
	}
	poisonedCtx := [][]int64{
		{1000000, 0, 0, 0},
		{0, 1000000, 0, 0},
		{-1000000, 0, 0, 0},
	}

	// 1. Missing context embeddings fails closed (RequireOnAllCall=true).
	_, bMiss, err := ag.Execute("g1op", "rebalance", "pool:1", []byte("r0"), nil, 100, 10)
	uassert.Error(t, err)
	uassert.Equal(t, "CONTEXT_COHERENCE_MISSING", bMiss.Decision.ReasonCode)
	uassert.NoError(t, bMiss.Verify())

	// 2. Poisoned cross-session memory batch fails closed with zero side effects!
	okP, scoreP, _, err := cg.StageContext(poisonedCtx)
	uassert.NoError(t, err)
	uassert.False(t, okP)
	uassert.True(t, scoreP < 750000)
	_, bPoison, err := ag.Execute("g1op", "rebalance", "pool:1", []byte("r1"), nil, 100, 11)
	uassert.Error(t, err)
	uassert.Equal(t, "CONTEXT_COHERENCE_LOW", bPoison.Decision.ReasonCode)
	uassert.Equal(t, string(OutcomeRefused), string(bPoison.Closure.Outcome))
	uassert.NoError(t, bPoison.Verify())

	// 3. Normal quiet ops + one isolated +15sigma spend spike (400ugnot) -> Hampel clamps spike, NO false alarm!
	quietSpends := []int64{100, 102, 98, 101, 400, 99, 100}
	for i, sp := range quietSpends {
		okC, _, _, err := cg.StageContext(coherentCtx)
		uassert.NoError(t, err)
		uassert.True(t, okC)
		out, bundle, err := ag.Execute("g1op", "rebalance", "pool:1", []byte("q"), nil, sp, int64(20+i))
		uassert.NoError(t, err)
		uassert.Equal(t, "rebalanced", string(out))
		uassert.NoError(t, bundle.Verify())
	}
	uassert.False(t, dg.Latched())

	// 4. Stealth gradual +3.5sigma spend drift (160ugnot, well under static 5000ugnot cap!) ->
	//    HampelCusum detects sustained shift, refuses execution, and latches circuit breaker!
	trippedAt := -1
	for step := 0; step < 12; step++ {
		_, _, _, err := cg.StageContext(coherentCtx)
		uassert.NoError(t, err)
		_, bundle, err := ag.Execute("g1op", "rebalance", "pool:1", []byte("drift"), nil, 160, int64(40+step))
		uassert.NoError(t, bundle.Verify())
		if err != nil && bundle.Decision.ReasonCode == "BEHAVIORAL_DRIFT_ALARM" {
			trippedAt = step
			uassert.Equal(t, string(VerdictEscalate), string(bundle.Decision.Verdict))
			break
		}
	}
	uassert.True(t, trippedAt >= 0 && trippedAt <= 8)
	uassert.True(t, dg.Latched())

	// 5. While latched, even a normal quiet call stays blocked until principal resets!
	_, _, _, _ = cg.StageContext(coherentCtx)
	_, bLatched, err := ag.Execute("g1op", "rebalance", "pool:1", []byte("after"), nil, 100, 60)
	uassert.Error(t, err)
	uassert.Equal(t, "DRIFT_CIRCUIT_BREAKER_LATCHED", bLatched.Decision.ReasonCode)
	uassert.NoError(t, bLatched.Verify())

	// 6. Principal resets circuit breaker -> agent resumes cleanly.
	dg.Reset()
	uassert.False(t, dg.Latched())
	uassert.NoError(t, ag.VerifyChain())
}

func TestMultiAgentDelegatedWarrantAttenuation(t *testing.T) {
	parentWarrant := EffectWarrant{
		ID:               7,
		AgentID:          "coordinator-1",
		ProjectionDigest: HashString("proj"),
		PolicyDigest:     HashString("pol"),
		Action:           "execute_swap",
		Target:           "pool:gnot-usdc",
		MaxSpendUgnot:    1000,
		IssuedHeight:     100,
		ExpiryHeight:     120,
	}

	// Privilege escalation attempts MUST ALL FAIL CLOSED:
	// (a) budget amplification
	_, err := AttenuateWarrant(parentWarrant, 1, "worker-a", "execute_swap", "pool:gnot-usdc", 1001, 101, 115)
	uassert.Error(t, err)
	// (b) expiry extension
	_, err = AttenuateWarrant(parentWarrant, 1, "worker-a", "execute_swap", "pool:gnot-usdc", 500, 101, 121)
	uassert.Error(t, err)
	// (c) action escalation
	_, err = AttenuateWarrant(parentWarrant, 1, "worker-a", "drain_treasury", "pool:gnot-usdc", 500, 101, 115)
	uassert.Error(t, err)
	// (d) target redirection
	_, err = AttenuateWarrant(parentWarrant, 1, "worker-a", "execute_swap", "pool:attacker", 500, 101, 115)
	uassert.Error(t, err)
	// (e) self-delegation
	_, err = AttenuateWarrant(parentWarrant, 1, "coordinator-1", "execute_swap", "pool:gnot-usdc", 500, 101, 115)
	uassert.Error(t, err)

	// Valid strictly attenuated delegation succeeds & verifies against parent.
	childW, err := AttenuateWarrant(parentWarrant, 1, "worker-a", "execute_swap", "pool:gnot-usdc", 400, 102, 115)
	uassert.NoError(t, err)
	uassert.NoError(t, childW.VerifyAgainst(parentWarrant))

	worker, err := NewAgentBuilder("worker-a").
		WithPrincipal("g1principal000000000000000000000000000000").
		AllowActions("execute_swap").
		AllowTargets("pool:gnot-usdc").
		WithBudgetCap(500).
		WithTool(ToolSpec{
			Name:           "execute_swap",
			RiskTier:       RiskLow,
			MaxBudgetUgnot: 500,
		}, func(w EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
			return []byte("swapped:" + string(input)), []byte("dex-receipt"), 350, nil
		}).
		Build()
	uassert.NoError(t, err)

	// Child executing above delegated ceiling (450 > 400) fails closed.
	_, _, err = worker.ExecuteDelegated(childW, "g1coord", []byte("order-1"), nil, 450, 105)
	uassert.Error(t, err)

	// Child executing after delegated expiry (116 > 115) fails closed.
	_, _, err = worker.ExecuteDelegated(childW, "g1coord", []byte("order-1"), nil, 350, 116)
	uassert.Error(t, err)

	// Child executing within attenuated bounds succeeds & emits self-verifying bundle bound to parent warrant!
	out, bundle, err := worker.ExecuteDelegated(childW, "g1coord", []byte("order-1"), []byte("memo"), 350, 105)
	uassert.NoError(t, err)
	uassert.Equal(t, "swapped:order-1", string(out))
	uassert.NoError(t, bundle.Verify())
	uassert.NoError(t, worker.VerifyChain())
}

func TestGasScalingAccumulator250Leaves(t *testing.T) {
	var acc Accumulator
	var leaves [][32]byte
	for i := 0; i < 250; i++ {
		leaf := LeafHash([]byte("bench-leaf-" + strconv.Itoa(i)))
		acc.Append(leaf)
		leaves = append(leaves, leaf)
	}
	root := acc.Root()
	for _, idx := range []uint64{0, 10, 50, 125, 249} {
		proof, err := acc.Proof(idx, 250)
		uassert.NoError(t, err)
		// RFC 6962 proof depth for 250 leaves is at most ceil(log2(250)) = 8 hashes!
		uassert.True(t, len(proof) <= 8)
		uassert.True(t, VerifyInclusion(idx, 250, leaves[idx], proof, root))
	}
	uassert.Equal(t, 64, len(Hex(root)))
}
