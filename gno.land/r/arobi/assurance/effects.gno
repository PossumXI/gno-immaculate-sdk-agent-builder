package assurance

import (
	"chain/runtime"
	"strconv"
	"strings"

	sdk "gno.land/p/arobi/assurance"
)

var effectTracker = sdk.NewEffectTracker()

// PauseAgentEffects pauses or resumes governed effect execution and recovery for an owned agent.
func PauseAgentEffects(cur realm, agentID string, paused bool) string {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("PauseAgentEffects requires a direct user call")
	}
	caller := prev.Address()
	mustOwnedActiveAgent(agentID, caller)
	effectTracker.SetAgentPaused(agentID, paused)
	if paused {
		return agentID + "|PAUSED"
	}
	return agentID + "|ACTIVE"
}

// BeginEffect starts a governed multi-step effect on-chain with mandatory deadline, cleanup owner,
// postcondition, and reversal class. Refuses IRREVERSIBLE effects without prior human approval
// (leaving zero STARTED record) and fences effect keys holding an open STARTED, IN_DOUBT, or PARTIAL effect.
// Returns "eff-N|STARTED|<attempt>|<leaseTokenHex>|<eventLeafHex>" or "eff-N|DEDUPLICATED|<state>".
func BeginEffect(
	cur realm,
	agentID, effectKey, idempotencyKey, reversalClass, cleanupOwner, postcondition, undoSpec, humanApprovalID string,
	totalSteps int,
	deadlineHeight int64,
) string {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("BeginEffect requires a direct user call")
	}
	caller := prev.Address()
	mustOwnedActiveAgent(agentID, caller)

	owner := strings.TrimSpace(cleanupOwner)
	if owner == "" {
		owner = caller.String()
	}

	spec, err := sdk.NewEffectSpec(agentID, effectKey, idempotencyKey).
		WithSteps(totalSteps).
		WithPostcondition(postcondition).
		WithReversal(sdk.ReversalClass(reversalClass), undoSpec).
		WithDeadlineHeight(deadlineHeight).
		WithCleanupOwner(owner).
		WithHumanApproval(humanApprovalID).
		Build(runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}

	rec, dedup, _, err := effectTracker.BeginEffect(spec, caller.String(), runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	if dedup {
		return rec.ID + "|DEDUPLICATED|" + string(rec.State)
	}
	return rec.ID + "|STARTED|" + strconv.FormatUint(rec.Attempt, 10) + "|" + sdk.Hex(rec.LeaseToken) + "|" + sdk.Hex(rec.LastEventHash)
}

// RecordStep seals one completed step receipt inside a STARTED effect, fenced by attempt and leaseTokenHex.
func RecordStep(cur realm, effectID string, attempt uint64, leaseTokenHex string, stepIndex int, stepName, outputDigestHex string, stateChanged bool) string {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("RecordStep requires a direct user call")
	}
	caller := prev.Address()
	rec, ok := effectTracker.GetEffect(effectID)
	if !ok {
		panic("unknown effect: " + effectID)
	}
	mustOwnedActiveAgent(rec.AgentID, caller)

	lease, err := sdk.ParseDigest(strings.TrimSpace(leaseTokenHex))
	if err != nil {
		panic("invalid lease token: " + err.Error())
	}
	digest, err := sdk.ParseDigest(strings.TrimSpace(outputDigestHex))
	if err != nil {
		panic("invalid output digest: " + err.Error())
	}
	sr, _, err := effectTracker.RecordStep(effectID, attempt, lease, stepIndex, stepName, digest, stateChanged, caller.String(), runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	return rec.ID + "|STEP|" + strconv.Itoa(sr.StepIndex) + "|" + sdk.Hex(sr.LeafHash)
}

// MarkInDoubt is permissionless: ANY direct caller may mark a STARTED effect IN_DOUBT
// once runtime.ChainHeight() >= deadlineHeight. Detection does not trust the quiet agent.
func MarkInDoubt(cur realm, effectID string) string {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("MarkInDoubt requires a direct user call")
	}
	rec, _, err := effectTracker.MarkInDoubt(effectID, prev.Address().String(), runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	return rec.ID + "|IN_DOUBT|" + sdk.Hex(rec.LastEventHash)
}

// CloseEffect checks attempt/lease binding, read-back observation freshness, and sink/grant fence evidence.
// Unfenced no-effect closes as IN_DOUBT (never ABORTED); only once fenceDigestHex proves the grant
// cannot land later does no-effect close as ABORTED.
func CloseEffect(
	cur realm,
	effectID string,
	attempt uint64,
	leaseTokenHex, requestedOutcome, readbackDigestHex string,
	observedHeight int64,
	fenceDigestHex string,
	stateChanged bool,
) string {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("CloseEffect requires a direct user call")
	}
	caller := prev.Address()
	rec, ok := effectTracker.GetEffect(effectID)
	if !ok {
		panic("unknown effect: " + effectID)
	}
	mustOwnedActiveAgent(rec.AgentID, caller)

	lease, err := sdk.ParseDigest(strings.TrimSpace(leaseTokenHex))
	if err != nil {
		panic("invalid lease token: " + err.Error())
	}
	digest := sdk.ZeroDigest()
	if strings.TrimSpace(readbackDigestHex) != "" {
		digest, err = sdk.ParseDigest(strings.TrimSpace(readbackDigestHex))
		if err != nil {
			panic("invalid readback digest: " + err.Error())
		}
	}
	fence := sdk.ZeroDigest()
	if strings.TrimSpace(fenceDigestHex) != "" {
		fence, err = sdk.ParseDigest(strings.TrimSpace(fenceDigestHex))
		if err != nil {
			panic("invalid fence digest: " + err.Error())
		}
	}
	closed, _, err := effectTracker.CloseEffect(
		effectID,
		attempt,
		lease,
		sdk.EffectState(requestedOutcome),
		digest,
		observedHeight,
		fence,
		stateChanged,
		caller.String(),
		runtime.ChainHeight(),
	)
	if err != nil {
		panic(err.Error())
	}
	return closed.ID + "|" + string(closed.State) + "|" + sdk.Hex(closed.LastEventHash)
}

// Compensate seals a bounded linked reversal effect for an IN_DOUBT or PARTIAL effect.
// Refuses while the agent passport is revoked or paused (even if invoked by cleanupOwner),
// enforces MaxRecoveryAttempts, and requires fresh non-zero restored read-back.
func Compensate(
	cur realm,
	originalEffectID, compIdempotencyKey, readbackDigestHex string,
	observedHeight int64,
	restoredOriginalState bool,
	compDeadlineHeight int64,
) string {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("Compensate requires a direct user call")
	}
	caller := prev.Address()
	rec, ok := effectTracker.GetEffect(originalEffectID)
	if !ok {
		panic("unknown effect: " + originalEffectID)
	}

	// Never allow compensation while the underlying agent passport is revoked or paused.
	p, pOk := passports.Get(rec.AgentID).(*AgentPassport)
	if !pOk || p == nil || p.Revoked {
		panic("DENIED: compensation blocked while agent is revoked")
	}
	if caller.String() != rec.CleanupOwner && p.Owner != caller {
		panic("only cleanup owner or agent owner may compensate")
	}

	digest := sdk.ZeroDigest()
	if strings.TrimSpace(readbackDigestHex) != "" {
		var err error
		digest, err = sdk.ParseDigest(strings.TrimSpace(readbackDigestHex))
		if err != nil {
			panic("invalid readback digest: " + err.Error())
		}
	}
	orig, comp, _, err := effectTracker.Compensate(
		originalEffectID,
		compIdempotencyKey,
		digest,
		observedHeight,
		restoredOriginalState,
		compDeadlineHeight,
		caller.String(),
		runtime.ChainHeight(),
	)
	if err != nil {
		panic(err.Error())
	}
	return orig.ID + "|COMPENSATED|" + comp.ID + "|" + sdk.Hex(orig.LastEventHash)
}

// AcceptPartial lets a named human explicitly seal a PARTIAL or IN_DOUBT effect as ACCEPTED.
func AcceptPartial(cur realm, originalEffectID, humanApprover, reasonDigestHex string) string {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("AcceptPartial requires a direct user call")
	}
	caller := prev.Address()
	rec, ok := effectTracker.GetEffect(originalEffectID)
	if !ok {
		panic("unknown effect: " + originalEffectID)
	}
	if caller.String() != rec.CleanupOwner {
		mustOwnedActiveAgent(rec.AgentID, caller)
	}
	digest, err := sdk.ParseDigest(strings.TrimSpace(reasonDigestHex))
	if err != nil {
		panic("invalid reason digest: " + err.Error())
	}
	accepted, _, err := effectTracker.AcceptPartial(originalEffectID, humanApprover, digest, runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	return accepted.ID + "|ACCEPTED|" + sdk.Hex(accepted.LastEventHash)
}

// EffectLifecycleRootHex returns the RFC 6962 Merkle root covering all on-chain effect lifecycle events.
func EffectLifecycleRootHex() string {
	return sdk.Hex(effectTracker.Root())
}

// EffectStateOf returns the current state of an effect (or "NOT_FOUND").
func EffectStateOf(effectID string) string {
	rec, ok := effectTracker.GetEffect(effectID)
	if !ok {
		return "NOT_FOUND"
	}
	if rec.State == sdk.StateStarted && runtime.ChainHeight() >= rec.DeadlineHeight {
		return string(sdk.StateInDoubt)
	}
	return string(rec.State)
}

// OpenObligationsCount returns the number of currently unresolved IN_DOUBT or PARTIAL effects.
func OpenObligationsCount() int {
	return len(effectTracker.OpenObligations(runtime.ChainHeight()))
}

func renderObligations() string {
	obs := effectTracker.OpenObligations(runtime.ChainHeight())
	var b strings.Builder
	b.WriteString("# Open Effect Obligations (IN_DOUBT / PARTIAL)\n\n")
	b.WriteString("- **Lifecycle RFC 6962 Root:** `" + sdk.Hex(effectTracker.Root()) + "`\n")
	b.WriteString("- **Total Lifecycle Events:** `" + strconv.FormatUint(effectTracker.EventCount(), 10) + "`\n")
	b.WriteString("- **Open Obligations:** `" + strconv.Itoa(len(obs)) + "`\n\n")
	if len(obs) == 0 {
		b.WriteString("_No open IN_DOUBT or PARTIAL obligations at height `" + strconv.FormatInt(runtime.ChainHeight(), 10) + "`._\n\n")
	} else {
		b.WriteString("| Effect ID | Effect Key | State | Attempt | Cleanup Owner | Reversal Class | Steps | Recoveries | Age (blocks) | Deadline |\n")
		b.WriteString("| --- | --- | --- | ---: | --- | --- | ---: | ---: | ---: | ---: |\n")
		for _, o := range obs {
			b.WriteString("| `" + o.EffectID + "` | `" + o.EffectKey + "` | `" + string(o.State) + "` | " +
				strconv.FormatUint(o.Attempt, 10) + " | `" +
				o.CleanupOwner + "` | `" + string(o.ReversalClass) + "` | " +
				strconv.Itoa(o.StepsRecorded) + "/" + strconv.Itoa(o.TotalSteps) + " | " +
				strconv.Itoa(o.RecoveryAttempts) + "/" + strconv.Itoa(o.MaxRecovery) + " | " +
				strconv.FormatInt(o.AgeBlocks, 10) + " | " +
				strconv.FormatInt(o.DeadlineHeight, 10) + " |\n")
		}
		b.WriteString("\n")
	}
	b.WriteString("[Back to Arobi Assurance Hub](/r/arobi/assurance)\n")
	return b.String()
}
