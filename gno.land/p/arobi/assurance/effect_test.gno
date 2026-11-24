package assurance

import (
	"strings"
	"testing"
)

const (
	effExecutor = "g1executor"
	effOwner    = "g1cleanup"
)

// effSpec is an external effect whose downstream honours EffectLive, so a fence proves "no effect".
func effSpec() EffectSpec {
	s, err := NewEffect("worker-1", "ledger:alice", "pay-42").
		Steps(3).
		States(HashString("before"), HashString("after")).
		DownstreamHonoursLive(true).
		Deadline(10).
		CleanupOwner(effOwner).
		Compensable("refund").
		Build()
	if err != nil {
		panic(err.Error())
	}
	return s
}

// landableSpec is the same effect against a downstream that does not honour EffectLive.
func landableSpec() EffectSpec {
	s := effSpec()
	s.DownstreamHonoursLive = false
	return s
}

func TestALandableEffectNeverReadsAbortedAndNeedsApprovalToCompensate(t *testing.T) {
	s := landableSpec()
	if !s.Landable() || effSpec().Landable() {
		t.Fatalf("Landable is the external read-back without EffectLive")
	}
	// A fence and a pre-state read-back after it: still IN_DOUBT, because a request sent before the fence may land.
	closed := chainEvents(9, s, []EffectEvent{
		startEvent(s, 100),
		{Kind: EventStep, State: EffectStarted, Actor: effExecutor, Height: 101, StepIndex: 1, Digest: HashString("r1")},
		{Kind: EventFence, State: EffectStarted, Actor: effExecutor, Height: 102},
		{Kind: EventClose, State: EffectInDoubt, Actor: effExecutor, Height: 104, Digest: s.PreState, ObservedHeight: 103},
	})
	if st, err := VerifyEffectLife(9, s, closed); err != nil || st != EffectInDoubt {
		t.Fatalf("got %s, %v", st, err)
	}
	asserted := chainEvents(9, s, []EffectEvent{
		startEvent(s, 100),
		{Kind: EventFence, State: EffectStarted, Actor: effExecutor, Height: 102},
		{Kind: EventClose, State: EffectAborted, Actor: effExecutor, Height: 104, Digest: s.PreState, ObservedHeight: 103},
	})
	if _, err := VerifyEffectLife(9, s, asserted); err == nil {
		t.Fatalf("ABORTED must not verify for an effect that may still land")
	}
	// The same after the deadline: the clock proves nothing either.
	late := chainEvents(9, s, []EffectEvent{
		startEvent(s, 100),
		{Kind: EventInDoubt, State: EffectInDoubt, Actor: "g1anyone", Height: 111},
		{Kind: EventClose, State: EffectInDoubt, Actor: effOwner, Height: 120, Digest: s.PreState, ObservedHeight: 119},
	})
	if st, err := VerifyEffectLife(9, s, late); err != nil || st != EffectInDoubt {
		t.Fatalf("got %s, %v", st, err)
	}
	// Compensating it while IN_DOUBT needs the owner's approval, carried on the COMPENSATE event.
	unapproved := chainEvents(9, s, []EffectEvent{
		startEvent(s, 100),
		{Kind: EventInDoubt, State: EffectInDoubt, Actor: "g1anyone", Height: 111},
		{Kind: EventCompensate, State: EffectInDoubt, Actor: effOwner, Height: 112, Link: 10},
	})
	if _, err := VerifyEffectLife(9, s, unapproved); err == nil {
		t.Fatalf("a compensation of an effect that may still land needs the recorded approval")
	}
	approved := chainEvents(9, s, []EffectEvent{
		startEvent(s, 100),
		{Kind: EventInDoubt, State: EffectInDoubt, Actor: "g1anyone", Height: 111},
		{Kind: EventCompensate, State: EffectInDoubt, Actor: effOwner, Height: 112, Digest: HashString("approval 3"), Link: 10},
		{Kind: EventCompensated, State: EffectCompensated, Actor: effOwner, Height: 115, Digest: s.PreState, Link: 10},
	})
	if st, err := VerifyEffectLife(9, s, approved); err != nil || st != EffectCompensated {
		t.Fatalf("got %s, %v", st, err)
	}
	// Undone, yet the old request may still land: the key is freed only by a RELEASE from someone other than the
	// executor, against the downstream's own record that the attempt will not land, and only once.
	release := func(actor string, digest [32]byte) EffectEvent {
		return EffectEvent{Kind: EventRelease, State: EffectCompensated, Actor: actor, Height: 120, Digest: digest}
	}
	withRelease := func(evs ...EffectEvent) []EffectEvent {
		base := []EffectEvent{
			startEvent(s, 100),
			{Kind: EventInDoubt, State: EffectInDoubt, Actor: "g1anyone", Height: 111},
			{Kind: EventCompensate, State: EffectInDoubt, Actor: effOwner, Height: 112, Digest: HashString("approval 3"), Link: 10},
			{Kind: EventCompensated, State: EffectCompensated, Actor: effOwner, Height: 115, Digest: s.PreState, Link: 10},
		}
		return chainEvents(9, s, append(base, evs...))
	}
	if st, err := VerifyEffectLife(9, s, withRelease(release("g1approver", HashString("downstream: attempt 1 refused")))); err != nil || st != EffectCompensated {
		t.Fatalf("got %s, %v", st, err)
	}
	for name, evs := range map[string][]EffectEvent{
		"by the executor":   withRelease(release(effExecutor, HashString("receipt"))),
		"with no receipt":   withRelease(release("g1approver", ZeroDigest())),
		"twice":             withRelease(release("g1approver", HashString("r")), release("g1approver", HashString("r2"))),
		"of a live sink":    chainEvents(9, effSpec(), []EffectEvent{startEvent(effSpec(), 100), {Kind: EventFence, State: EffectStarted, Actor: effExecutor, Height: 101}, {Kind: EventClose, State: EffectAborted, Actor: effExecutor, Height: 103, Digest: effSpec().PreState, ObservedHeight: 102}, {Kind: EventRelease, State: EffectAborted, Actor: "g1approver", Height: 104, Digest: HashString("r")}}),
	} {
		spec := s
		if name == "of a live sink" {
			spec = effSpec()
		}
		if _, err := VerifyEffectLife(9, spec, evs); err == nil {
			t.Fatalf("release %s must not verify", name)
		}
	}
}

// chainEvents numbers the events, links each to the one before and returns them.
func chainEvents(id uint64, spec EffectSpec, evs []EffectEvent) []EffectEvent {
	prev := ZeroDigest()
	for i := range evs {
		evs[i].EffectID, evs[i].Attempt, evs[i].Seq, evs[i].PrevHash = id, spec.Attempt, uint32(i), prev
		prev = evs[i].LeafHash()
	}
	return evs
}

func startEvent(spec EffectSpec, height int64) EffectEvent {
	return EffectEvent{Kind: EventStart, State: EffectStarted, Actor: effExecutor, Height: height, Digest: spec.Digest()}
}

func TestEffectBuilderRefusesAnUndecidedSpec(t *testing.T) {
	base := func() *EffectBuilder {
		return NewEffect("worker-1", "ledger:alice", "pay-42").Steps(1).States(HashString("a"), HashString("b")).Deadline(5).CleanupOwner(effOwner)
	}
	if _, err := base().Build(); err == nil || !strings.Contains(err.Error(), "reversal class") {
		t.Fatalf("no reversal class must be refused, got %v", err)
	}
	if _, err := base().Deadline(0).Compensable("refund").Build(); err == nil || !strings.Contains(err.Error(), "deadline") {
		t.Fatalf("no deadline must be refused, got %v", err)
	}
	if _, err := base().CleanupOwner("").Compensable("refund").Build(); err == nil || !strings.Contains(err.Error(), "cleanup owner") {
		t.Fatalf("no cleanup owner must be refused, got %v", err)
	}
	if _, err := base().Reversible("").Build(); err == nil || !strings.Contains(err.Error(), "names how it is undone") {
		t.Fatalf("a REVERSIBLE effect without its inverse must be refused, got %v", err)
	}
	if _, err := base().Irreversible(0).Build(); err == nil || !strings.Contains(err.Error(), "human approval") {
		t.Fatalf("an IRREVERSIBLE effect without an approval must be refused, got %v", err)
	}
	if _, err := base().States(HashString("a"), HashString("a")).Compensable("refund").Build(); err == nil {
		t.Fatalf("a postcondition equal to the pre-state must be refused")
	}
	if _, err := base().Irreversible(7).Build(); err != nil {
		t.Fatalf("an approved IRREVERSIBLE effect is a valid spec: %v", err)
	}
}

func TestCloseOutcomeNeedsAFenceForNoEffect(t *testing.T) {
	s := effSpec()
	cases := []struct {
		readBack [32]byte
		fenced   bool
		want     EffectState
	}{
		{s.Postcondition, false, EffectCommitted},
		{s.Postcondition, true, EffectCommitted},
		{s.PreState, false, EffectInDoubt}, // nothing seen is not yet no effect
		{s.PreState, true, EffectAborted},
		{HashString("half"), false, EffectPartial},
		{HashString("half"), true, EffectPartial},
	}
	for i, c := range cases {
		if got := CloseOutcome(s, c.readBack, c.fenced); got != c.want {
			t.Fatalf("case %d: got %s, want %s", i, got, c.want)
		}
	}
}

func TestEffectiveStateIsInDoubtPastTheDeadline(t *testing.T) {
	if got := EffectiveState(EffectStarted, 100, 10, 110); got != EffectStarted {
		t.Fatalf("at the deadline height it is still STARTED, got %s", got)
	}
	if got := EffectiveState(EffectStarted, 100, 10, 111); got != EffectInDoubt {
		t.Fatalf("past the deadline it reads IN_DOUBT, got %s", got)
	}
	if got := EffectiveState(EffectCommitted, 100, 10, 500); got != EffectCommitted {
		t.Fatalf("a closed effect keeps its state, got %s", got)
	}
}

func TestVerifyEffectLifeAcceptsACompensatedLife(t *testing.T) {
	s := effSpec()
	evs := chainEvents(9, s, []EffectEvent{
		startEvent(s, 100),
		{Kind: EventStep, State: EffectStarted, Actor: effExecutor, Height: 101, StepIndex: 1, Digest: HashString("r1")},
		{Kind: EventInDoubt, State: EffectInDoubt, Actor: "g1anyone", Height: 111},
		{Kind: EventCompensate, State: EffectInDoubt, Actor: effOwner, Height: 112, Link: 10},
		{Kind: EventCompensated, State: EffectCompensated, Actor: effOwner, Height: 115, Digest: s.PreState, Link: 10},
	})
	if st, err := VerifyEffectLife(9, s, evs); err != nil || st != EffectCompensated {
		t.Fatalf("got %s, %v", st, err)
	}
	// The executor's own close of a pre-state read-back, before any fence, is IN_DOUBT; after a fence it is ABORTED.
	evs2 := chainEvents(9, s, []EffectEvent{
		startEvent(s, 100),
		{Kind: EventStep, State: EffectStarted, Actor: effExecutor, Height: 101, StepIndex: 1, Digest: HashString("r1")},
		{Kind: EventClose, State: EffectInDoubt, Actor: effExecutor, Height: 102, Digest: s.PreState, ObservedHeight: 102},
		{Kind: EventFence, State: EffectInDoubt, Actor: effOwner, Height: 103},
		{Kind: EventClose, State: EffectAborted, Actor: effOwner, Height: 105, Digest: s.PreState, ObservedHeight: 104},
	})
	if st, err := VerifyEffectLife(9, s, evs2); err != nil || st != EffectAborted {
		t.Fatalf("got %s, %v", st, err)
	}
	// A person accepts an IN_DOUBT effect once it is fenced.
	evs3 := chainEvents(9, s, []EffectEvent{
		startEvent(s, 100),
		{Kind: EventInDoubt, State: EffectInDoubt, Actor: "g1anyone", Height: 111},
		{Kind: EventFence, State: EffectInDoubt, Actor: effOwner, Height: 112},
		{Kind: EventAccept, State: EffectAccepted, Actor: effOwner, Height: 113, Digest: HashString("ok")},
	})
	if st, err := VerifyEffectLife(9, s, evs3); err != nil || st != EffectAccepted {
		t.Fatalf("got %s, %v", st, err)
	}
}

func TestVerifyEffectLifeRefusesATamperedChain(t *testing.T) {
	s := effSpec()
	good := func() []EffectEvent {
		return chainEvents(9, s, []EffectEvent{
			startEvent(s, 100),
			{Kind: EventStep, State: EffectStarted, Actor: effExecutor, Height: 101, StepIndex: 1, Digest: HashString("r1")},
			{Kind: EventStep, State: EffectStarted, Actor: effExecutor, Height: 102, StepIndex: 2, Digest: HashString("r2")},
			{Kind: EventClose, State: EffectPartial, Actor: effExecutor, Height: 103, Digest: HashString("half"), ObservedHeight: 103},
		})
	}
	if _, err := VerifyEffectLife(9, s, good()); err != nil {
		t.Fatalf("the untampered life must verify: %v", err)
	}
	cases := map[string]func([]EffectEvent) []EffectEvent{
		"gap": func(e []EffectEvent) []EffectEvent { return []EffectEvent{e[0], e[1], e[3]} },
		"reorder": func(e []EffectEvent) []EffectEvent {
			e[1], e[2] = e[2], e[1]
			return e
		},
		"fork": func(e []EffectEvent) []EffectEvent {
			e[2].Digest = HashString("another receipt") // the next event no longer links to it
			return e
		},
		"asserted commit": func(e []EffectEvent) []EffectEvent {
			e[3].State = EffectCommitted // the read-back computes PARTIAL
			return chainEvents(9, s, e)
		},
		"another attempt": func(e []EffectEvent) []EffectEvent {
			e[2].Attempt = 2
			return e
		},
		"spec swapped": func(e []EffectEvent) []EffectEvent {
			e[0].Digest = HashString("another spec")
			return chainEvents(9, s, e)
		},
	}
	for name, tamper := range cases {
		if _, err := VerifyEffectLife(9, s, tamper(good())); err == nil {
			t.Fatalf("%s: a tampered life must not verify", name)
		}
	}
}

func TestVerifyEffectLifeRefusesWhatTheLifecycleForbids(t *testing.T) {
	s := effSpec()
	cases := map[string][]EffectEvent{
		"IN_DOUBT before the deadline": {
			startEvent(s, 100),
			{Kind: EventInDoubt, State: EffectInDoubt, Actor: "g1anyone", Height: 105},
		},
		"a step after the deadline": {
			startEvent(s, 100),
			{Kind: EventStep, State: EffectStarted, Actor: effExecutor, Height: 111, StepIndex: 1, Digest: HashString("r1")},
		},
		"a step after the fence": {
			startEvent(s, 100),
			{Kind: EventFence, State: EffectStarted, Actor: effExecutor, Height: 101},
			{Kind: EventStep, State: EffectStarted, Actor: effExecutor, Height: 102, StepIndex: 1, Digest: HashString("r1")},
		},
		"a step by someone else": {
			startEvent(s, 100),
			{Kind: EventStep, State: EffectStarted, Actor: effOwner, Height: 101, StepIndex: 1, Digest: HashString("r1")},
		},
		"ABORTED without a fence": {
			startEvent(s, 100),
			{Kind: EventClose, State: EffectAborted, Actor: effExecutor, Height: 102, Digest: s.PreState, ObservedHeight: 102},
		},
		"a read-back from before the last step": {
			startEvent(s, 100),
			{Kind: EventStep, State: EffectStarted, Actor: effExecutor, Height: 104, StepIndex: 1, Digest: HashString("r1")},
			{Kind: EventClose, State: EffectCommitted, Actor: effExecutor, Height: 105, Digest: s.Postcondition, ObservedHeight: 103},
		},
		"acceptance by the executor": {
			startEvent(s, 100),
			{Kind: EventClose, State: EffectPartial, Actor: effExecutor, Height: 102, Digest: HashString("half"), ObservedHeight: 102},
			{Kind: EventAccept, State: EffectAccepted, Actor: effExecutor, Height: 103, Digest: HashString("ok")},
		},
		"accepting an unfenced IN_DOUBT": {
			startEvent(s, 100),
			{Kind: EventInDoubt, State: EffectInDoubt, Actor: "g1anyone", Height: 111},
			{Kind: EventAccept, State: EffectAccepted, Actor: effOwner, Height: 112, Digest: HashString("ok")},
		},
		"anything after ABORTED": {
			startEvent(s, 100),
			{Kind: EventFence, State: EffectStarted, Actor: effExecutor, Height: 101},
			{Kind: EventClose, State: EffectAborted, Actor: effExecutor, Height: 103, Digest: s.PreState, ObservedHeight: 102},
			{Kind: EventAccept, State: EffectAccepted, Actor: effOwner, Height: 104, Digest: HashString("ok")},
		},
	}
	for name, evs := range cases {
		if _, err := VerifyEffectLife(9, s, chainEvents(9, s, evs)); err == nil {
			t.Fatalf("%s: must not verify", name)
		}
	}
}

func TestEffectEncodingIsCanonical(t *testing.T) {
	a, b := effSpec(), effSpec()
	if a.Digest() != b.Digest() {
		t.Fatalf("the same spec must have the same digest")
	}
	b.Attempt = 2
	if a.Digest() == b.Digest() {
		t.Fatalf("the attempt is part of the spec digest")
	}
	ev := EffectEvent{EffectID: 1, Attempt: 1, Kind: EventStart, State: EffectStarted, Actor: effExecutor, Height: 5, Digest: a.Digest()}
	if ev.LeafHash() != LeafHash(ev.Encode()) {
		t.Fatalf("an event's leaf is RFC 6962 LeafHash of its encoding")
	}
}
