package examples

import (
	"testing"

	"gno.land/p/arobi/assurance"
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
