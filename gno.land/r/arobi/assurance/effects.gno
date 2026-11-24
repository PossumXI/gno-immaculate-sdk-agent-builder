package assurance

import (
	"chain/runtime"
	"strconv"
	"strings"

	sdk "gno.land/p/arobi/assurance"
)

var effectTracker = sdk.NewEffectTracker()

// BeginEffect starts a governed multi-step effect on-chain with mandatory deadline, cleanup owner,
// postcondition, and reversal class. Refuses IRREVERSIBLE effects without prior human approval and
// fences effect keys that already have an open STARTED, IN_DOUBT, or PARTIAL effect.
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
	return rec.ID + "|STARTED|" + sdk.Hex(rec.LastEventHash)
}

// RecordStep seals one completed step receipt inside a STARTED effect.
func RecordStep(cur realm, effectID string, stepIndex int, stepName, outputDigestHex string, stateChanged bool) string {
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

	digest, err := sdk.ParseDigest(strings.TrimSpace(outputDigestHex))
	if err != nil {
		panic("invalid output digest: " + err.Error())
	}
	sr, _, err := effectTracker.RecordStep(effectID, stepIndex, stepName, digest, stateChanged, caller.String(), runtime.ChainHeight())
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

// CloseEffect checks downstream read-back evidence and closes a STARTED or IN_DOUBT effect.
// A zero readback or stateChanged=false never closes as COMMITTED (closes ABORTED or PARTIAL).
func CloseEffect(cur realm, effectID, requestedOutcome, readbackDigestHex string, stateChanged bool) string {
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

	digest := sdk.ZeroDigest()
	if strings.TrimSpace(readbackDigestHex) != "" {
		var err error
		digest, err = sdk.ParseDigest(strings.TrimSpace(readbackDigestHex))
		if err != nil {
			panic("invalid readback digest: " + err.Error())
		}
	}
	closed, _, err := effectTracker.CloseEffect(effectID, sdk.EffectState(requestedOutcome), digest, stateChanged, caller.String(), runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	return closed.ID + "|" + string(closed.State) + "|" + sdk.Hex(closed.LastEventHash)
}

// Compensate seals a linked reversal effect and transitions an IN_DOUBT or PARTIAL effect to COMPENSATED
// once verified read-back confirms the earlier state was restored.
func Compensate(cur realm, originalEffectID, compIdempotencyKey, readbackDigestHex string, restoredOriginalState bool) string {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("Compensate requires a direct user call")
	}
	caller := prev.Address()
	rec, ok := effectTracker.GetEffect(originalEffectID)
	if !ok {
		panic("unknown effect: " + originalEffectID)
	}
	// Either the agent owner or the designated cleanup owner may run compensation.
	if caller.String() != rec.CleanupOwner {
		mustOwnedActiveAgent(rec.AgentID, caller)
	}
	digest, err := sdk.ParseDigest(strings.TrimSpace(readbackDigestHex))
	if err != nil {
		panic("invalid readback digest: " + err.Error())
	}
	orig, comp, _, err := effectTracker.Compensate(originalEffectID, compIdempotencyKey, digest, restoredOriginalState, caller.String(), runtime.ChainHeight())
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
		b.WriteString("| Effect ID | Effect Key | State | Cleanup Owner | Reversal Class | Steps | Age (blocks) | Deadline |\n")
		b.WriteString("| --- | --- | --- | --- | --- | ---: | ---: | ---: |\n")
		for _, o := range obs {
			b.WriteString("| `" + o.EffectID + "` | `" + o.EffectKey + "` | `" + string(o.State) + "` | `" +
				o.CleanupOwner + "` | `" + string(o.ReversalClass) + "` | " +
				strconv.Itoa(o.StepsRecorded) + "/" + strconv.Itoa(o.TotalSteps) + " | " +
				strconv.FormatInt(o.AgeBlocks, 10) + " | " +
				strconv.FormatInt(o.DeadlineHeight, 10) + " |\n")
		}
		b.WriteString("\n")
	}
	b.WriteString("[Back to Arobi Assurance Hub](/r/arobi/assurance)\n")
	return b.String()
}
