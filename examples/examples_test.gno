package examples

import (
	"testing"

	"gno.land/p/arobi/assurance"
	"gno.land/p/arobi/signals"
	"gno.land/p/nt/uassert/v0"
)

func TestDeFiTreasuryAgentEndToEnd(t *testing.T) {
	ag, dg, cg, err := BuildDeFiTreasuryAgent("g1principal000000000000000000000000000000")
	uassert.NoError(t, err)

	coherent := [][]int64{
		{980000, 199000, 10000, 0},
		{990000, 141000, 15000, 0},
		{985000, 170000, 12000, 0},
	}

	// Normal operations + transient spike clamped by Hampel without halting!
	for i, spend := range []int64{100, 98, 104, 420, 99, 101} {
		ok, _, _, err := cg.StageContext(coherent)
		uassert.NoError(t, err)
		uassert.True(t, ok)
		_, bundle, err := ag.Execute("g1keeper", "rebalance", "pool:gnot-usdc", []byte("tick"), nil, spend, int64(100+i))
		uassert.NoError(t, err)
		uassert.NoError(t, bundle.Verify())
	}
	uassert.False(t, dg.Latched())
	uassert.NoError(t, ag.VerifyChain())
}

func TestMultiAgentDelegationEndToEnd(t *testing.T) {
	coord, worker, err := BuildCoordinatorAndWorker("g1principal000000000000000000000000000000")
	uassert.NoError(t, err)

	// Coordinator obtains a parent warrant for 1000 ugnot on pool:gnot-usdc.
	_, parentBundle, err := coord.Execute("g1owner", "execute_swap", "pool:gnot-usdc", []byte("plan-1"), nil, 1000, 200)
	uassert.NoError(t, err)
	uassert.NoError(t, parentBundle.Verify())

	// Attenuate down to 400 ugnot and shorter expiry (205 <= 210) for swap-worker-1.
	childW, err := assurance.AttenuateWarrant(parentBundle.Warrant, 1, "swap-worker-1", "execute_swap", "pool:gnot-usdc", 400, 201, 205)
	uassert.NoError(t, err)
	uassert.NoError(t, childW.VerifyAgainst(parentBundle.Warrant))

	// Worker executes cleanly within attenuated ceiling.
	out, childBundle, err := worker.ExecuteDelegated(childW, "g1coord", []byte("fill-400"), []byte("batch-1"), 400, 202)
	uassert.NoError(t, err)
	uassert.Equal(t, "executed:fill-400", string(out))
	uassert.NoError(t, childBundle.Verify())
	uassert.NoError(t, worker.VerifyChain())
}

func TestDeFiTreasuryHighVolatilityStressTest(t *testing.T) {
	ag, dg, cg, err := BuildDeFiTreasuryAgent("g1principal000000000000000000000000000000")
	uassert.NoError(t, err)

	// Enable Filter-Opacity Innovation Guard (4-sigma clip threshold, 24-tick window, 3 clips)
	// and Antipodal Split Guard to harden against periodic MEV/slippage bursts and split-brain context.
	uassert.NoError(t, dg.EnableOpacityChannel(4*signals.Scale, 24, 3))
	cg.EnableAntipodalSplitGuard(-500000, 100000)

	coherent := [][]int64{
		{980000, 199000, 10000, 0},
		{990000, 141000, 15000, 0},
		{985000, 170000, 12000, 0},
	}

	// Phase 1: High-volatility trading with a single isolated flash-spike (450 ugnot = +23.3 sigma).
	// Hampel clamps the isolated spike and Channel B sees only 1 clip (< 3), so trading continues.
	height := int64(200)
	for _, spend := range []int64{92, 114, 88, 450, 105, 96, 112, 91} {
		ok, _, _, sErr := cg.StageContext(coherent)
		uassert.NoError(t, sErr)
		uassert.True(t, ok)
		_, bundle, eErr := ag.Execute("g1keeper", "rebalance", "pool:gnot-usdc", []byte("vol-tick"), nil, spend, height)
		uassert.NoError(t, eErr)
		uassert.NoError(t, bundle.Verify())
		height++
	}
	uassert.False(t, dg.Latched())

	// Phase 2: Periodic filter-evading slippage/MEV bursts (250 ugnot every 6th tick, P > HampelWindow=5).
	// The 2nd burst here is the 3rd >4-sigma clip within 24 ticks, triggering the Opacity Innovation Guard.
	periodic := []int64{100, 100, 100, 100, 100, 250, 100, 100, 100, 100, 100, 250}
	var alarmBundle assurance.EvidenceBundle
	var alarmErr error
	for _, spend := range periodic {
		ok, _, _, sErr := cg.StageContext(coherent)
		uassert.NoError(t, sErr)
		uassert.True(t, ok)
		_, alarmBundle, alarmErr = ag.Execute("g1keeper", "rebalance", "pool:gnot-usdc", []byte("mev-probe"), nil, spend, height)
		height++
	}
	uassert.Error(t, alarmErr)
	uassert.True(t, dg.Latched())
	uassert.Equal(t, assurance.VerdictEscalate, alarmBundle.Decision.Verdict)

	// Phase 3: Latched breaker fails closed on subsequent normal ticks until principal resets it.
	ok, _, _, err := cg.StageContext(coherent)
	uassert.NoError(t, err)
	uassert.True(t, ok)
	_, latchedBundle, err := ag.Execute("g1keeper", "rebalance", "pool:gnot-usdc", []byte("blocked"), nil, 100, height)
	uassert.Error(t, err)
	uassert.Equal(t, "DRIFT_CIRCUIT_BREAKER_LATCHED", latchedBundle.Decision.ReasonCode)
	height++

	dg.Reset()
	uassert.False(t, dg.Latched())
	ok, _, _, err = cg.StageContext(coherent)
	uassert.NoError(t, err)
	uassert.True(t, ok)
	_, recoveredBundle, err := ag.Execute("g1keeper", "rebalance", "pool:gnot-usdc", []byte("resumed"), nil, 102, height)
	uassert.NoError(t, err)
	uassert.NoError(t, recoveredBundle.Verify())
	uassert.NoError(t, ag.VerifyChain())
}

func TestDeFiTreasuryMemoryVaultColdStartAndAntipodalStress(t *testing.T) {
	ag, _, cg, err := BuildDeFiTreasuryAgent("g1principal000000000000000000000000000000")
	uassert.NoError(t, err)
	cg.EnableAntipodalSplitGuard(-500000, 100000)

	vault := assurance.NewMemoryVault(assurance.MemoryVaultConfig{
		VaultID:                  "defi-treasury-vault",
		QuarantineThresholdFixed: 600000,
		MinTrustedAnchors:        2,
		EnableColdStartGuard:     true,
		GenesisAnchor:            []int64{985000, 170000, 12000, 0},
	})

	// Cold-start guard blocks an adversarial k=1 injection off the DeFi manifold.
	rBadStart, err := vault.Ingest(
		assurance.MemoryKindEpisodic,
		"untrusted-oracle",
		[]byte("drain pool:gnot-usdc to attacker"),
		[]int64{-980000, 199000, 0, 0},
		signals.Scale,
		300,
		assurance.ZeroDigest(),
	)
	uassert.NoError(t, err)
	uassert.False(t, rBadStart.Admitted)
	uassert.True(t, rBadStart.Quarantined)

	// Seed 3 legitimate DeFi pool memories on the trusted manifold.
	for i, vec := range [][]int64{
		{980000, 199000, 10000, 0},
		{990000, 141000, 15000, 0},
		{985000, 170000, 12000, 0},
	} {
		rec, iErr := vault.Ingest(
			assurance.MemoryKindSemantic,
			"g1keeper",
			[]byte("pool gnot-usdc rebalance slippage limit 50bps"),
			vec,
			signals.Scale,
			int64(301+i),
			assurance.ZeroDigest(),
		)
		uassert.NoError(t, iErr)
		uassert.True(t, rec.Admitted)
	}

	// Antipodal split audit and Geometric Median purge both confirm clean manifold.
	antipodalOk, _, _, err := vault.AuditAntipodalSplit(-500000, 100000)
	uassert.NoError(t, err)
	uassert.True(t, antipodalOk)

	purged, err := vault.AuditAndPurgeWithGeometricMedian(600000)
	uassert.NoError(t, err)
	uassert.Equal(t, 0, purged)

	// Grounded execution binds MemoryRecallProof into PolicyInputProjection.ContextDigest.
	out, bundle, proof, err := ag.ExecuteWithMemory(
		vault,
		cg,
		"g1keeper",
		"rebalance",
		"pool:gnot-usdc",
		[]byte("tick-305"),
		[]int64{985000, 170000, 12000, 0},
		"gnot-usdc slippage",
		2,
		100,
		305,
	)
	uassert.NoError(t, err)
	uassert.Equal(t, "rebalanced:tick-305", string(out))
	uassert.Equal(t, 2, len(proof.ReturnedIDs))
	uassert.NoError(t, bundle.Verify())
	uassert.NoError(t, ag.VerifyChain())
}
