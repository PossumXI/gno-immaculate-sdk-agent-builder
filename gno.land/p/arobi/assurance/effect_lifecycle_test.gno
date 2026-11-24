package assurance

import (
	"strings"
	"testing"
)

// All 6 acceptance tests from PARTIAL-EFFECT-GAPS.md verified against p/arobi/assurance EffectTracker.
func TestEffectLifecycleAllSixAcceptanceTests(t *testing.T) {
	tr := NewEffectTracker()

	// Builder refuses missing deadline, owner, or reversal class.
	if _, err := NewEffectSpec("agent-1", "deploy:prod", "idem-bad-1").WithSteps(3).Build(100); err == nil {
		t.Fatalf("expected builder refusal when postcondition/owner/deadline/reversal missing")
	}

	// Acceptance Test #4: IRREVERSIBLE effect with no prior human approval is DENIED at authorize.
	_, err := NewEffectSpec("agent-1", "wire:bank-tx", "idem-irrev-1").
		WithSteps(1).
		WithPostcondition("settlement receipt confirmed").
		WithReversal(ReversalIrreversible, "").
		WithDeadlineHeight(120).
		WithCleanupOwner("g1issuer").
		Build(100)
	if err == nil || !strings.Contains(err.Error(), "IRREVERSIBLE") {
		t.Fatalf("acceptance #4 failed: expected IRREVERSIBLE denial without human approval, got: %v", err)
	}

	// Acceptance Test #1: Stop executor between step 1 and step 2 of a 3-step action.
	// After deadline, effect reads IN_DOUBT with no call from executor, and open list shows owner + 1 receipt.
	spec1, err := NewEffectSpec("agent-1", "migrate:db-v2", "idem-mig-1").
		WithSteps(3).
		WithPostcondition("all 3 tables migrated").
		WithReversal(ReversalCompensable, "drop partial tables and restore snapshot").
		WithDeadlineHeight(110).
		WithCleanupOwner("g1grantissuer").
		Build(100)
	if err != nil {
		t.Fatalf("unexpected spec1 error: %v", err)
	}
	rec1, dedup, _, err := tr.BeginEffect(spec1, "executor-1", 100)
	if err != nil || dedup {
		t.Fatalf("BeginEffect failed: %v dedup=%v", err, dedup)
	}
	if _, _, err := tr.RecordStep(rec1.ID, 1, "alter-table-1", HashBytes([]byte("table1-ok")), true, "executor-1", 102); err != nil {
		t.Fatalf("RecordStep 1 failed: %v", err)
	}

	// Executor goes quiet; deadline height 110 passes -> OpenObligations sweeps without executor call.
	obligations := tr.OpenObligations(115)
	if len(obligations) != 1 {
		t.Fatalf("acceptance #1 failed: expected 1 open obligation, got %d", len(obligations))
	}
	if obligations[0].State != StateInDoubt || obligations[0].CleanupOwner != "g1grantissuer" || obligations[0].StepsRecorded != 1 {
		t.Fatalf("acceptance #1 mismatch: %+v", obligations[0])
	}

	// Acceptance Test #2: Authorize again on the same effect key while IN_DOUBT -> DENIED naming open effect id.
	specRetryDiffKey, err := NewEffectSpec("agent-1", "migrate:db-v2", "idem-mig-2").
		WithSteps(3).
		WithPostcondition("all 3 tables migrated").
		WithReversal(ReversalCompensable, "restore snapshot").
		WithDeadlineHeight(130).
		WithCleanupOwner("g1grantissuer").
		Build(116)
	if err != nil {
		t.Fatalf("unexpected specRetryDiffKey error: %v", err)
	}
	if _, _, _, err := tr.BeginEffect(specRetryDiffKey, "executor-2", 116); err == nil || !strings.Contains(err.Error(), rec1.ID) {
		t.Fatalf("acceptance #2 failed: expected denial carrying %s, got: %v", rec1.ID, err)
	}

	// Acceptance Test #5: Retry with the SAME idempotency key does not apply the effect twice.
	sameRec, wasDedup, _, err := tr.BeginEffect(spec1, "executor-1", 105)
	if err != nil || !wasDedup || sameRec.ID != rec1.ID {
		t.Fatalf("acceptance #5 failed: expected deduplicated %s, got id=%v dedup=%v err=%v", rec1.ID, sameRec, wasDedup, err)
	}

	// Acceptance Test #3: Run compensation with read-back showing restored state -> COMPENSATED + fence cleared.
	origAfter, compRec, _, err := tr.Compensate(rec1.ID, "idem-comp-1", HashBytes([]byte("snapshot-restored")), true, "g1grantissuer", 118)
	if err != nil {
		t.Fatalf("acceptance #3 failed: Compensate error: %v", err)
	}
	if origAfter.State != StateCompensated || compRec.SupersedesID != rec1.ID {
		t.Fatalf("acceptance #3 mismatch: orig=%s compSupersedes=%s", origAfter.State, compRec.SupersedesID)
	}
	if len(tr.OpenObligations(119)) != 0 {
		t.Fatalf("acceptance #3 failed: fence/obligation should be cleared after COMPENSATED")
	}

	// Acceptance Test #6: A step that exits 0 and changed nothing closes as ABORTED, never COMMITTED.
	specNoop, err := NewEffectSpec("agent-1", "deploy:site", "idem-noop-1").
		WithSteps(1).
		WithPostcondition("netlify published_deploy moved to new sha").
		WithReversal(ReversalCompensable, "restore previous deploy").
		WithDeadlineHeight(140).
		WithCleanupOwner("g1release").
		Build(120)
	if err != nil {
		t.Fatalf("unexpected specNoop error: %v", err)
	}
	recNoop, _, _, err := tr.BeginEffect(specNoop, "executor-3", 120)
	if err != nil {
		t.Fatalf("BeginEffect noop failed: %v", err)
	}
	if _, _, err := tr.RecordStep(recNoop.ID, 1, "deploy-script-exit-0", HashBytes([]byte("no-op")), false, "executor-3", 121); err != nil {
		t.Fatalf("RecordStep noop failed: %v", err)
	}
	closedNoop, _, err := tr.CloseEffect(recNoop.ID, StateCommitted, ZeroDigest(), false, "executor-3", 122)
	if err != nil {
		t.Fatalf("CloseEffect noop failed: %v", err)
	}
	if closedNoop.State != StateAborted {
		t.Fatalf("acceptance #6 failed: exit-0 no-op must close as ABORTED, got %s", closedNoop.State)
	}

	// Also verify permissionless MarkInDoubt by an unrelated third-party watcher after deadline.
	specWatch, _ := NewEffectSpec("agent-1", "sync:job", "idem-watch-1").
		WithSteps(2).
		WithPostcondition("sync done").
		WithReversal(ReversalReversible, "undo sync").
		WithDeadlineHeight(150).
		WithCleanupOwner("g1issuer").
		Build(130)
	recWatch, _, _, err := tr.BeginEffect(specWatch, "executor-4", 130)
	if err != nil {
		t.Fatalf("BeginEffect watch failed: %v", err)
	}
	if _, _, err := tr.MarkInDoubt(recWatch.ID, "g1randomwatcher", 149); err == nil {
		t.Fatalf("MarkInDoubt before deadline must fail")
	}
	marked, _, err := tr.MarkInDoubt(recWatch.ID, "g1randomwatcher", 150)
	if err != nil || marked.State != StateInDoubt {
		t.Fatalf("permissionless MarkInDoubt at deadline failed: %v", err)
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
		StepIndex:      0,
		TotalSteps:     3,
		Actor:          "g1owner",
		Owner:          "g1owner",
		ReversalClass:  ReversalCompensable,
		StateChanged:   false,
		ReadbackDigest: ZeroDigest(),
		SupersedesID:   "",
		HumanApproval:  "",
		DeadlineHeight: 110,
		Height:         100,
	}
	const wantGolden = "34a2d178d37aa8e5f952a774e5d872360ef361df689a9ed5b423601a5ff1122a"
	if got := Hex(goldenEv.LeafHash()); got != wantGolden {
		t.Fatalf("cross-language EffectEvent golden hash mismatch: got %s want %s", got, wantGolden)
	}
}
