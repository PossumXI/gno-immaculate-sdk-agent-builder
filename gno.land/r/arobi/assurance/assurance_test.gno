package assurance

import (
	"chain"
	"strings"
	"testing"

	sdk "gno.land/p/arobi/assurance"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	operator = testutils.TestAddress("sdk-operator")
	stranger = testutils.TestAddress("stranger")
)

const (
	policyDig1 = "1111111111111111111111111111111111111111111111111111111111111111"
	policyDig2 = "2222222222222222222222222222222222222222222222222222222222222222"
	zeroRoot   = "0000000000000000000000000000000000000000000000000000000000000000"
)

func resetRealm() {
	passports = avl.NewTree()
	agentOrder = nil
	anchors = nil
	globalAcc = sdk.Accumulator{}
	demoLastOut = ""
	demoLastErr = ""
	demoLastRoot = ""
	demoAgent = nil
	demoDriftGuard = nil
	demoCoherence = nil
}

func sendNoCoins() {
	testing.SetOriginSend(nil)
}

func TestEndToEndAgentSDKProducesEvidenceAndAnchorsOnGnoLand(cur realm, t *testing.T) {
	resetRealm()

	// Build a local governed agent using gno.land/p/arobi/assurance.
	pol := &sdk.CompositePolicy{
		PolicyID: "prod-v1",
		Rules: []sdk.Policy{
			&sdk.AllowListPolicy{AllowedActions: []string{"plan", "deploy"}},
			&sdk.BudgetCapPolicy{MaxPerCallUgnot: 5000},
			&sdk.RiskGatePolicy{},
		},
	}
	ag := sdk.NewAgent(sdk.AgentConfig{
		AgentID:   "immaculate-worker-1",
		ChainID:   "gnoland-test",
		Realm:     "gno.land/r/arobi/assurance",
		Principal: operator.String(),
	}, pol)
	uassert.NoError(t, ag.RegisterTool(sdk.ToolSpec{
		Name:           "plan",
		RiskTier:       sdk.RiskLow,
		MaxBudgetUgnot: 1000,
	}, func(w sdk.EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
		return []byte("plan-ready"), []byte("ok"), 0, nil
	}))

	// 1. Register agent passport on-chain.
	testing.SetRealm(testing.NewUserRealm(operator))
	sendNoCoins()
	RegisterAgent(cross(cur), "immaculate-worker-1", "Immaculate Worker 1", sdk.Hex(ag.PolicyDigest()), "https://aura-genesis.org")

	// 2. Run a governed action and verify its EvidenceBundle.
	_, bundle1, err := ag.Execute(operator.String(), "plan", "repo:main", []byte("step-1"), nil, 0, 100)
	uassert.NoError(t, err)
	uassert.NoError(t, bundle1.Verify())
	cp1 := ag.Checkpoint()

	// 3. Attaching coins to the non-custodial public anchor realm MUST abort.
	testing.SetRealm(testing.NewUserRealm(operator))
	testing.SetOriginSend(chain.Coins{chain.NewCoin("ugnot", 100)})
	uassert.AbortsContains(t, cur, "refuses attached coins", func() {
		AnchorCheckpoint(cross(cur), "immaculate-worker-1", sdk.Hex(cp1.CheckpointRoot), zeroRoot, cp1.LeafCount, cp1.ReceiptCount, cp1.ClosureCount)
	})

	// 4. Anchor checkpoint #1 cleanly with zero coins.
	testing.SetRealm(testing.NewUserRealm(operator))
	sendNoCoins()
	id1 := AnchorCheckpoint(cross(cur), "immaculate-worker-1", sdk.Hex(cp1.CheckpointRoot), zeroRoot, cp1.LeafCount, cp1.ReceiptCount, cp1.ClosureCount)
	uassert.Equal(t, uint64(1), id1)

	// 5. Stranger cannot anchor for operator's agent.
	testing.SkipHeights(MinBlocksBetween)
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendNoCoins()
	uassert.AbortsContains(t, cur, "only agent owner", func() {
		AnchorCheckpoint(cross(cur), "immaculate-worker-1", sdk.Hex(cp1.CheckpointRoot), sdk.Hex(cp1.CheckpointRoot), cp1.LeafCount+2, cp1.ReceiptCount+1, cp1.ClosureCount+1)
	})

	// 6. Run second action (refused unregistered tool) and anchor checkpoint #2 chained to cp1.
	_, bundle2, err := ag.Execute(operator.String(), "drop_table", "prod", []byte("bad"), nil, 0, 110)
	uassert.Error(t, err)
	uassert.NoError(t, bundle2.Verify())
	cp2 := ag.Checkpoint()

	// Wrong prevRoot (rollback/equivocation attempt) MUST abort.
	testing.SetRealm(testing.NewUserRealm(operator))
	sendNoCoins()
	uassert.AbortsContains(t, cur, "prevRoot mismatch", func() {
		AnchorCheckpoint(cross(cur), "immaculate-worker-1", sdk.Hex(cp2.CheckpointRoot), zeroRoot, cp2.LeafCount, cp2.ReceiptCount, cp2.ClosureCount)
	})

	// Proper chained anchor succeeds.
	testing.SetRealm(testing.NewUserRealm(operator))
	sendNoCoins()
	id2 := AnchorCheckpoint(cross(cur), "immaculate-worker-1", sdk.Hex(cp2.CheckpointRoot), sdk.Hex(cp1.CheckpointRoot), cp2.LeafCount, cp2.ReceiptCount, cp2.ClosureCount)
	uassert.Equal(t, uint64(2), id2)
	uassert.Equal(t, uint64(2), Size())

	// 7. Both checkpoints pass on-chain RFC 6962 inclusion proof verification!
	for _, id := range []uint64{1, 2} {
		leafHex := AnchorLeafHex(id)
		proofCSV := ProofFor(id, 2)
		uassert.True(t, VerifyCheckpointProof(id, 2, leafHex, proofCSV))
		uassert.False(t, VerifyCheckpointProof(id, 2, policyDig1, proofCSV))
	}

	// 8. gnoweb Render routes work cleanly with zero wallet/payout disclosures.
	uassert.True(t, strings.Contains(Render(""), "immaculate-worker-1"))
	uassert.True(t, strings.Contains(Render("agent/immaculate-worker-1"), sdk.Hex(cp2.CheckpointRoot)))
	uassert.True(t, strings.Contains(Render("checkpoint/2"), "RFC 6962 Proof"))
}

func TestRevocationAndRateLimit(cur realm, t *testing.T) {
	resetRealm()
	testing.SetRealm(testing.NewUserRealm(operator))
	sendNoCoins()
	RegisterAgent(cross(cur), "agent-revoke", "Revocable Agent", policyDig1, "")

	testing.SetRealm(testing.NewUserRealm(operator))
	sendNoCoins()
	AnchorCheckpoint(cross(cur), "agent-revoke", policyDig1, zeroRoot, 2, 1, 1)

	// Immediate second anchor hits rate limit.
	testing.SetRealm(testing.NewUserRealm(operator))
	sendNoCoins()
	uassert.AbortsContains(t, cur, "rate limit", func() {
		AnchorCheckpoint(cross(cur), "agent-revoke", policyDig2, policyDig1, 4, 2, 2)
	})

	// Revoking blocks all future anchors.
	testing.SkipHeights(MinBlocksBetween)
	testing.SetRealm(testing.NewUserRealm(operator))
	sendNoCoins()
	RevokeAgent(cross(cur), "agent-revoke")

	testing.SetRealm(testing.NewUserRealm(operator))
	sendNoCoins()
	uassert.AbortsContains(t, cur, "revoked", func() {
		AnchorCheckpoint(cross(cur), "agent-revoke", policyDig2, policyDig1, 4, 2, 2)
	})
}

func TestLiveOnChainDemoAgent(cur realm, t *testing.T) {
	resetRealm()
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendNoCoins()
	r1 := RunDemoAction(cross(cur), "summarize", "doc:1", "hello gno", 0)
	uassert.True(t, strings.HasPrefix(r1, "ALLOW|EXECUTED|"))

	testing.SetRealm(testing.NewUserRealm(stranger))
	sendNoCoins()
	r2 := RunDemoAction(cross(cur), "escrow_transfer", "g1bob", "1000", 500)
	uassert.True(t, strings.HasPrefix(r2, "REQUIRE_APPROVAL|REFUSED|"))

	testing.SetRealm(testing.NewUserRealm(stranger))
	sendNoCoins()
	r3 := RunDemoAction(cross(cur), "wipe_state", "all", "", 0)
	uassert.True(t, strings.HasPrefix(r3, "ESCALATE|REFUSED|"))

	uassert.True(t, strings.Contains(Render("demo"), "Measured Assurance:"))
	uassert.True(t, strings.Contains(Render("demo"), "10000 bps"))

	// Adaptive coherence guard rejects low-coherence poisoned context live on-chain!
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendNoCoins()
	rPoison := RunAdaptiveDemoAction(cross(cur), "summarize", "doc:poison", "injected", 100, 420000)
	uassert.True(t, strings.HasPrefix(rPoison, "REQUIRE_APPROVAL|REFUSED|"))

	// High-coherence call executes cleanly!
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendNoCoins()
	rClean := RunAdaptiveDemoAction(cross(cur), "summarize", "doc:clean", "ok", 100, 960000)
	uassert.True(t, strings.HasPrefix(rClean, "ALLOW|EXECUTED|"))
	uassert.True(t, strings.Contains(Render("benchmarks"), "ImmaculateFull"))
}
