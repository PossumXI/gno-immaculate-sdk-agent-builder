package assurance

import (
	"chain/runtime"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
	sdk "gno.land/p/arobi/assurance"
)

const (
	stepDig1     = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	restoredDig  = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	committedDig = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
	reasonDig    = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
)

func resetRealmWithEffects() {
	resetRealm()
	effectTracker = sdk.NewEffectTracker()
}

func TestEffectLifecycleAllSixAcceptanceCriteria(cur realm, t *testing.T) {
	resetRealmWithEffects()

	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	RegisterAgent(cross(cur), "worker-effects-1", "Effects Worker", policyDig1, "https://aura-genesis.org")

	// -------------------------------------------------------------------------
	// Acceptance Test 1: Stop executor between step 1 and step 2 of a 3-step action.
	// After deadline height, effect reads IN_DOUBT with no call from executor,
	// open obligations list shows it with its cleanup owner and 1/3 receipt,
	// and ANY third party may call MarkInDoubt once deadline passes.
	// -------------------------------------------------------------------------
	startH := runtime.ChainHeight()
	deadline1 := startH + 10
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	res1 := BeginEffect(
		cross(cur),
		"worker-effects-1",
		"deploy:aura-genesis-prod",
		"idem-deploy-001",
		"COMPENSABLE",
		"", // empty defaults to issuer (agentOwner)
		"live deploy sha matches build artifact",
		"restore previous netlify deploy",
		"",
		3,
		deadline1,
	)
	uassert.True(t, strings.HasPrefix(res1, "eff-1|STARTED|"))

	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	s1 := RecordStep(cross(cur), "eff-1", 1, "upload-assets", stepDig1, true)
	uassert.True(t, strings.HasPrefix(s1, "eff-1|STEP|1|"))

	// Executor goes silent (no step 2, no step 3, no CloseEffect).
	// Before deadline, stranger cannot prematurely mark IN_DOUBT.
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendFee(0)
	uassert.AbortsContains(t, cur, "deadline height not yet reached", func() {
		MarkInDoubt(cross(cur), "eff-1")
	})

	// Advance chain height past deadline.
	testing.SkipHeights(12)

	// Without ANY call from the silent executor, EffectStateOf reads IN_DOUBT.
	uassert.Equal(t, "IN_DOUBT", EffectStateOf("eff-1"))

	// Permissionless MarkInDoubt: an unrelated caller seals IN_DOUBT on-chain.
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendFee(0)
	doubtRes := MarkInDoubt(cross(cur), "eff-1")
	uassert.True(t, strings.HasPrefix(doubtRes, "eff-1|IN_DOUBT|"))

	// Open obligations & Render("obligations") show eff-1 with its cleanup owner and 1/3 steps.
	uassert.Equal(t, 1, OpenObligationsCount())
	obsPage := Render("obligations")
	uassert.True(t, strings.Contains(obsPage, "eff-1"))
	uassert.True(t, strings.Contains(obsPage, "deploy:aura-genesis-prod"))
	uassert.True(t, strings.Contains(obsPage, "IN_DOUBT"))
	uassert.True(t, strings.Contains(obsPage, agentOwner.String()))
	uassert.True(t, strings.Contains(obsPage, "1/3"))

	// -------------------------------------------------------------------------
	// Acceptance Test 2: Authorize again on the same effect key -> DENIED with open effect id.
	// -------------------------------------------------------------------------
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.AbortsContains(t, cur, "DENIED: effect key fenced by open effect eff-1", func() {
		BeginEffect(
			cross(cur),
			"worker-effects-1",
			"deploy:aura-genesis-prod",
			"idem-deploy-002",
			"COMPENSABLE",
			agentOwner.String(),
			"live deploy sha matches build artifact",
			"restore previous netlify deploy",
			"",
			3,
			runtime.ChainHeight()+10,
		)
	})

	// -------------------------------------------------------------------------
	// Acceptance Test 3: Run compensation with read-back confirming restored state.
	// -------------------------------------------------------------------------
	// Missing/zero readback or restoredOriginalState=false MUST fail closed.
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.AbortsContains(t, cur, "COMPENSATED requires non-zero read-back", func() {
		Compensate(cross(cur), "eff-1", "comp-001", zeroRoot, true)
	})
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.AbortsContains(t, cur, "COMPENSATED requires non-zero read-back", func() {
		Compensate(cross(cur), "eff-1", "comp-001", restoredDig, false)
	})

	// Valid compensation seals linked effect eff-2, marks eff-1 COMPENSATED, and clears fence.
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	compRes := Compensate(cross(cur), "eff-1", "comp-001", restoredDig, true)
	uassert.True(t, strings.HasPrefix(compRes, "eff-1|COMPENSATED|eff-2|"))
	uassert.Equal(t, "COMPENSATED", EffectStateOf("eff-1"))
	uassert.Equal(t, "COMMITTED", EffectStateOf("eff-2"))
	uassert.Equal(t, 0, OpenObligationsCount())
	uassert.Equal(t, 64, len(EffectLifecycleRootHex()))

	// -------------------------------------------------------------------------
	// Acceptance Test 4: IRREVERSIBLE effect with no prior human approval is DENIED at authorize.
	// -------------------------------------------------------------------------
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.AbortsContains(t, cur, "DENIED: IRREVERSIBLE effect requires prior human approval", func() {
		BeginEffect(
			cross(cur),
			"worker-effects-1",
			"email:customer-blast",
			"idem-email-001",
			"IRREVERSIBLE",
			agentOwner.String(),
			"resend message id delivered",
			"",
			"", // missing human approval!
			1,
			runtime.ChainHeight()+5,
		)
	})

	// With prior human approval it is authorized; if it finishes PARTIAL, only human AcceptPartial resolves it.
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	irrRes := BeginEffect(
		cross(cur),
		"worker-effects-1",
		"email:customer-blast",
		"idem-email-002",
		"IRREVERSIBLE",
		agentOwner.String(),
		"resend message id delivered",
		"",
		"human:gaetano:approval-20261124",
		2,
		runtime.ChainHeight()+5,
	)
	uassert.True(t, strings.HasPrefix(irrRes, "eff-3|STARTED|"))

	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	RecordStep(cross(cur), "eff-3", 1, "send-batch-1", stepDig1, true)
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	pClose := CloseEffect(cross(cur), "eff-3", "COMMITTED", committedDig, true)
	// Only 1 of 2 steps recorded -> downgraded to PARTIAL, never COMMITTED!
	uassert.True(t, strings.HasPrefix(pClose, "eff-3|PARTIAL|"))
	uassert.Equal(t, 1, OpenObligationsCount())

	// Auto-compensate is refused on IRREVERSIBLE; human AcceptPartial resolves & releases fence.
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.AbortsContains(t, cur, "IRREVERSIBLE effect cannot be automatically compensated", func() {
		Compensate(cross(cur), "eff-3", "comp-irr", restoredDig, true)
	})
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	accRes := AcceptPartial(cross(cur), "eff-3", "human:gaetano", reasonDig)
	uassert.True(t, strings.HasPrefix(accRes, "eff-3|ACCEPTED|"))
	uassert.Equal(t, 0, OpenObligationsCount())

	// -------------------------------------------------------------------------
	// Acceptance Test 5: Retry with the same idempotency key does not apply twice.
	// -------------------------------------------------------------------------
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	first := BeginEffect(
		cross(cur),
		"worker-effects-1",
		"deploy:aura-genesis-prod", // fence was released by COMPENSATED above
		"idem-retry-unique-1",
		"REVERSIBLE",
		agentOwner.String(),
		"config written and verified",
		"restore previous config",
		"",
		1,
		runtime.ChainHeight()+5,
	)
	uassert.True(t, strings.HasPrefix(first, "eff-4|STARTED|"))

	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	retry := BeginEffect(
		cross(cur),
		"worker-effects-1",
		"deploy:aura-genesis-prod",
		"idem-retry-unique-1",
		"REVERSIBLE",
		agentOwner.String(),
		"config written and verified",
		"restore previous config",
		"",
		1,
		runtime.ChainHeight()+5,
	)
	uassert.Equal(t, "eff-4|DEDUPLICATED|STARTED", retry)

	// Close eff-4 cleanly as COMMITTED with verified read-back and stateChanged=true.
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	RecordStep(cross(cur), "eff-4", 1, "write-config", stepDig1, true)
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	cOk := CloseEffect(cross(cur), "eff-4", "COMMITTED", committedDig, true)
	uassert.True(t, strings.HasPrefix(cOk, "eff-4|COMMITTED|"))

	// -------------------------------------------------------------------------
	// Acceptance Test 6: Step exits 0 and changed nothing -> closes as ABORTED, NEVER COMMITTED.
	// -------------------------------------------------------------------------
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	noopStart := BeginEffect(
		cross(cur),
		"worker-effects-1",
		"deploy:silent-noop",
		"idem-noop-1",
		"COMPENSABLE",
		agentOwner.String(),
		"live deploy sha updated",
		"rollback deploy",
		"",
		1,
		runtime.ChainHeight()+5,
	)
	uassert.True(t, strings.HasPrefix(noopStart, "eff-5|STARTED|"))

	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	RecordStep(cross(cur), "eff-5", 1, "deploy-waiter-exit-0", stepDig1, false)
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	noopClose := CloseEffect(cross(cur), "eff-5", "COMMITTED", "", false)
	uassert.True(t, strings.HasPrefix(noopClose, "eff-5|ABORTED|"))
	uassert.Equal(t, "ABORTED", EffectStateOf("eff-5"))
}
