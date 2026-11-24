package assurance

import (
	"strings"
	"testing"
)

// Verifies all 6 acceptance tests from PARTIAL-EFFECT-GAPS.md AND all 8 rules from
// PARTIAL-EFFECT-REVIEW-CHECKLIST.md against gno.land/p/arobi/assurance EffectTracker.
func TestEffectLifecycleAllSixAcceptanceTests(t *testing.T) {
	tr := NewEffectTracker()

	// Builder refuses missing deadline, owner, or reversal class.
	if _, err := NewEffectSpec("agent-1", "deploy:prod", "idem-bad-1").WithSteps(3).Build(100); err == nil {
		t.Fatalf("expected builder refusal when postcondition/owner/deadline/reversal missing")
	}

	// Rule 8 / Acceptance Test #4: IRREVERSIBLE with no prior human approval is DENIED at authorize,
	// leaving ZERO STARTED record and ZERO events.
	beforeEffs := tr.EffectCount()
	beforeEvs := tr.EventCount()
	if _, _, _, err := tr.BeginEffect(EffectSpec{
		AgentID:        "agent-1",
		EffectKey:      "wire:bank-tx",
		IdempotencyKey: "idem-irrev-1",
		TotalSteps:     1,
		Postcondition:  "settlement receipt confirmed",
		ReversalClass:  ReversalIrreversible,
		DeadlineHeight: 120,
		CleanupOwner:   "g1issuer",
	}, "executor-1", 100); err == nil || !strings.Contains(err.Error(), "IRREVERSIBLE") {
		t.Fatalf("rule 8 / acceptance #4 failed: expected IRREVERSIBLE denial, got: %v", err)
	}
	if tr.EffectCount() != beforeEffs || tr.EventCount() != beforeEvs {
		t.Fatalf("rule 8 failed: held IRREVERSIBLE authorize must leave no STARTED record")
	}

	// Acceptance Test #1: Stop executor between step 1 and step 2 of a 3-step action.
	spec1, err := NewEffectSpec("agent-1", "migrate:db-v2", "idem-mig-1").
		WithSteps(3).
		WithPostcondition("all 3 tables migrated").
		WithReversal(ReversalCompensable, "drop partial tables and restore snapshot").
		WithDeadlineHeight(110).
		WithCleanupOwner("g1grantissuer").
		WithMaxRecoveryAttempts(2).
		Build(100)
	if err != nil {
		t.Fatalf("unexpected spec1 error: %v", err)
	}
	rec1, dedup, _, err := tr.BeginEffect(spec1, "executor-1", 100)
	if err != nil || dedup {
		t.Fatalf("BeginEffect failed: %v dedup=%v", err, dedup)
	}
	if _, _, err := tr.RecordStep(rec1.ID, rec1.Attempt, rec1.LeaseToken, 1, "alter-table-1", HashBytes([]byte("table1-ok")), true, "executor-1", 102); err != nil {
		t.Fatalf("RecordStep 1 failed: %v", err)
	}

	// Rule 3 (Attempt fencing): stale attempt number or stale lease token is REFUSED.
	if _, _, err := tr.RecordStep(rec1.ID, rec1.Attempt+1, rec1.LeaseToken, 2, "stale-attempt", HashBytes([]byte("x")), true, "executor-1", 103); err == nil || !strings.Contains(err.Error(), "stale attempt") {
		t.Fatalf("rule 3 failed: expected stale attempt rejection, got %v", err)
	}
	if _, _, err := tr.RecordStep(rec1.ID, rec1.Attempt, HashBytes([]byte("wrong-lease")), 2, "stale-lease", HashBytes([]byte("x")), true, "executor-1", 103); err == nil || !strings.Contains(err.Error(), "stale attempt") {
		t.Fatalf("rule 3 failed: expected stale lease rejection, got %v", err)
	}

	// Rule 2 (Close binds to attempt & observation freshness): readback observed before start or too old is REFUSED.
	if _, _, err := tr.CloseEffect(rec1.ID, rec1.Attempt, rec1.LeaseToken, StateCommitted, HashBytes([]byte("old-readback")), 99, ZeroDigest(), true, "executor-1", 104); err == nil || !strings.Contains(err.Error(), "before effect started") {
		t.Fatalf("rule 2 failed: expected pre-start observation rejection, got %v", err)
	}
	if _, _, err := tr.CloseEffect(rec1.ID, rec1.Attempt, rec1.LeaseToken, StateCommitted, HashBytes([]byte("stale-readback")), 100, ZeroDigest(), true, "executor-1", 115); err == nil || !strings.Contains(err.Error(), "older than allowed age") {
		t.Fatalf("rule 2 failed: expected stale observation rejection, got %v", err)
	}

	// Rule 5 / Acceptance Test #1: Deadline height 110 passes -> IN_DOUBT without executor call;
	// expired start can NO LONGER record a step under the old attempt.
	obligations := tr.OpenObligations(115)
	if len(obligations) != 1 || obligations[0].State != StateInDoubt || obligations[0].CleanupOwner != "g1grantissuer" || obligations[0].StepsRecorded != 1 {
		t.Fatalf("acceptance #1 mismatch: %+v", obligations)
	}
	if _, _, err := tr.RecordStep(rec1.ID, rec1.Attempt, rec1.LeaseToken, 2, "late-step", HashBytes([]byte("late")), true, "executor-1", 115); err == nil {
		t.Fatalf("rule 5 failed: expired IN_DOUBT effect must refuse late step receipt")
	}

	// Acceptance Test #2: Authorize again on the same effect key while IN_DOUBT -> DENIED carrying rec1.ID.
	specRetryDiffKey, _ := NewEffectSpec("agent-1", "migrate:db-v2", "idem-mig-2").
		WithSteps(3).
		WithPostcondition("all 3 tables migrated").
		WithReversal(ReversalCompensable, "restore snapshot").
		WithDeadlineHeight(130).
		WithCleanupOwner("g1grantissuer").
		Build(116)
	if _, _, _, err := tr.BeginEffect(specRetryDiffKey, "executor-2", 116); err == nil || !strings.Contains(err.Error(), rec1.ID) {
		t.Fatalf("acceptance #2 failed: expected denial carrying %s, got: %v", rec1.ID, err)
	}

	// Acceptance Test #5: Retry with the SAME idempotency key does not apply twice.
	sameRec, wasDedup, _, err := tr.BeginEffect(spec1, "executor-1", 105)
	if err != nil || !wasDedup || sameRec.ID != rec1.ID {
		t.Fatalf("acceptance #5 failed: expected deduplicated %s, got id=%v dedup=%v err=%v", rec1.ID, sameRec, wasDedup, err)
	}

	// Rule 4: No reversal while paused.
	tr.SetAgentPaused("agent-1", true)
	if _, _, _, err := tr.Compensate(rec1.ID, "idem-comp-paused", HashBytes([]byte("restored")), 118, true, 125, "g1grantissuer", 118); err == nil || !strings.Contains(err.Error(), "paused") {
		t.Fatalf("rule 4 failed: compensation must be blocked while agent paused, got %v", err)
	}
	tr.SetAgentPaused("agent-1", false)

	// Rule 6 (Bounded recovery): failed recovery transitions its own compensation effect to IN_DOUBT (never loops).
	_, failedComp, _, err := tr.Compensate(rec1.ID, "idem-comp-fail-1", ZeroDigest(), 118, false, 125, "g1grantissuer", 118)
	if err == nil || failedComp == nil || failedComp.State != StateInDoubt || rec1.RecoveryAttempts != 1 {
		t.Fatalf("rule 6 failed: failed compensation must mark recovery IN_DOUBT and consume 1 attempt; comp=%+v err=%v", failedComp, err)
	}

	// Acceptance Test #3: Second recovery attempt succeeds with fresh restored read-back -> COMPENSATED + fence cleared.
	origAfter, compRec, _, err := tr.Compensate(rec1.ID, "idem-comp-ok", HashBytes([]byte("snapshot-restored")), 119, true, 126, "g1grantissuer", 119)
	if err != nil || origAfter.State != StateCompensated || compRec.SupersedesID != rec1.ID {
		t.Fatalf("acceptance #3 failed: orig=%+v comp=%+v err=%v", origAfter, compRec, err)
	}
	if len(tr.OpenObligations(120)) != 0 {
		t.Fatalf("acceptance #3 failed: obligation should be cleared after COMPENSATED")
	}

	// Rule 6 cap check: exceeding MaxRecoveryAttempts refuses further automated compensation.
	specCap, _ := NewEffectSpec("agent-1", "cap:test", "idem-cap-1").
		WithSteps(1).
		WithPostcondition("done").
		WithReversal(ReversalCompensable, "undo").
		WithDeadlineHeight(125).
		WithCleanupOwner("g1grantissuer").
		WithMaxRecoveryAttempts(1).
		Build(120)
	recCap, _, _, _ := tr.BeginEffect(specCap, "exec", 120)
	tr.MarkInDoubt(recCap.ID, "watcher", 126)
	_, _, _, _ = tr.Compensate(recCap.ID, "cap-fail-1", ZeroDigest(), 126, false, 130, "g1grantissuer", 126)
	if _, _, _, err := tr.Compensate(recCap.ID, "cap-fail-2", HashBytes([]byte("restored")), 127, true, 132, "g1grantissuer", 127); err == nil || !strings.Contains(err.Error(), "recovery attempt limit exceeded") {
		t.Fatalf("rule 6 cap failed: expected recovery limit exceeded, got %v", err)
	}
	// Resolve recCap cleanly with human AcceptPartial so obligations return to 0.
	if _, _, err := tr.AcceptPartial(recCap.ID, "human:gaetano", HashBytes([]byte("reviewed")), 128); err != nil {
		t.Fatalf("AcceptPartial failed: %v", err)
	}

	// Rule 1 + Acceptance Test #6 (BOTH HALVES):
	// Half A: Exit 0 + changed nothing + UNFENCED closes as IN_DOUBT (never ABORTED, never COMMITTED).
	// Half B: Once grant/sink fenceDigest proves the authorization cannot land later, closes as ABORTED.
	specNoop, _ := NewEffectSpec("agent-1", "deploy:site", "idem-noop-1").
		WithSteps(1).
		WithPostcondition("netlify published_deploy moved to new sha").
		WithReversal(ReversalCompensable, "restore previous deploy").
		WithDeadlineHeight(140).
		WithCleanupOwner("g1release").
		Build(130)
	recNoop, _, _, err := tr.BeginEffect(specNoop, "executor-3", 130)
	if err != nil {
		t.Fatalf("BeginEffect noop failed: %v", err)
	}
	if _, _, err := tr.RecordStep(recNoop.ID, recNoop.Attempt, recNoop.LeaseToken, 1, "deploy-script-exit-0", HashBytes([]byte("no-op")), false, "executor-3", 131); err != nil {
		t.Fatalf("RecordStep noop failed: %v", err)
	}
	unfencedClose, _, err := tr.CloseEffect(recNoop.ID, recNoop.Attempt, recNoop.LeaseToken, StateCommitted, ZeroDigest(), 132, ZeroDigest(), false, "executor-3", 132)
	if err != nil || unfencedClose.State != StateInDoubt {
		t.Fatalf("rule 1 / acceptance #6 half-A failed: unfenced exit-0 no-op must be IN_DOUBT, got state=%s err=%v", unfencedClose.State, err)
	}
	fencedClose, _, err := tr.CloseEffect(recNoop.ID, recNoop.Attempt, recNoop.LeaseToken, StateCommitted, ZeroDigest(), 133, HashBytes([]byte("grant-expired-unused")), false, "executor-3", 133)
	if err != nil || fencedClose.State != StateAborted {
		t.Fatalf("rule 1 / acceptance #6 half-B failed: fenced exit-0 no-op must close as ABORTED, got state=%s err=%v", fencedClose.State, err)
	}

	// Cross-language golden parity vector: must match verifier/verify-evidence.mjs effectEventLeafHash() bit-for-bit.
	goldenEv := EffectEvent{
		Seq:            1,
		PrevHash:       ZeroDigest(),
		EffectID:       "eff-1",
		EffectKey:      "deploy:prod",
		IdempotencyKey: "idem-1",
		Kind:           "START",
		State:          StateStarted,
		Attempt:        1,
		StepIndex:      0,
		TotalSteps:     3,
		Actor:          "g1owner",
		Owner:          "g1owner",
		ReversalClass:  ReversalCompensable,
		StateChanged:   false,
		ReadbackDigest: ZeroDigest(),
		FenceDigest:    ZeroDigest(),
		ObservedHeight: 0,
		SupersedesID:   "",
		HumanApproval:  "",
		DeadlineHeight: 110,
		Height:         100,
	}
	const wantGolden = "1a8fd81abfd1ee3782b809aa560f61d9ea84b974c6ed1d1aa5289c2a0239610f"
	if got := Hex(goldenEv.LeafHash()); got != wantGolden {
		t.Fatalf("cross-language EffectEvent golden hash mismatch: got %s want %s", got, wantGolden)
	}
}
