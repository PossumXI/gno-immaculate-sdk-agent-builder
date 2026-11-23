package assurance

import (
	"errors"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestAccumulatorRFC6962ProofsAndTamperRejection(t *testing.T) {
	var acc Accumulator
	// Empty root is SHA-256("").
	uassert.Equal(t, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Hex(acc.Root()))

	leaves := make([][32]byte, 0, 7)
	roots := make([][32]byte, 0, 7)
	for i := 0; i < 7; i++ {
		leaf := LeafHash([]byte("arobi-evidence-leaf-" + string(rune('a'+i))))
		idx := acc.Append(leaf)
		uassert.Equal(t, uint64(i), idx)
		leaves = append(leaves, leaf)
		roots = append(roots, acc.Root())
	}

	uassert.Equal(t, uint64(7), acc.Size())

	// Every historical tree size must reconstruct the exact root and valid proofs.
	for size := uint64(1); size <= 7; size++ {
		histRoot, err := acc.RootAt(size)
		uassert.NoError(t, err)
		uassert.Equal(t, Hex(roots[size-1]), Hex(histRoot))
		for idx := uint64(0); idx < size; idx++ {
			proof, err := acc.Proof(idx, size)
			uassert.NoError(t, err)
			uassert.True(t, VerifyInclusion(idx, size, leaves[idx], proof, histRoot))
			// Wrong leaf must fail verification.
			badLeaf := leaves[idx]
			badLeaf[0] ^= 0xff
			uassert.False(t, VerifyInclusion(idx, size, badLeaf, proof, histRoot))
		}
	}
}

func TestGovernedAgentLifecycleProducesVerifiableEvidenceOutOfTheBox(t *testing.T) {
	policy := &CompositePolicy{
		PolicyID: "arobi-default-guard-v1",
		Rules: []Policy{
			&AllowListPolicy{
				PolicyID:       "allowed-ops",
				AllowedActions: []string{"summarize", "escrow_pay", "delete_all"},
				AllowedTargets: []string{"doc:spec", "g1recipient", "prod:db"},
			},
			&BudgetCapPolicy{
				PolicyID:        "cap-5000",
				MaxPerCallUgnot: 5000,
			},
			&RiskGatePolicy{
				PolicyID:     "risk-tiers",
				AllowHigh:    false,
				DenyCritical: false,
			},
		},
	}

	agent := NewAgent(AgentConfig{
		AgentID:          "agent-alpha",
		ChainID:          "gnoland-test",
		Realm:            "gno.land/r/arobi/assurance",
		Principal:        "g1principal000000000000000000000000000000",
		WarrantTTLBlocks: 10,
	}, policy)

	executedCount := 0
	uassert.NoError(t, agent.RegisterTool(ToolSpec{
		Name:           "summarize",
		Description:    "Summarize a document safely",
		RiskTier:       RiskLow,
		MaxBudgetUgnot: 1000,
	}, func(w EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
		executedCount++
		return []byte("summary:" + string(input)), []byte("witness:ok"), 100, nil
	}))

	uassert.NoError(t, agent.RegisterTool(ToolSpec{
		Name:           "escrow_pay",
		Description:    "High-risk DeFi transfer",
		RiskTier:       RiskHigh,
		MaxBudgetUgnot: 5000,
	}, func(w EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
		executedCount++
		return []byte("paid"), []byte("tx:1"), 2000, nil
	}))

	uassert.NoError(t, agent.RegisterTool(ToolSpec{
		Name:           "delete_all",
		Description:    "Critical destructive op",
		RiskTier:       RiskCritical,
		MaxBudgetUgnot: 0,
	}, func(w EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
		executedCount++
		return []byte("deleted"), nil, 0, nil
	}))

	// 1. Allowed LOW-risk action -> executes, mints & consumes warrant, closes EXECUTED, bundle verifies.
	out, b1, err := agent.Execute("g1caller", "summarize", "doc:spec", []byte("hello"), []byte("ctx-1"), 500, 100)
	uassert.NoError(t, err)
	uassert.Equal(t, "summary:hello", string(out))
	uassert.Equal(t, string(VerdictAllow), string(b1.Decision.Verdict))
	uassert.True(t, b1.HasWarrant)
	uassert.True(t, b1.Warrant.Consumed)
	uassert.Equal(t, string(OutcomeExecuted), string(b1.Closure.Outcome))
	uassert.Equal(t, int64(100), b1.Closure.SpentUgnot)
	uassert.NoError(t, b1.Verify())
	uassert.Equal(t, 1, executedCount)

	// Below MinSamplesForMeasuredScore (3), metrics MUST stay UNMEASURED (never fake constants).
	mEarly := agent.Metrics(105, 0)
	uassert.False(t, mEarly.Measured)
	uassert.Equal(t, uint64(1), mEarly.TotalDecisions)

	// 2. HIGH-risk action -> REQUIRE_APPROVAL, zero side effects, immutable REFUSED closure.
	_, b2, err := agent.Execute("g1caller", "escrow_pay", "g1recipient", []byte("pay"), []byte("ctx-2"), 1000, 101)
	uassert.Error(t, err)
	uassert.Equal(t, string(VerdictRequireApproval), string(b2.Decision.Verdict))
	uassert.False(t, b2.HasWarrant)
	uassert.Equal(t, string(OutcomeRefused), string(b2.Closure.Outcome))
	uassert.NoError(t, b2.Verify())
	uassert.Equal(t, 1, executedCount)

	// 3. CRITICAL-risk action -> ESCALATE, zero side effects, immutable REFUSED closure.
	_, b3, err := agent.Execute("g1caller", "delete_all", "prod:db", []byte("drop"), []byte("ctx-3"), 0, 102)
	uassert.Error(t, err)
	uassert.Equal(t, string(VerdictEscalate), string(b3.Decision.Verdict))
	uassert.False(t, b3.HasWarrant)
	uassert.Equal(t, string(OutcomeRefused), string(b3.Closure.Outcome))
	uassert.NoError(t, b3.Verify())
	uassert.Equal(t, 1, executedCount)

	// 4. Budget cap exceeded on LOW-risk tool -> DENY, zero side effects.
	_, b4, err := agent.Execute("g1caller", "summarize", "doc:spec", []byte("big"), []byte("ctx-4"), 9000, 103)
	uassert.Error(t, err)
	uassert.Equal(t, string(VerdictDeny), string(b4.Decision.Verdict))
	uassert.Equal(t, "TOOL_BUDGET_EXCEEDED", b4.Decision.ReasonCode)
	uassert.NoError(t, b4.Verify())
	uassert.Equal(t, 1, executedCount)

	// Full chain integrity + measured assurance metrics (4 >= MinSamplesForMeasuredScore).
	uassert.NoError(t, agent.VerifyChain())
	cp := agent.Checkpoint()
	uassert.Equal(t, uint64(8), cp.LeafCount) // 4 receipts + 4 closures
	uassert.Equal(t, uint64(4), cp.ReceiptCount)
	uassert.Equal(t, uint64(4), cp.ClosureCount)

	m := agent.Metrics(110, 102)
	uassert.True(t, m.Measured)
	uassert.Equal(t, uint64(10000), m.GovernanceBps)
	uassert.Equal(t, uint64(10000), m.ClosureIntegrityBps)
	uassert.Equal(t, uint64(10000), m.RefusalIntegrityBps)
	uassert.Equal(t, int64(8), m.AnchorLagBlocks)
}

func TestFailClosedKillSwitchOverspendAndTamperDetection(t *testing.T) {
	agent := NewAgent(AgentConfig{
		AgentID:   "agent-guard",
		ChainID:   "gnoland-test",
		Realm:     "gno.land/r/arobi/assurance",
		Principal: "g1principal000000000000000000000000000000",
	}, &AllowListPolicy{
		PolicyID:       "allow-rogue",
		AllowedActions: []string{"rogue_spend", "flaky"},
	})

	// Tool attempts to overspend its warrant ceiling -> recorded as OutcomeFailed.
	uassert.NoError(t, agent.RegisterTool(ToolSpec{
		Name:           "rogue_spend",
		RiskTier:       RiskLow,
		MaxBudgetUgnot: 500,
	}, func(w EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
		return []byte("oops"), nil, 999, nil
	}))

	uassert.NoError(t, agent.RegisterTool(ToolSpec{
		Name:           "flaky",
		RiskTier:       RiskLow,
		MaxBudgetUgnot: 500,
	}, func(w EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
		return nil, nil, 0, errors.New("downstream timeout")
	}))

	_, b1, err := agent.Execute("g1u", "rogue_spend", "target", []byte("x"), nil, 100, 10)
	uassert.Error(t, err)
	uassert.True(t, strings.Contains(err.Error(), "violated warrant spend ceiling"))
	uassert.Equal(t, string(OutcomeFailed), string(b1.Closure.Outcome))
	uassert.NoError(t, b1.Verify())

	// Kill switch pauses all actions -> fail-closed refusal receipt.
	agent.Pause()
	_, b2, err := agent.Execute("g1u", "flaky", "target", []byte("y"), nil, 0, 11)
	uassert.Error(t, err)
	uassert.Equal(t, "AGENT_PAUSED", b2.Decision.ReasonCode)
	uassert.Equal(t, string(OutcomeRefused), string(b2.Closure.Outcome))
	uassert.NoError(t, b2.Verify())

	// Tampering with the EvidenceBundle must be caught immediately by Verify().
	tampered := b1
	tampered.Receipt.ReasonCode = "FORGED"
	uassert.Error(t, tampered.Verify())
}

func TestFluentAgentBuilderProducesVerifiableEvidence(t *testing.T) {
	ag, err := NewAgentBuilder("immaculate-builder-demo").
		WithChain("gnoland-testnet", "gno.land/r/arobi/assurance").
		WithPrincipal("g1principal000000000000000000000000000000").
		AllowActions("read_doc", "wire_funds").
		WithBudgetCap(1000).
		WithRiskGate(false, true).
		WithTool(ToolSpec{Name: "read_doc", RiskTier: RiskLow, MaxBudgetUgnot: 500},
			func(w EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
				return []byte("read:" + string(input)), []byte("w"), 0, nil
			}).
		WithTool(ToolSpec{Name: "wire_funds", RiskTier: RiskCritical, MaxBudgetUgnot: 1000},
			func(w EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
				return []byte("wired"), nil, 500, nil
			}).
		Build()
	uassert.NoError(t, err)

	out, b1, err := ag.Execute("g1alice", "read_doc", "spec.md", []byte("q"), nil, 0, 50)
	uassert.NoError(t, err)
	uassert.Equal(t, "read:q", string(out))
	uassert.NoError(t, b1.Verify())

	_, b2, err := ag.Execute("g1alice", "wire_funds", "g1bob", []byte("100"), nil, 100, 51)
	uassert.Error(t, err)
	uassert.Equal(t, string(VerdictDeny), string(b2.Decision.Verdict))
	uassert.Equal(t, "CRITICAL_RISK_DENIED", b2.Decision.ReasonCode)
	uassert.NoError(t, b2.Verify())
	uassert.NoError(t, ag.VerifyChain())
}
