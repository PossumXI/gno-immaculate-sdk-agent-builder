package effects

import (
	"chain/runtime"
	"strconv"
	"strings"
	"testing"

	sdk "gno.land/p/arobi/assurance"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/arobi/assurance"
)

var (
	ownerAddr   = testutils.TestAddress("effects-agent-owner")
	cleanupAddr  = testutils.TestAddress("fx-cleanup-owner")
	otherAddr    = testutils.TestAddress("effects-stranger")
	approverAddr = testutils.TestAddress("effects-approver")
)

// Each test calls testing.SetRealm(testing.NewUserRealm(...)) itself, right before the call it makes as that user:
// the realm SetRealm sets belongs to the frame that calls it, so a helper that set it would lose it on return.
const policyDigest = "1111111111111111111111111111111111111111111111111111111111111111"

// register mints a passport for agentID owned by ownerAddr. The call into the other realm is made from a crossing
// closure that first becomes the owner's user realm, as gno's own examples do, so the assurance realm sees a direct
// user call.
func register(cur realm, t *testing.T, agentID string) {
	uassert.NotPanics(t, cur, func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(ownerAddr))
		assurance.RegisterAgent(cross(cur), agentID, "Effects test agent", policyDigest, "")
	})
}

func idString(id uint64) string { return strconv.FormatUint(id, 10) }

// Rule: deadlines are the clock's. A quiet executor's effect reads IN_DOUBT past its deadline, its steps are refused
// under the old attempt, and the open list names its cleanup owner and the receipts that landed.
func TestQuietExecutorIsInDoubtByTheClock(cur realm, t *testing.T) {
	register(cur, t, "fx-quiet")
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginDemoEffect(cross(cur), "fx-quiet", "ledger:q", "q-1", 1, "COMPENSABLE", "restore the old values",
		"q1,q2,q3", "a,b,c", 5, cleanupAddr, 0)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	DemoStep(cross(cur), id, 1, 1, "a")
	testing.SkipHeights(6)
	uassert.Equal(t, "IN_DOUBT", EffectState(id))
	open := OpenEffects()
	uassert.True(t, strings.Contains(open, `"id":`+idString(id)), open)
	uassert.True(t, strings.Contains(open, `"cleanup_owner":"`+cleanupAddr.String()+`"`), open)
	uassert.True(t, strings.Contains(open, `"receipts":1`), open)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "passed its deadline height", func() { DemoStep(cross(cur), id, 1, 2, "b") })
	// Anyone may seal it, and that changes nothing but the state.
	before := DemoValue("q1")
	testing.SetRealm(testing.NewUserRealm(otherAddr))
	uassert.Equal(t, "IN_DOUBT", MarkInDoubt(cross(cur), id))
	uassert.Equal(t, before, DemoValue("q1"))
	uassert.Equal(t, "IN_DOUBT", VerifyEffect(id))
}

// Rule: one effect at a time per key; the refusal names the open effect.
func TestAKeyWithAnOpenEffectRefusesANewStart(cur realm, t *testing.T) {
	register(cur, t, "fx-fence")
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginDemoEffect(cross(cur), "fx-fence", "ledger:f", "f-1", 1, "COMPENSABLE", "restore", "f1", "x", 5, cleanupAddr, 0)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "has open effect "+idString(id), func() {
		BeginDemoEffect(cross(cur), "fx-fence", "ledger:f", "f-2", 1, "COMPENSABLE", "restore", "f1", "y", 5, cleanupAddr, 0)
	})
}

// Rule: "nothing seen" is IN_DOUBT until the effect is fenced; after the fence the same read-back is ABORTED, and a
// retry is then a new attempt.
func TestNothingSeenIsInDoubtUntilFenced(cur realm, t *testing.T) {
	register(cur, t, "fx-noop")
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginDemoEffect(cross(cur), "fx-noop", "ledger:n", "n-1", 1, "COMPENSABLE", "restore", "n1", "set", 10, cleanupAddr, 0)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	DemoStep(cross(cur), id, 1, 1, "") // the step "exits 0" and writes what was there
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.Equal(t, "IN_DOUBT", CloseDemoEffect(cross(cur), id, 1))
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	FenceEffect(cross(cur), id, 1)
	uassert.False(t, EffectLive(id, 1))
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.Equal(t, "ABORTED", CloseDemoEffect(cross(cur), id, 1))
	uassert.Equal(t, "ABORTED", VerifyEffect(id))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "attempt 2", func() {
		BeginDemoEffect(cross(cur), "fx-noop", "ledger:n", "n-1", 1, "COMPENSABLE", "restore", "n1", "set", 10, cleanupAddr, 0)
	})
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	retry := BeginDemoEffect(cross(cur), "fx-noop", "ledger:n", "n-1", 2, "COMPENSABLE", "restore", "n1", "set", 10, cleanupAddr, 0)
	uassert.True(t, retry != id)
	// A call that names the old attempt is refused on the new one.
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "a call for another attempt is refused", func() { DemoStep(cross(cur), retry, 1, 1, "set") })
}

// Rule: a close binds to its attempt and to a fresh read-back observed after the start.
func TestAnExternalCloseIsBoundToItsAttemptAndReadBack(cur realm, t *testing.T) {
	register(cur, t, "fx-ext")
	pre, post := sdk.Hex(sdk.HashString("before")), sdk.Hex(sdk.HashString("after"))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginEffect(cross(cur), "fx-ext", "deploy:site", "d-1", 1, 2, "COMPENSABLE", "redeploy the previous build",
		pre, post, true, 50, cleanupAddr, 0)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	RecordStep(cross(cur), id, 1, 1, sdk.Hex(sdk.HashString("upload")))
	now := runtime.ChainHeight()
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "another attempt", func() { CloseEffect(cross(cur), id, 2, post, now) })
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "observed after the last step", func() { CloseEffect(cross(cur), id, 1, post, now+5) })
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "read-back digest", func() { CloseEffect(cross(cur), id, 1, strings.Repeat("0", 64), now) })
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.Equal(t, "COMMITTED", CloseEffect(cross(cur), id, 1, post, now))
	uassert.Equal(t, "COMMITTED", VerifyEffect(id))
}

// Rule: IRREVERSIBLE is held at the start: without a recorded approval nothing is started and nothing is recorded.
// The approval comes from the agent's approver, another account than the owner who runs the effect, and is used once.
func TestIrreversibleNeedsARecordedApproval(cur realm, t *testing.T) {
	register(cur, t, "fx-irr")
	count := EffectCount()
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "human approval", func() {
		BeginDemoEffect(cross(cur), "fx-irr", "mail:all", "m-1", 1, "IRREVERSIBLE", "", "m1", "sent", 5, cleanupAddr, 0)
	})
	uassert.Equal(t, count, EffectCount())
	// The owner cannot approve its own effects, nor name itself as the approver.
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "approver (SetApprover)", func() { ApproveEffect(cross(cur), "fx-irr", "mail:all", DemoDigest("m1", "sent")) })
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "other than the agent's owner", func() { SetApprover(cross(cur), "fx-irr", ownerAddr) })
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	SetApprover(cross(cur), "fx-irr", approverAddr)
	testing.SetRealm(testing.NewUserRealm(approverAddr))
	appr := ApproveEffect(cross(cur), "fx-irr", "mail:all", DemoDigest("m1", "sent"))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginDemoEffect(cross(cur), "fx-irr", "mail:all", "m-1", 1, "IRREVERSIBLE", "", "m1", "sent", 5, cleanupAddr, appr)
	uassert.Equal(t, count+1, EffectCount())
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	DemoStep(cross(cur), id, 1, 1, "sent")
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.Equal(t, "COMMITTED", CloseDemoEffect(cross(cur), id, 1))
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.AbortsContains(t, cur, "IRREVERSIBLE", func() { CompensateDemo(cross(cur), id, 5) })
}

// Rule: a retry with the same idempotency key never applies twice.
func TestARetryOfACommittedEffectIsNotAppliedAgain(cur realm, t *testing.T) {
	register(cur, t, "fx-idem")
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginDemoEffect(cross(cur), "fx-idem", "ledger:i", "i-1", 1, "COMPENSABLE", "restore", "i1", "paid", 5, cleanupAddr, 0)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	DemoStep(cross(cur), id, 1, 1, "paid")
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.Equal(t, "COMMITTED", CloseDemoEffect(cross(cur), id, 1))
	count := EffectCount()
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	again := BeginDemoEffect(cross(cur), "fx-idem", "ledger:i", "i-1", 1, "COMPENSABLE", "restore", "i1", "paid", 5, cleanupAddr, 0)
	uassert.Equal(t, id, again)
	uassert.Equal(t, count, EffectCount())
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "is COMMITTED", func() { DemoStep(cross(cur), again, 1, 1, "paid") })
}

// Rules: compensation is its own effect, bounded, refused while paused; the original reads COMPENSATED only when
// the compensation's read-back shows the pre-state.
func TestCompensationIsBoundedAndHeldWhilePaused(cur realm, t *testing.T) {
	register(cur, t, "fx-comp")
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginDemoEffect(cross(cur), "fx-comp", "ledger:c", "c-1", 1, "COMPENSABLE", "restore", "c1,c2", "x,y", 5, cleanupAddr, 0)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	DemoStep(cross(cur), id, 1, 1, "x")
	testing.SkipHeights(6)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	PauseEffects(cross(cur), "fx-comp")
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.AbortsContains(t, cur, "paused", func() { CompensateDemo(cross(cur), id, 5) })
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	ResumeEffects(cross(cur), "fx-comp")
	testing.SetRealm(testing.NewUserRealm(otherAddr))
	uassert.AbortsContains(t, cur, "cleanup owner", func() { CompensateDemo(cross(cur), id, 5) })
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	comp := CompensateDemo(cross(cur), id, 5)
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	DemoStep(cross(cur), comp, 1, 1, "")
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	DemoStep(cross(cur), comp, 1, 2, "")
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.Equal(t, "COMMITTED", CloseDemoEffect(cross(cur), comp, 1))
	uassert.Equal(t, "COMPENSATED", EffectState(id))
	uassert.Equal(t, "", DemoValue("c1"))
	uassert.Equal(t, "COMPENSATED", VerifyEffect(id))
	uassert.Equal(t, "COMMITTED", VerifyEffect(comp))
}

// Rule 9: against a downstream that does not honour EffectLive, neither a fence nor the clock proves "no effect". A
// pre-state read-back stays IN_DOUBT, an acceptance keeps the key held, and the undo needs the approver.
func TestALandableEffectStaysInDoubtAndHoldsItsKey(cur realm, t *testing.T) {
	register(cur, t, "fx-land")
	pre, post := sdk.Hex(sdk.HashString("before")), sdk.Hex(sdk.HashString("after"))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginEffect(cross(cur), "fx-land", "mail:list", "l-1", 1, 1, "COMPENSABLE", "send a correction",
		pre, post, false, 50, cleanupAddr, 0)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	RecordStep(cross(cur), id, 1, 1, sdk.Hex(sdk.HashString("queued")))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	FenceEffect(cross(cur), id, 1)
	testing.SkipHeights(1)
	now := runtime.ChainHeight()
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.Equal(t, "IN_DOUBT", CloseEffect(cross(cur), id, 1, pre, now))
	uassert.Equal(t, "IN_DOUBT", VerifyEffect(id))
	// The undo now needs the approver's approval for this key, with the original's pre-state as its postcondition.
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.AbortsContains(t, cur, "needs ApproveEffect", func() { Compensate(cross(cur), id, 1, post, 20, 0) })
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	SetApprover(cross(cur), "fx-land", approverAddr)
	testing.SetRealm(testing.NewUserRealm(approverAddr))
	appr := ApproveEffect(cross(cur), "fx-land", "mail:list", pre)
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	comp := Compensate(cross(cur), id, 1, post, 20, appr)
	uassert.True(t, strings.Contains(EffectJSON(id), `"link":`+idString(comp)))
	uassert.Equal(t, "IN_DOUBT", VerifyEffect(id))
	// The compensation fails (its read-back is neither state). The original is not accepted while that failed
	// compensation is open; a person accepts the compensation's outcome first, then the original's.
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	RecordStep(cross(cur), comp, 1, 1, sdk.Hex(sdk.HashString("correction queued")))
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.Equal(t, "PARTIAL", CloseEffect(cross(cur), comp, 1, sdk.Hex(sdk.HashString("half")), runtime.ChainHeight()))
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.AbortsContains(t, cur, "running", func() { AcceptEffect(cross(cur), id, sdk.Hex(sdk.HashString("reviewed by a person"))) })
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	AcceptEffect(cross(cur), comp, sdk.Hex(sdk.HashString("reviewed by a person")))
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	AcceptEffect(cross(cur), id, sdk.Hex(sdk.HashString("reviewed by a person")))
	uassert.Equal(t, "ACCEPTED", EffectState(id))
	// Accepted, yet it may still land: the key stays held.
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "may still land", func() {
		BeginEffect(cross(cur), "fx-land", "mail:list", "l-2", 1, 1, "COMPENSABLE", "send a correction", pre, post, false, 50, cleanupAddr, 0)
	})
	// Only the approver frees it, and only against the downstream's record that the attempt will not land.
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.AbortsContains(t, cur, "approver releases", func() { ReleaseKey(cross(cur), id, sdk.Hex(sdk.HashString("list says no"))) })
	testing.SetRealm(testing.NewUserRealm(approverAddr))
	uassert.AbortsContains(t, cur, "downstream's record", func() { ReleaseKey(cross(cur), id, strings.Repeat("0", 64)) })
	testing.SetRealm(testing.NewUserRealm(approverAddr))
	ReleaseKey(cross(cur), id, sdk.Hex(sdk.HashString("mail list: attempt 1 of l-1 refused")))
	uassert.Equal(t, "ACCEPTED", VerifyEffect(id))
	testing.SetRealm(testing.NewUserRealm(approverAddr))
	uassert.AbortsContains(t, cur, "holds no key", func() { ReleaseKey(cross(cur), id, sdk.Hex(sdk.HashString("again"))) })
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	next := BeginEffect(cross(cur), "fx-land", "mail:list", "l-2", 1, 1, "COMPENSABLE", "send a correction", pre, post, false, 50, cleanupAddr, 0)
	uassert.True(t, next > id)
}

// An undone effect that may still land keeps its key too, until the approver releases it.
func TestACompensatedLandableEffectHoldsItsKeyUntilReleased(cur realm, t *testing.T) {
	register(cur, t, "fx-undo")
	pre, post := sdk.Hex(sdk.HashString("before")), sdk.Hex(sdk.HashString("after"))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginEffect(cross(cur), "fx-undo", "wire:7", "w-1", 1, 1, "COMPENSABLE", "send it back", pre, post, false, 3, cleanupAddr, 0)
	testing.SkipHeights(4)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	SetApprover(cross(cur), "fx-undo", approverAddr)
	testing.SetRealm(testing.NewUserRealm(approverAddr))
	appr := ApproveEffect(cross(cur), "fx-undo", "wire:7", pre)
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	comp := Compensate(cross(cur), id, 1, post, 10, appr)
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	RecordStep(cross(cur), comp, 1, 1, sdk.Hex(sdk.HashString("returned")))
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.Equal(t, "COMMITTED", CloseEffect(cross(cur), comp, 1, pre, runtime.ChainHeight()))
	uassert.Equal(t, "COMPENSATED", EffectState(id))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "may still land", func() {
		BeginEffect(cross(cur), "fx-undo", "wire:7", "w-2", 1, 1, "COMPENSABLE", "send it back", pre, post, false, 3, cleanupAddr, 0)
	})
	testing.SetRealm(testing.NewUserRealm(approverAddr))
	ReleaseKey(cross(cur), id, sdk.Hex(sdk.HashString("bank: wire 7 attempt 1 expired unused")))
	uassert.Equal(t, "COMPENSATED", VerifyEffect(id))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	next := BeginEffect(cross(cur), "fx-undo", "wire:7", "w-2", 1, 1, "COMPENSABLE", "send it back", pre, post, false, 3, cleanupAddr, 0)
	uassert.True(t, next > comp)
}

// Every SetApprover starts a new epoch: naming the same account again does not revive its older approvals.
func TestAnApprovalFromAnEarlierApproverEpochIsVoid(cur realm, t *testing.T) {
	register(cur, t, "fx-epoch")
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	SetApprover(cross(cur), "fx-epoch", approverAddr)
	testing.SetRealm(testing.NewUserRealm(approverAddr))
	old := ApproveEffect(cross(cur), "fx-epoch", "mail:all", DemoDigest("e1", "sent"))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	SetApprover(cross(cur), "fx-epoch", otherAddr)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	SetApprover(cross(cur), "fx-epoch", approverAddr)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.AbortsContains(t, cur, "current approver", func() {
		BeginDemoEffect(cross(cur), "fx-epoch", "mail:all", "e-1", 1, "IRREVERSIBLE", "", "e1", "sent", 5, cleanupAddr, old)
	})
	testing.SetRealm(testing.NewUserRealm(approverAddr))
	fresh := ApproveEffect(cross(cur), "fx-epoch", "mail:all", DemoDigest("e1", "sent"))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginDemoEffect(cross(cur), "fx-epoch", "mail:all", "e-1", 1, "IRREVERSIBLE", "", "e1", "sent", 5, cleanupAddr, fresh)
	uassert.True(t, id > 0)
}

// The same against a downstream that honours EffectLive: after the fence the pre-state read-back is ABORTED, and the
// key is free again.
func TestAHonouringDownstreamMakesAFencedNoEffectAborted(cur realm, t *testing.T) {
	register(cur, t, "fx-live")
	pre, post := sdk.Hex(sdk.HashString("before")), sdk.Hex(sdk.HashString("after"))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginEffect(cross(cur), "fx-live", "site:docs", "s-1", 1, 1, "COMPENSABLE", "redeploy", pre, post, true, 50, cleanupAddr, 0)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	FenceEffect(cross(cur), id, 1)
	testing.SkipHeights(1)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	uassert.Equal(t, "ABORTED", CloseEffect(cross(cur), id, 1, pre, runtime.ChainHeight()))
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	again := BeginEffect(cross(cur), "fx-live", "site:docs", "s-1", 2, 1, "COMPENSABLE", "redeploy", pre, post, true, 50, cleanupAddr, 0)
	uassert.True(t, again != id)
}

// ACCEPTED: an IN_DOUBT effect is fenced before a person accepts it, and nothing is accepted while its compensation
// runs.
func TestAcceptNeedsAFenceAndNoRunningCompensation(cur realm, t *testing.T) {
	register(cur, t, "fx-acc")
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := BeginDemoEffect(cross(cur), "fx-acc", "ledger:acc", "acc-1", 1, "COMPENSABLE", "restore", "acc1", "x", 3, cleanupAddr, 0)
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	DemoStep(cross(cur), id, 1, 1, "x")
	testing.SkipHeights(4)
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.AbortsContains(t, cur, "FenceEffect first", func() { AcceptEffect(cross(cur), id, sdk.Hex(sdk.HashString("ok"))) })
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	FenceEffect(cross(cur), id, 1)
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	comp := CompensateDemo(cross(cur), id, 5)
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.AbortsContains(t, cur, "running", func() { AcceptEffect(cross(cur), id, sdk.Hex(sdk.HashString("ok"))) })
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	DemoStep(cross(cur), comp, 1, 1, "")
	testing.SetRealm(testing.NewUserRealm(cleanupAddr))
	uassert.Equal(t, "COMMITTED", CloseDemoEffect(cross(cur), comp, 1))
	uassert.Equal(t, "COMPENSATED", EffectState(id))
	uassert.Equal(t, "COMPENSATED", VerifyEffect(id))
}
