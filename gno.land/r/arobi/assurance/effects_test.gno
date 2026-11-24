package assurance

import (
	"chain/runtime"
	"strings"
	"testing"

	sdk "gno.land/p/arobi/assurance"
	"gno.land/p/nt/uassert/v0"
)

const (
	stepDig1     = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	restoredDig  = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	committedDig = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
	reasonDig    = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
	fenceDig     = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
	wrongLease   = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
)

func resetRealmWithEffects() {
	resetRealm()
	effectTracker = sdk.NewEffectTracker()
}

func parseBegin(res string) (id string, lease string) {
	parts := strings.Split(res, "|")
	return parts[0], parts[3]
}

func TestEffectLifecycleAllSixAcceptanceCriteriaAndChecklist(cur realm, t *testing.T) {
	resetRealmWithEffects()

	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	RegisterAgent(cross(cur), "worker-effects-1", "Effects Worker", policyDig1, "https://aura-genesis.org")

	// -------------------------------------------------------------------------
	// Acceptance Test 1 & Rule 3 / Rule 5:
	// Start 3-step effect, record step 1, verify stale attempt/lease refused,
	// stop executor, advance height past deadline -> IN_DOUBT by clock +
	// permissionless MarkInDoubt + late step refused + Render("obligations").
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
		"",
		"live deploy sha matches build artifact",
		"restore previous netlify deploy",
		"",
		3,
		deadline1,
	)
	uassert.True(t, strings.HasPrefix(res1, "eff-1|STARTED|1|"))
	id1, lease1 := parseBegin(res1)

	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	s1 := RecordStep(cross(cur), id1, 1, lease1, 1, "upload-assets", stepDig1, true)
	uassert.True(t, strings.HasPrefix(s1, "eff-1|STEP|1|"))

	// Rule 3: stale attempt or stale lease token MUST abort.
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.AbortsContains(t, cur, "stale attempt", func() {
		RecordStep(cross(cur), id1, 2, lease1, 2, "stale-attempt", stepDig1, true)
	})
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.AbortsContains(t, cur, "stale attempt", func() {
		RecordStep(cross(cur), id1, 1, wrongLease, 2, "stale-lease", stepDig1, true)
	})

	// Rule 2: read-back observed before start MUST abort.
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.AbortsContains(t, cur, "before effect started", func() {
		CloseEffect(cross(cur), id1, 1, lease1, "COMMITTED", committedDig, startH-1, "", true)
	})

	// Before deadline, stranger cannot prematurely mark IN_DOUBT.
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendFee(0)
	uassert.AbortsContains(t, cur, "deadline height not yet reached", func() {
		MarkInDoubt(cross(cur), id1)
	})

	// Advance chain height past deadline.
	testing.SkipHeights(12)
	uassert.Equal(t, "IN_DOUBT", EffectStateOf(id1))

	// Permissionless MarkInDoubt by an unrelated caller seals IN_DOUBT on-chain.
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendFee(0)
	doubtRes := MarkInDoubt(cross(cur), id1)
	uassert.True(t, strings.HasPrefix(doubtRes, "eff-1|IN_DOUBT|"))

	// Rule 5: expired start can no longer record a step under the old attempt.
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.AbortsContains(t, cur, "cannot record step", func() {
		RecordStep(cross(cur), id1, 1, lease1, 2, "too-late", stepDig1, true)
	})

	uassert.Equal(t, 1, OpenObligationsCount())
	obsPage := Render("obligations")
	uassert.True(t, strings.Contains(obsPage, "eff-1"))
	uassert.True(t, strings.Contains(obsPage, "deploy:aura-genesis-prod"))
	uassert.True(t, strings.Contains(obsPage, "IN_DOUBT"))
	uassert.True(t, strings.Contains(obsPage, agentOwner.String()))
	uassert.True(t, strings.Contains(obsPage, "1/3"))

	// -------------------------------------------------------------------------
	// Acceptance Test 2: Authorize again on same effect key -> DENIED carrying eff-1.
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
	// Rule 4 & Acceptance Test 3:
	// No reversal while paused; once active, valid compensation seals linked
	// reversal effect, marks eff-1 COMPENSATED, and clears fence.
	// -------------------------------------------------------------------------
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.Equal(t, "worker-effects-1|PAUSED", PauseAgentEffects(cross(cur), "worker-effects-1", true))
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.AbortsContains(t, cur, "paused", func() {
		Compensate(cross(cur), id1, "comp-paused", restoredDig, runtime.ChainHeight(), true, runtime.ChainHeight()+5)
	})
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.Equal(t, "worker-effects-1|ACTIVE", PauseAgentEffects(cross(cur), "worker-effects-1", false))

	// Valid compensation with fresh restored read-back succeeds.
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	compRes := Compensate(cross(cur), id1, "comp-001", restoredDig, runtime.ChainHeight(), true, runtime.ChainHeight()+5)
	uassert.True(t, strings.HasPrefix(compRes, "eff-1|COMPENSATED|eff-2|"))
	uassert.Equal(t, "COMPENSATED", EffectStateOf("eff-1"))
	uassert.Equal(t, "COMMITTED", EffectStateOf("eff-2"))
	uassert.Equal(t, 0, OpenObligationsCount())
	uassert.Equal(t, 64, len(EffectLifecycleRootHex()))

	// -------------------------------------------------------------------------
	// Acceptance Test 4 & Rule 8: IRREVERSIBLE without prior human approval is DENIED,
	// leaving no STARTED record.
	// -------------------------------------------------------------------------
	evCountBefore := effectTracker.EventCount()
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
			"",
			1,
			runtime.ChainHeight()+5,
		)
	})
	uassert.Equal(t, evCountBefore, effectTracker.EventCount())

	// -------------------------------------------------------------------------
	// Acceptance Test 5: Retry with same idempotency key does not apply twice.
	// -------------------------------------------------------------------------
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	first := BeginEffect(
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
	uassert.True(t, strings.HasPrefix(first, "eff-3|STARTED|1|"))
	id3, lease3 := parseBegin(first)

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
	uassert.Equal(t, "eff-3|DEDUPLICATED|STARTED", retry)

	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	RecordStep(cross(cur), id3, 1, lease3, 1, "write-config", stepDig1, true)
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	cOk := CloseEffect(cross(cur), id3, 1, lease3, "COMMITTED", committedDig, runtime.ChainHeight(), "", true)
	uassert.True(t, strings.HasPrefix(cOk, "eff-3|COMMITTED|"))

	// -------------------------------------------------------------------------
	// Acceptance Test 6 & Rule 1 (BOTH HALVES):
	// Unfenced exit-0 no-op -> IN_DOUBT (never ABORTED); once fenced -> ABORTED.
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
	id4, lease4 := parseBegin(noopStart)

	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	RecordStep(cross(cur), id4, 1, lease4, 1, "deploy-waiter-exit-0", stepDig1, false)

	// Half A: unfenced -> IN_DOUBT (fence held!)
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	unfenced := CloseEffect(cross(cur), id4, 1, lease4, "COMMITTED", "", runtime.ChainHeight(), "", false)
	uassert.True(t, strings.HasPrefix(unfenced, "eff-4|IN_DOUBT|"))
	uassert.Equal(t, "IN_DOUBT", EffectStateOf(id4))

	// Half B: fenced -> ABORTED (never COMMITTED!)
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	fenced := CloseEffect(cross(cur), id4, 1, lease4, "COMMITTED", "", runtime.ChainHeight(), fenceDig, false)
	uassert.True(t, strings.HasPrefix(fenced, "eff-4|ABORTED|"))
	uassert.Equal(t, "ABORTED", EffectStateOf(id4))

	// Rule 4 (Revoked agent blocks compensation even from cleanupOwner).
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	revStart := BeginEffect(
		cross(cur),
		"worker-effects-1",
		"deploy:revoked-guard",
		"idem-rev-1",
		"COMPENSABLE",
		agentOwner.String(),
		"done",
		"undo",
		"",
		1,
		runtime.ChainHeight()+2,
	)
	id5, _ := parseBegin(revStart)
	testing.SkipHeights(4)
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendFee(0)
	MarkInDoubt(cross(cur), id5)
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	RevokeAgent(cross(cur), "worker-effects-1")
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	uassert.AbortsContains(t, cur, "revoked", func() {
		Compensate(cross(cur), id5, "comp-after-revoke", restoredDig, runtime.ChainHeight(), true, runtime.ChainHeight()+5)
	})
}
