// Package examples provides runnable, GnoVM-tested end-to-end reference agents built
// with Immaculate SDK Agent Builder (gno.land/p/arobi/assurance + signals).
package examples

import (
	"gno.land/p/arobi/assurance"
	"gno.land/p/arobi/signals"
)

// BuildDeFiTreasuryAgent builds an autonomous DeFi liquidity rebalancer guarded by:
//   - AllowList (rebalance, claim_yield)
//   - Hard BudgetCap (5000 ugnot per call)
//   - RiskGate (LOW/MEDIUM auto-allow, HIGH requires approval, CRITICAL denied)
//   - Dual-Channel Opacity-Aware Hampel-CUSUM Drift Circuit Breaker (clamps +/-10sigma oracle spikes, blocks periodic bursts & stealth drift)
//   - Spherical Context Coherence Gate + Antipodal Split-Brain Guard (blocks cross-session memory poisoning & opposing-pair splits)
func BuildDeFiTreasuryAgent(owner string) (*assurance.Agent, *assurance.DriftGuardPolicy, *assurance.CoherenceGuardPolicy, error) {
	base := signals.Baseline{
		MeanFixed: 100 * signals.Scale,
		SDFixed:   15 * signals.Scale,
	}
	b := assurance.NewAgentBuilder("defi-treasury-rebalancer").
		WithChain("gnoland-testnet", "gno.land/r/arobi/assurance").
		WithPrincipal(owner).
		AllowActions("rebalance", "claim_yield").
		AllowTargets("pool:gnot-usdc", "pool:gnot-atom").
		WithBudgetCap(5000).
		WithRiskGate(false, true).
		WithOpacityAwareDriftGuard(base, 5*signals.Scale, signals.Scale, 5, 4*signals.Scale, 24, 3, false, true).
		WithCoherenceGuard(750000, false, false, true).
		WithTool(assurance.ToolSpec{
			Name:           "rebalance",
			Description:    "Rebalance liquidity ticks within bounded slippage",
			RiskTier:       assurance.RiskLow,
			MaxBudgetUgnot: 5000,
		}, func(w assurance.EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
			return []byte("rebalanced:" + string(input)), []byte("pool-proof"), w.MaxSpendUgnot, nil
		}).
		WithTool(assurance.ToolSpec{
			Name:           "claim_yield",
			Description:    "Harvest accrued LP fees to treasury",
			RiskTier:       assurance.RiskMedium,
			MaxBudgetUgnot: 500,
		}, func(w assurance.EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
			return []byte("claimed:" + string(input)), []byte("yield-proof"), 0, nil
		})

	if cg := b.CoherenceGuard(); cg != nil {
		cg.EnableAntipodalSplitGuard(-500000, 100000)
	}

	ag, err := b.Build()
	if err != nil {
		return nil, nil, nil, err
	}
	return ag, b.DriftGuard(), b.CoherenceGuard(), nil
}

// BuildCoordinatorAndWorker constructs a two-agent team demonstrating strictly attenuated
// multi-agent warrant delegation (coordinator -> specialist worker) with zero privilege escalation.
func BuildCoordinatorAndWorker(owner string) (coordinator *assurance.Agent, worker *assurance.Agent, err error) {
	coordinator, err = assurance.NewAgentBuilder("coordinator-alpha").
		WithChain("gnoland-testnet", "gno.land/r/arobi/assurance").
		WithPrincipal(owner).
		AllowActions("execute_swap").
		AllowTargets("pool:gnot-usdc").
		WithBudgetCap(2000).
		WithTool(assurance.ToolSpec{
			Name:           "execute_swap",
			Description:    "Authorize bounded DEX swap budget for specialist worker",
			RiskTier:       assurance.RiskLow,
			MaxBudgetUgnot: 2000,
		}, func(w assurance.EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
			return []byte("authorized:" + string(input)), []byte("coord-ok"), 0, nil
		}).
		Build()
	if err != nil {
		return nil, nil, err
	}

	worker, err = assurance.NewAgentBuilder("swap-worker-1").
		WithChain("gnoland-testnet", "gno.land/r/arobi/assurance").
		WithPrincipal(owner).
		AllowActions("execute_swap").
		AllowTargets("pool:gnot-usdc").
		WithBudgetCap(1000).
		WithTool(assurance.ToolSpec{
			Name:           "execute_swap",
			Description:    "Execute delegated swap under attenuated warrant",
			RiskTier:       assurance.RiskLow,
			MaxBudgetUgnot: 1000,
		}, func(w assurance.EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
			return []byte("executed:" + string(input)), []byte("swap-tx-receipt"), w.MaxSpendUgnot, nil
		}).
		Build()
	if err != nil {
		return nil, nil, err
	}
	return coordinator, worker, nil
}
