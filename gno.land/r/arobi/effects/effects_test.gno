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
	cleanupAddr = testutils.TestAddress("effects-cleanup-owner")
	otherAddr   = testutils.TestAddress("effects-stranger")
)

const policyDigest = "1111111111111111111111111111111111111111111111111111111111111111"

func as(who address) { testing.SetRealm(testing.NewUserRealm(who)) }

// register mints a passport for agentID owned by ownerAddr.
func register(cur realm, agentID string) {
	as(ownerAddr)
	assurance.RegisterAgent(cross(cur), agentID, "Effects test agent", policyDigest, "")
}

func idString(id uint64) string { return strconv.FormatUint(id, 10) }

// Rule: deadlines are the clock's. A quiet executor's effect reads IN_DOUBT past its deadline, its steps are refused
// under the old attempt, and the open list names its cleanup owner and the receipts that landed.
func TestQuietExecutorIsInDoubtByTheClock(cur realm, t *testing.T) {
	register(cur, "fx-quiet")
	as(ownerAddr)
	id := BeginDemoEffect(cross(cur), "fx-quiet", "ledger:q", "q-1", 1, "COMPENSABLE", "restore the old values",
		"q1,q2,q3", "a,b,c", 5, cleanupAddr, 0)
	as(ownerAddr)
	DemoStep(cross(cur), id, 1, 1, "a")
	testing.SkipHeights(6)
	uassert.Equal(t, "IN_DOUBT", EffectState(id))
	open := OpenEffects()
	uassert.True(t, strings.Contains(open, `"id":`+idString(id)), open)
	uassert.True(t, strings.Contains(open, `"cleanup_owner":"`+cleanupAddr.String()+`"`), open)
	uassert.True(t, strings.Contains(open, `"receipts":1`), open)
	as(ownerAddr)
	uassert.AbortsContains(t, cur, "passed its deadline height", func() { DemoStep(cross(cur), id, 1, 2, "b") })
	// Anyone may seal it, and that changes nothing but the state.
	before := DemoValue("q1")
	as(otherAddr)
	uassert.Equal(t, "IN_DOUBT", MarkInDoubt(cross(cur), id))
	uassert.Equal(t, before, DemoValue("q1"))
	uassert.Equal(t, "IN_DOUBT", VerifyEffect(id))
}

// Rule: one effect at a time per key; the refusal names the open effect.
func TestAKeyWithAnOpenEffectRefusesANewStart(cur realm, t *testing.T) {
	register(cur, "fx-fence")
	as(ownerAddr)
	id := BeginDemoEffect(cross(cur), "fx-fence", "ledger:f", "f-1", 1, "COMPENSABLE", "restore", "f1", "x", 5, cleanupAddr, 0)
	as(ownerAddr)
	uassert.AbortsContains(t, cur, "has open effect "+idString(id), func() {
		BeginDemoEffect(cross(cur), "fx-fence", "ledger:f", "f-2", 1, "COMPENSABLE", "restore", "f1", "y", 5, cleanupAddr, 0)
	})
}

// Rule: "nothing seen" is IN_DOUBT until the effect is fenced; after the fence the same read-back is ABORTED, and a
// retry is then a new attempt.
func TestNothingSeenIsInDoubtUntilFenced(cur realm, t *testing.T) {
	register(cur, "fx-noop")
	as(ownerAddr)
	id := BeginDemoEffect(cross(cur), "fx-noop", "ledger:n", "n-1", 1, "COMPENSABLE", "restore", "n1", "set", 10, cleanupAddr, 0)
	as(ownerAddr)
	DemoStep(cross(cur), id, 1, 1, "") // the step "exits 0" and writes what was there
	as(ownerAddr)
	uassert.Equal(t, "IN_DOUBT", CloseDemoEffect(cross(cur), id, 1))
	as(cleanupAddr)
	FenceEffect(cross(cur), id, 1)
	uassert.False(t, EffectLive(id, 1))
	as(cleanupAddr)
	uassert.Equal(t, "ABORTED", CloseDemoEffect(cross(cur), id, 1))
	uassert.Equal(t, "ABORTED", VerifyEffect(id))
	as(ownerAddr)
	uassert.AbortsContains(t, cur, "attempt 2", func() {
		BeginDemoEffect(cross(cur), "fx-noop", "ledger:n", "n-1", 1, "COMPENSABLE", "restore", "n1", "set", 10, cleanupAddr, 0)
	})
	as(ownerAddr)
	retry := BeginDemoEffect(cross(cur), "fx-noop", "ledger:n", "n-1", 2, "COMPENSABLE", "restore", "n1", "set", 10, cleanupAddr, 0)
	uassert.True(t, retry != id)
	// A call that names the old attempt is refused on the new one.
	as(ownerAddr)
	uassert.AbortsContains(t, cur, "a call for another attempt is refused", func() { DemoStep(cross(cur), retry, 1, 1, "set") })
}

// Rule: a close binds to its attempt and to a fresh read-back observed after the start.
func TestAnExternalCloseIsBoundToItsAttemptAndReadBack(cur realm, t *testing.T) {
	register(cur, "fx-ext")
	pre, post := sdk.Hex(sdk.HashString("before")), sdk.Hex(sdk.HashString("after"))
	as(ownerAddr)
	id := BeginEffect(cross(cur), "fx-ext", "deploy:site", "d-1", 1, 2, "COMPENSABLE", "redeploy the previous build",
		pre, post, 50, cleanupAddr, 0)
	as(ownerAddr)
	RecordStep(cross(cur), id, 1, 1, sdk.Hex(sdk.HashString("upload")))
	now := runtime.ChainHeight()
	as(ownerAddr)
	uassert.AbortsContains(t, cur, "another attempt", func() { CloseEffect(cross(cur), id, 2, post, now) })
	as(ownerAddr)
	uassert.AbortsContains(t, cur, "observed after the last step", func() { CloseEffect(cross(cur), id, 1, post, now+5) })
	as(ownerAddr)
	uassert.AbortsContains(t, cur, "read-back digest", func() { CloseEffect(cross(cur), id, 1, strings.Repeat("0", 64), now) })
	as(ownerAddr)
	uassert.Equal(t, "COMMITTED", CloseEffect(cross(cur), id, 1, post, now))
	uassert.Equal(t, "COMMITTED", VerifyEffect(id))
}

// Rule: IRREVERSIBLE is held at the start: without the owner's recorded approval nothing is started and nothing is
// recorded; with it, the approval is used once.
func TestIrreversibleNeedsARecordedApproval(cur realm, t *testing.T) {
	register(cur, "fx-irr")
	count := EffectCount()
	as(ownerAddr)
	uassert.AbortsContains(t, cur, "human approval", func() {
		BeginDemoEffect(cross(cur), "fx-irr", "mail:all", "m-1", 1, "IRREVERSIBLE", "", "m1", "sent", 5, cleanupAddr, 0)
	})
	uassert.Equal(t, count, EffectCount())
	as(ownerAddr)
	appr := ApproveEffect(cross(cur), "fx-irr", "mail:all", DemoDigest("m1", "sent"))
	as(ownerAddr)
	id := BeginDemoEffect(cross(cur), "fx-irr", "mail:all", "m-1", 1, "IRREVERSIBLE", "", "m1", "sent", 5, cleanupAddr, appr)
	uassert.Equal(t, count+1, EffectCount())
	as(ownerAddr)
	DemoStep(cross(cur), id, 1, 1, "sent")
	as(ownerAddr)
	uassert.Equal(t, "COMMITTED", CloseDemoEffect(cross(cur), id, 1))
	as(cleanupAddr)
	uassert.AbortsContains(t, cur, "IRREVERSIBLE", func() { CompensateDemo(cross(cur), id, 5) })
}

// Rule: a retry with the same idempotency key never applies twice.
func TestARetryOfACommittedEffectIsNotAppliedAgain(cur realm, t *testing.T) {
	register(cur, "fx-idem")
	as(ownerAddr)
	id := BeginDemoEffect(cross(cur), "fx-idem", "ledger:i", "i-1", 1, "COMPENSABLE", "restore", "i1", "paid", 5, cleanupAddr, 0)
	as(ownerAddr)
	DemoStep(cross(cur), id, 1, 1, "paid")
	as(ownerAddr)
	uassert.Equal(t, "COMMITTED", CloseDemoEffect(cross(cur), id, 1))
	count := EffectCount()
	as(ownerAddr)
	again := BeginDemoEffect(cross(cur), "fx-idem", "ledger:i", "i-1", 1, "COMPENSABLE", "restore", "i1", "paid", 5, cleanupAddr, 0)
	uassert.Equal(t, id, again)
	uassert.Equal(t, count, EffectCount())
	as(ownerAddr)
	uassert.AbortsContains(t, cur, "is COMMITTED", func() { DemoStep(cross(cur), again, 1, 1, "paid") })
}

// Rules: compensation is its own effect, bounded, refused while paused; the original reads COMPENSATED only when
// the compensation's read-back shows the pre-state.
func TestCompensationIsBoundedAndHeldWhilePaused(cur realm, t *testing.T) {
	register(cur, "fx-comp")
	as(ownerAddr)
	id := BeginDemoEffect(cross(cur), "fx-comp", "ledger:c", "c-1", 1, "COMPENSABLE", "restore", "c1,c2", "x,y", 5, cleanupAddr, 0)
	as(ownerAddr)
	DemoStep(cross(cur), id, 1, 1, "x")
	testing.SkipHeights(6)
	as(ownerAddr)
	PauseEffects(cross(cur), "fx-comp")
	as(cleanupAddr)
	uassert.AbortsContains(t, cur, "paused", func() { CompensateDemo(cross(cur), id, 5) })
	as(ownerAddr)
	ResumeEffects(cross(cur), "fx-comp")
	as(otherAddr)
	uassert.AbortsContains(t, cur, "cleanup owner", func() { CompensateDemo(cross(cur), id, 5) })
	as(cleanupAddr)
	comp := CompensateDemo(cross(cur), id, 5)
	as(cleanupAddr)
	DemoStep(cross(cur), comp, 1, 1, "")
	as(cleanupAddr)
	DemoStep(cross(cur), comp, 1, 2, "")
	as(cleanupAddr)
	uassert.Equal(t, "COMMITTED", CloseDemoEffect(cross(cur), comp, 1))
	uassert.Equal(t, "COMPENSATED", EffectState(id))
	uassert.Equal(t, "", DemoValue("c1"))
	uassert.Equal(t, "COMPENSATED", VerifyEffect(id))
	uassert.Equal(t, "COMMITTED", VerifyEffect(comp))
}
