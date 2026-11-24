package assurance

import (
	"encoding/binary"
	"errors"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// DomainEffectEvent is the domain separator for canonical partial-effect lifecycle events
// sealed into the RFC 6962 hash-chain and Merkle accumulator.
const DomainEffectEvent = "arobi-assurance-effect-event-v1"

// EffectState tracks the governed lifecycle of a multi-step consequential effect:
//
//	AUTHORIZED -> STARTED -> (step receipts) -> COMMITTED | ABORTED | PARTIAL
//	                 |                                          |
//	                 +-- deadline passes, no close -> IN_DOUBT  +--> COMPENSATED | ACCEPTED | VOIDED
type EffectState string

const (
	StateAuthorized  EffectState = "AUTHORIZED"
	StateStarted     EffectState = "STARTED"
	StateCommitted   EffectState = "COMMITTED"
	StateAborted     EffectState = "ABORTED"
	StatePartial     EffectState = "PARTIAL"
	StateInDoubt     EffectState = "IN_DOUBT"
	StateCompensated EffectState = "COMPENSATED"
	StateAccepted    EffectState = "ACCEPTED"
	StateVoided      EffectState = "VOIDED"
)

// ReversalClass declares before execution how a downstream effect can be undone.
type ReversalClass string

const (
	ReversalReversible   ReversalClass = "REVERSIBLE"
	ReversalCompensable  ReversalClass = "COMPENSABLE"
	ReversalIrreversible ReversalClass = "IRREVERSIBLE"
)

// EffectSpec declares an effect's boundary, ownership, reversal class, and deadline before start.
type EffectSpec struct {
	AgentID         string
	EffectKey       string
	IdempotencyKey  string
	TotalSteps      int
	Postcondition   string
	ReversalClass   ReversalClass
	UndoSpec        string
	DeadlineHeight  int64
	CleanupOwner    string
	HumanApprovalID string
}

// EffectSpecBuilder refuses incomplete effect declarations before anything executes.
type EffectSpecBuilder struct {
	spec EffectSpec
}

func NewEffectSpec(agentID, effectKey, idempotencyKey string) *EffectSpecBuilder {
	return &EffectSpecBuilder{
		spec: EffectSpec{
			AgentID:        strings.TrimSpace(agentID),
			EffectKey:      strings.TrimSpace(effectKey),
			IdempotencyKey: strings.TrimSpace(idempotencyKey),
		},
	}
}

func (b *EffectSpecBuilder) WithSteps(total int) *EffectSpecBuilder {
	b.spec.TotalSteps = total
	return b
}

func (b *EffectSpecBuilder) WithPostcondition(desc string) *EffectSpecBuilder {
	b.spec.Postcondition = strings.TrimSpace(desc)
	return b
}

func (b *EffectSpecBuilder) WithReversal(class ReversalClass, undoSpec string) *EffectSpecBuilder {
	b.spec.ReversalClass = class
	b.spec.UndoSpec = strings.TrimSpace(undoSpec)
	return b
}

func (b *EffectSpecBuilder) WithDeadlineHeight(height int64) *EffectSpecBuilder {
	b.spec.DeadlineHeight = height
	return b
}

func (b *EffectSpecBuilder) WithCleanupOwner(owner string) *EffectSpecBuilder {
	b.spec.CleanupOwner = strings.TrimSpace(owner)
	return b
}

func (b *EffectSpecBuilder) WithHumanApproval(approvalID string) *EffectSpecBuilder {
	b.spec.HumanApprovalID = strings.TrimSpace(approvalID)
	return b
}

// Build validates every required invariant and fails closed if deadline, owner, reversal class,
// postcondition, or human approval (for IRREVERSIBLE) is missing.
func (b *EffectSpecBuilder) Build(startHeight int64) (EffectSpec, error) {
	s := b.spec
	if s.AgentID == "" {
		return EffectSpec{}, errors.New("effect spec missing agent_id")
	}
	if s.EffectKey == "" {
		return EffectSpec{}, errors.New("effect spec missing effect_key")
	}
	if s.IdempotencyKey == "" {
		return EffectSpec{}, errors.New("effect spec missing idempotency_key")
	}
	if s.TotalSteps <= 0 || s.TotalSteps > 64 {
		return EffectSpec{}, errors.New("effect spec total_steps must be between 1 and 64")
	}
	if s.Postcondition == "" {
		return EffectSpec{}, errors.New("effect spec missing declared postcondition")
	}
	if s.CleanupOwner == "" {
		return EffectSpec{}, errors.New("effect spec missing cleanup_owner")
	}
	if s.DeadlineHeight <= startHeight {
		return EffectSpec{}, errors.New("effect spec deadline_height must be strictly greater than start height")
	}
	switch s.ReversalClass {
	case ReversalReversible, ReversalCompensable:
		if s.UndoSpec == "" {
			return EffectSpec{}, errors.New("reversible/compensable effect requires undo_spec")
		}
	case ReversalIrreversible:
		if s.HumanApprovalID == "" {
			return EffectSpec{}, errors.New("DENIED: IRREVERSIBLE effect requires prior human approval")
		}
	default:
		return EffectSpec{}, errors.New("effect spec missing or invalid reversal_class")
	}
	return s, nil
}

// StepReceipt records one completed sub-step inside a multi-step effect.
type StepReceipt struct {
	StepIndex    int
	TotalSteps   int
	Name         string
	OutputDigest [32]byte
	StateChanged bool
	Actor        string
	Height       int64
	LeafHash     [32]byte
}

// EffectEvent is the canonical, hash-chained, RFC 6962 leaf record for every lifecycle transition.
// Mirrors verifier/verify-evidence.mjs encodeEffectEvent byte-for-byte.
type EffectEvent struct {
	Seq            uint64
	PrevHash       [32]byte
	EffectID       string
	EffectKey      string
	IdempotencyKey string
	Kind           string // START | STEP | CLOSE | IN_DOUBT | COMPENSATE | ACCEPT
	State          EffectState
	StepIndex      int
	TotalSteps     int
	Actor          string
	Owner          string
	ReversalClass  ReversalClass
	StateChanged   bool
	ReadbackDigest [32]byte
	SupersedesID   string
	HumanApproval  string
	DeadlineHeight int64
	Height         int64
}

// Encode serializes EffectEvent into deterministic big-endian length-prefixed canonical bytes.
func (e EffectEvent) Encode() []byte {
	out := make([]byte, 0, 320)
	out = appendString(out, DomainEffectEvent)
	out = append(out, EncodingVersion)
	out = binary.BigEndian.AppendUint64(out, e.Seq)
	out = append(out, e.PrevHash[:]...)
	out = appendString(out, e.EffectID)
	out = appendString(out, e.EffectKey)
	out = appendString(out, e.IdempotencyKey)
	out = appendString(out, e.Kind)
	out = appendString(out, string(e.State))
	out = binary.BigEndian.AppendUint32(out, uint32(e.StepIndex))
	out = binary.BigEndian.AppendUint32(out, uint32(e.TotalSteps))
	out = appendString(out, e.Actor)
	out = appendString(out, e.Owner)
	out = appendString(out, string(e.ReversalClass))
	if e.StateChanged {
		out = append(out, 1)
	} else {
		out = append(out, 0)
	}
	out = append(out, e.ReadbackDigest[:]...)
	out = appendString(out, e.SupersedesID)
	out = appendString(out, e.HumanApproval)
	out = binary.BigEndian.AppendUint64(out, uint64(e.DeadlineHeight))
	out = binary.BigEndian.AppendUint64(out, uint64(e.Height))
	return out
}

// LeafHash returns RFC 6962 LeafHash(Encode()).
func (e EffectEvent) LeafHash() [32]byte {
	return LeafHash(e.Encode())
}

// EffectRecord holds the full state, step receipts, and resolution links of one governed effect.
type EffectRecord struct {
	ID              string
	AgentID         string
	EffectKey       string
	IdempotencyKey  string
	State           EffectState
	TotalSteps      int
	Postcondition   string
	ReversalClass   ReversalClass
	UndoSpec        string
	CleanupOwner    string
	HumanApprovalID string
	StartHeight     int64
	DeadlineHeight  int64
	ClosedHeight    int64
	Steps           []StepReceipt
	ReadbackDigest  [32]byte
	CompensatedByID string
	SupersedesID    string
	LastEventHash   [32]byte
}

// OpenObligation summarizes an unresolved IN_DOUBT or PARTIAL effect requiring cleanup or review.
type OpenObligation struct {
	EffectID       string
	EffectKey      string
	State          EffectState
	CleanupOwner   string
	ReversalClass  ReversalClass
	AgeBlocks      int64
	StepsRecorded  int
	TotalSteps     int
	DeadlineHeight int64
}

// EffectTracker manages governed multi-step effects with O(log N) AVL storage,
// deadline detection, effect-key fencing, idempotency deduplication, and RFC 6962 sealing.
type EffectTracker struct {
	effects       *avl.Tree // effectID -> *EffectRecord
	openByKey     *avl.Tree // effectKey -> effectID (fence while STARTED, IN_DOUBT, or PARTIAL)
	byIdempotency *avl.Tree // idempotencyKey -> effectID
	orderTree     *avl.Tree // padded seq -> effectID
	eventSeq      uint64
	effectCount   uint64
	lastHash      [32]byte
	acc           LedgerAccumulator
}

func NewEffectTracker() *EffectTracker {
	return &EffectTracker{
		effects:       avl.NewTree(),
		openByKey:     avl.NewTree(),
		byIdempotency: avl.NewTree(),
		orderTree:     avl.NewTree(),
	}
}

func (t *EffectTracker) Root() [32]byte { return t.acc.Root() }
func (t *EffectTracker) EventCount() uint64 { return t.eventSeq }
func (t *EffectTracker) EffectCount() uint64 { return t.effectCount }
func (t *EffectTracker) LastHash() [32]byte { return t.lastHash }

func (t *EffectTracker) GetEffect(effectID string) (*EffectRecord, bool) {
	v := t.effects.Get(effectID)
	if v == nil {
		return nil, false
	}
	rec, ok := v.(*EffectRecord)
	return rec, ok && rec != nil
}

func padUint64(n uint64) string {
	s := strconv.FormatUint(n, 10)
	if len(s) >= 20 {
		return s
	}
	return strings.Repeat("0", 20-len(s)) + s
}

func (t *EffectTracker) sealEvent(ev EffectEvent) (EffectEvent, [32]byte) {
	t.eventSeq++
	ev.Seq = t.eventSeq
	ev.PrevHash = t.lastHash
	leaf := ev.LeafHash()
	t.lastHash = leaf
	t.acc.Append(leaf)
	return ev, leaf
}

// SweepOverdue transitions any STARTED effect whose deadline has passed to IN_DOUBT
// automatically by height without requiring a call from the quiet executor.
func (t *EffectTracker) SweepOverdue(actor string, currentHeight int64) int {
	var overdue []*EffectRecord
	t.openByKey.Iterate("", "", func(_ string, v any) bool {
		id, _ := v.(string)
		rec, ok := t.GetEffect(id)
		if ok && rec.State == StateStarted && currentHeight >= rec.DeadlineHeight {
			overdue = append(overdue, rec)
		}
		return false
	})
	for _, rec := range overdue {
		rec.State = StateInDoubt
		_, leaf := t.sealEvent(EffectEvent{
			EffectID:       rec.ID,
			EffectKey:      rec.EffectKey,
			IdempotencyKey: rec.IdempotencyKey,
			Kind:           "IN_DOUBT",
			State:          StateInDoubt,
			StepIndex:      len(rec.Steps),
			TotalSteps:     rec.TotalSteps,
			Actor:          actor,
			Owner:          rec.CleanupOwner,
			ReversalClass:  rec.ReversalClass,
			DeadlineHeight: rec.DeadlineHeight,
			Height:         currentHeight,
		})
		rec.LastEventHash = leaf
	}
	return len(overdue)
}

// BeginEffect validates spec, sweeps overdue effects, checks idempotency deduplication,
// enforces effect-key fencing, and seals STARTED in the RFC 6962 chain.
// Returns (record, deduplicated, event, error).
func (t *EffectTracker) BeginEffect(spec EffectSpec, actor string, currentHeight int64) (*EffectRecord, bool, EffectEvent, error) {
	// Validate spec invariants (including IRREVERSIBLE requiring human approval).
	built, err := (&EffectSpecBuilder{spec: spec}).Build(currentHeight)
	if err != nil {
		return nil, false, EffectEvent{}, err
	}

	// Automatically detect overdue quiet executors before fencing check.
	t.SweepOverdue("height-sweep", currentHeight)

	// Idempotency deduplication: a retry with the same idempotency key never applies twice.
	if prev := t.byIdempotency.Get(built.IdempotencyKey); prev != nil {
		prevID := prev.(string)
		if rec, ok := t.GetEffect(prevID); ok {
			return rec, true, EffectEvent{}, nil
		}
	}

	// Fencing: a new authorize on the same effect key while one is STARTED, IN_DOUBT, or PARTIAL is DENIED.
	if open := t.openByKey.Get(built.EffectKey); open != nil {
		openID := open.(string)
		if existing, ok := t.GetEffect(openID); ok {
			return nil, false, EffectEvent{}, errors.New("DENIED: effect key fenced by open effect " + existing.ID + " (state=" + string(existing.State) + ")")
		}
	}

	t.effectCount++
	id := "eff-" + strconv.FormatUint(t.effectCount, 10)
	rec := &EffectRecord{
		ID:              id,
		AgentID:         built.AgentID,
		EffectKey:       built.EffectKey,
		IdempotencyKey:  built.IdempotencyKey,
		State:           StateStarted,
		TotalSteps:      built.TotalSteps,
		Postcondition:   built.Postcondition,
		ReversalClass:   built.ReversalClass,
		UndoSpec:        built.UndoSpec,
		CleanupOwner:    built.CleanupOwner,
		HumanApprovalID: built.HumanApprovalID,
		StartHeight:     currentHeight,
		DeadlineHeight:  built.DeadlineHeight,
	}

	ev, leaf := t.sealEvent(EffectEvent{
		EffectID:       rec.ID,
		EffectKey:      rec.EffectKey,
		IdempotencyKey: rec.IdempotencyKey,
		Kind:           "START",
		State:          StateStarted,
		StepIndex:      0,
		TotalSteps:     rec.TotalSteps,
		Actor:          actor,
		Owner:          rec.CleanupOwner,
		ReversalClass:  rec.ReversalClass,
		HumanApproval:  rec.HumanApprovalID,
		DeadlineHeight: rec.DeadlineHeight,
		Height:         currentHeight,
	})
	rec.LastEventHash = leaf

	t.effects.Set(rec.ID, rec)
	t.openByKey.Set(rec.EffectKey, rec.ID)
	t.byIdempotency.Set(rec.IdempotencyKey, rec.ID)
	t.orderTree.Set(padUint64(t.effectCount), rec.ID)
	return rec, false, ev, nil
}

// RecordStep seals one completed step receipt inside an active STARTED effect.
func (t *EffectTracker) RecordStep(effectID string, stepIndex int, stepName string, outputDigest [32]byte, stateChanged bool, actor string, currentHeight int64) (StepReceipt, EffectEvent, error) {
	rec, ok := t.GetEffect(effectID)
	if !ok {
		return StepReceipt{}, EffectEvent{}, errors.New("unknown effect id: " + effectID)
	}
	if rec.State != StateStarted {
		return StepReceipt{}, EffectEvent{}, errors.New("cannot record step in state " + string(rec.State))
	}
	if currentHeight >= rec.DeadlineHeight {
		t.MarkInDoubt(effectID, actor, currentHeight)
		return StepReceipt{}, EffectEvent{}, errors.New("effect deadline passed; marked IN_DOUBT")
	}
	if stepIndex < 1 || stepIndex > rec.TotalSteps {
		return StepReceipt{}, EffectEvent{}, errors.New("step index out of declared bounds")
	}
	for _, existing := range rec.Steps {
		if existing.StepIndex == stepIndex {
			return existing, EffectEvent{}, nil
		}
	}
	ev, leaf := t.sealEvent(EffectEvent{
		EffectID:       rec.ID,
		EffectKey:      rec.EffectKey,
		IdempotencyKey: rec.IdempotencyKey,
		Kind:           "STEP",
		State:          StateStarted,
		StepIndex:      stepIndex,
		TotalSteps:     rec.TotalSteps,
		Actor:          actor,
		Owner:          rec.CleanupOwner,
		ReversalClass:  rec.ReversalClass,
		StateChanged:   stateChanged,
		ReadbackDigest: outputDigest,
		DeadlineHeight: rec.DeadlineHeight,
		Height:         currentHeight,
	})
	sr := StepReceipt{
		StepIndex:    stepIndex,
		TotalSteps:   rec.TotalSteps,
		Name:         stepName,
		OutputDigest: outputDigest,
		StateChanged: stateChanged,
		Actor:        actor,
		Height:       currentHeight,
		LeafHash:     leaf,
	}
	rec.Steps = append(rec.Steps, sr)
	rec.LastEventHash = leaf
	return sr, ev, nil
}

// MarkInDoubt may be called by ANYONE once currentHeight >= effect.DeadlineHeight.
// Detection does not trust or wait for a dead or silent executor.
func (t *EffectTracker) MarkInDoubt(effectID, caller string, currentHeight int64) (*EffectRecord, EffectEvent, error) {
	rec, ok := t.GetEffect(effectID)
	if !ok {
		return nil, EffectEvent{}, errors.New("unknown effect id: " + effectID)
	}
	if rec.State == StateInDoubt {
		return rec, EffectEvent{}, nil
	}
	if rec.State != StateStarted {
		return nil, EffectEvent{}, errors.New("only STARTED effects may transition to IN_DOUBT; state=" + string(rec.State))
	}
	if currentHeight < rec.DeadlineHeight {
		return nil, EffectEvent{}, errors.New("deadline height not yet reached")
	}
	rec.State = StateInDoubt
	ev, leaf := t.sealEvent(EffectEvent{
		EffectID:       rec.ID,
		EffectKey:      rec.EffectKey,
		IdempotencyKey: rec.IdempotencyKey,
		Kind:           "IN_DOUBT",
		State:          StateInDoubt,
		StepIndex:      len(rec.Steps),
		TotalSteps:     rec.TotalSteps,
		Actor:          caller,
		Owner:          rec.CleanupOwner,
		ReversalClass:  rec.ReversalClass,
		DeadlineHeight: rec.DeadlineHeight,
		Height:         currentHeight,
	})
	rec.LastEventHash = leaf
	return rec, ev, nil
}

// CloseEffect checks downstream read-back evidence instead of trusting exit 0:
//   - COMMITTED requires non-zero readbackDigest, stateChanged == true, and all declared steps recorded.
//   - Exit 0 with stateChanged == false or missing readback closes as ABORTED (if 0 changed steps) or PARTIAL.
//   - PARTIAL retains the effect-key fence until COMPENSATED or human ACCEPTED.
func (t *EffectTracker) CloseEffect(effectID string, requested EffectState, readbackDigest [32]byte, stateChanged bool, actor string, currentHeight int64) (*EffectRecord, EffectEvent, error) {
	rec, ok := t.GetEffect(effectID)
	if !ok {
		return nil, EffectEvent{}, errors.New("unknown effect id: " + effectID)
	}
	if rec.State != StateStarted && rec.State != StateInDoubt {
		return nil, EffectEvent{}, errors.New("cannot close effect in state " + string(rec.State))
	}

	anyStepChanged := false
	for _, s := range rec.Steps {
		if s.StateChanged {
			anyStepChanged = true
			break
		}
	}

	finalState := requested
	switch requested {
	case StateCommitted:
		if !stateChanged || readbackDigest == ZeroDigest() {
			if anyStepChanged {
				finalState = StatePartial
			} else {
				finalState = StateAborted
			}
		} else if len(rec.Steps) < rec.TotalSteps {
			finalState = StatePartial
		}
	case StateAborted:
		if anyStepChanged {
			finalState = StatePartial
		}
	case StatePartial:
		finalState = StatePartial
	default:
		return nil, EffectEvent{}, errors.New("close outcome must be COMMITTED, ABORTED, or PARTIAL")
	}

	rec.State = finalState
	rec.ReadbackDigest = readbackDigest
	rec.ClosedHeight = currentHeight

	// COMMITTED and ABORTED release the fence; PARTIAL keeps the fence until COMPENSATED or ACCEPTED.
	if finalState == StateCommitted || finalState == StateAborted {
		t.openByKey.Remove(rec.EffectKey)
	}

	ev, leaf := t.sealEvent(EffectEvent{
		EffectID:       rec.ID,
		EffectKey:      rec.EffectKey,
		IdempotencyKey: rec.IdempotencyKey,
		Kind:           "CLOSE",
		State:          finalState,
		StepIndex:      len(rec.Steps),
		TotalSteps:     rec.TotalSteps,
		Actor:          actor,
		Owner:          rec.CleanupOwner,
		ReversalClass:  rec.ReversalClass,
		StateChanged:   stateChanged || anyStepChanged,
		ReadbackDigest: readbackDigest,
		DeadlineHeight: rec.DeadlineHeight,
		Height:         currentHeight,
	})
	rec.LastEventHash = leaf
	return rec, ev, nil
}

// Compensate runs a linked reversal effect against an IN_DOUBT or PARTIAL effect.
// Requires verified read-back confirming the earlier state was restored; clears the fence on effectKey.
func (t *EffectTracker) Compensate(originalEffectID, compIdempotencyKey string, readbackDigest [32]byte, restoredOriginalState bool, actor string, currentHeight int64) (*EffectRecord, *EffectRecord, EffectEvent, error) {
	orig, ok := t.GetEffect(originalEffectID)
	if !ok {
		return nil, nil, EffectEvent{}, errors.New("unknown effect id: " + originalEffectID)
	}
	if orig.State != StateInDoubt && orig.State != StatePartial {
		return nil, nil, EffectEvent{}, errors.New("only IN_DOUBT or PARTIAL effects may be compensated; state=" + string(orig.State))
	}
	if orig.ReversalClass == ReversalIrreversible {
		return nil, nil, EffectEvent{}, errors.New("IRREVERSIBLE effect cannot be automatically compensated; require human AcceptPartial")
	}
	if !restoredOriginalState || readbackDigest == ZeroDigest() {
		return nil, nil, EffectEvent{}, errors.New("COMPENSATED requires non-zero read-back confirming restored state")
	}
	if strings.TrimSpace(compIdempotencyKey) == "" {
		return nil, nil, EffectEvent{}, errors.New("compensation requires non-empty idempotency key")
	}
	if prev := t.byIdempotency.Get(compIdempotencyKey); prev != nil {
		compRec, _ := t.GetEffect(prev.(string))
		return orig, compRec, EffectEvent{}, nil
	}

	// Create the linked compensation effect record.
	t.effectCount++
	compID := "eff-" + strconv.FormatUint(t.effectCount, 10)
	comp := &EffectRecord{
		ID:             compID,
		AgentID:        orig.AgentID,
		EffectKey:      orig.EffectKey + ":compensate",
		IdempotencyKey: compIdempotencyKey,
		State:          StateCommitted,
		TotalSteps:     1,
		Postcondition:  "restored state prior to " + orig.ID,
		ReversalClass:  ReversalCompensable,
		UndoSpec:       orig.UndoSpec,
		CleanupOwner:   orig.CleanupOwner,
		StartHeight:    currentHeight,
		DeadlineHeight: currentHeight + 1,
		ClosedHeight:   currentHeight,
		ReadbackDigest: readbackDigest,
		SupersedesID:   orig.ID,
	}

	// Seal the compensation effect commit event first, then supersede original -> COMPENSATED.
	_, compLeaf := t.sealEvent(EffectEvent{
		EffectID:       comp.ID,
		EffectKey:      comp.EffectKey,
		IdempotencyKey: comp.IdempotencyKey,
		Kind:           "COMPENSATE",
		State:          StateCommitted,
		StepIndex:      1,
		TotalSteps:     1,
		Actor:          actor,
		Owner:          comp.CleanupOwner,
		ReversalClass:  comp.ReversalClass,
		StateChanged:   true,
		ReadbackDigest: readbackDigest,
		SupersedesID:   orig.ID,
		DeadlineHeight: comp.DeadlineHeight,
		Height:         currentHeight,
	})
	comp.LastEventHash = compLeaf
	t.effects.Set(comp.ID, comp)
	t.byIdempotency.Set(comp.IdempotencyKey, comp.ID)
	t.orderTree.Set(padUint64(t.effectCount), comp.ID)

	orig.State = StateCompensated
	orig.CompensatedByID = comp.ID
	orig.ReadbackDigest = readbackDigest
	orig.ClosedHeight = currentHeight
	t.openByKey.Remove(orig.EffectKey)

	ev, origLeaf := t.sealEvent(EffectEvent{
		EffectID:       orig.ID,
		EffectKey:      orig.EffectKey,
		IdempotencyKey: orig.IdempotencyKey,
		Kind:           "COMPENSATE",
		State:          StateCompensated,
		StepIndex:      len(orig.Steps),
		TotalSteps:     orig.TotalSteps,
		Actor:          actor,
		Owner:          orig.CleanupOwner,
		ReversalClass:  orig.ReversalClass,
		StateChanged:   true,
		ReadbackDigest: readbackDigest,
		SupersedesID:   comp.ID,
		DeadlineHeight: orig.DeadlineHeight,
		Height:         currentHeight,
	})
	orig.LastEventHash = origLeaf
	return orig, comp, ev, nil
}

// AcceptPartial lets a named human explicitly close a PARTIAL or IN_DOUBT effect as ACCEPTED.
func (t *EffectTracker) AcceptPartial(effectID, humanApprover string, reasonDigest [32]byte, currentHeight int64) (*EffectRecord, EffectEvent, error) {
	rec, ok := t.GetEffect(effectID)
	if !ok {
		return nil, EffectEvent{}, errors.New("unknown effect id: " + effectID)
	}
	if rec.State != StatePartial && rec.State != StateInDoubt {
		return nil, EffectEvent{}, errors.New("only PARTIAL or IN_DOUBT effects may be accepted")
	}
	if strings.TrimSpace(humanApprover) == "" || reasonDigest == ZeroDigest() {
		return nil, EffectEvent{}, errors.New("human approver and non-zero reason digest are required")
	}
	rec.State = StateAccepted
	rec.HumanApprovalID = humanApprover
	rec.ReadbackDigest = reasonDigest
	rec.ClosedHeight = currentHeight
	t.openByKey.Remove(rec.EffectKey)

	ev, leaf := t.sealEvent(EffectEvent{
		EffectID:       rec.ID,
		EffectKey:      rec.EffectKey,
		IdempotencyKey: rec.IdempotencyKey,
		Kind:           "ACCEPT",
		State:          StateAccepted,
		StepIndex:      len(rec.Steps),
		TotalSteps:     rec.TotalSteps,
		Actor:          humanApprover,
		Owner:          rec.CleanupOwner,
		ReversalClass:  rec.ReversalClass,
		ReadbackDigest: reasonDigest,
		HumanApproval:  humanApprover,
		DeadlineHeight: rec.DeadlineHeight,
		Height:         currentHeight,
	})
	rec.LastEventHash = leaf
	return rec, ev, nil
}

// OpenObligations sweeps overdue effects and lists every IN_DOUBT or PARTIAL obligation.
func (t *EffectTracker) OpenObligations(currentHeight int64) []OpenObligation {
	t.SweepOverdue("obligation-sweep", currentHeight)
	var out []OpenObligation
	t.openByKey.Iterate("", "", func(_ string, v any) bool {
		id, _ := v.(string)
		rec, ok := t.GetEffect(id)
		if ok && (rec.State == StateInDoubt || rec.State == StatePartial) {
			age := currentHeight - rec.StartHeight
			if age < 0 {
				age = 0
			}
			out = append(out, OpenObligation{
				EffectID:       rec.ID,
				EffectKey:      rec.EffectKey,
				State:          rec.State,
				CleanupOwner:   rec.CleanupOwner,
				ReversalClass:  rec.ReversalClass,
				AgeBlocks:      age,
				StepsRecorded:  len(rec.Steps),
				TotalSteps:     rec.TotalSteps,
				DeadlineHeight: rec.DeadlineHeight,
			})
		}
		return false
	})
	return out
}
