// Package assurance is the public on-chain Gno.land Agent Passport Registry and
// RFC 6962 Evidence Anchor for the Immaculate Agent SDK Builder.
//
// Any agent built with gno.land/p/arobi/assurance can register an owner-bound passport,
// anchor hash-chained evidence checkpoints into a global append-only RFC 6962 Merkle
// accumulator, and let any third party verify inclusion proofs on-chain or offline.
//
// Security model: strictly non-custodial — this public realm refuses all attached coins
// and never discloses or routes to any private payout or treasury address.
package assurance

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"

	sdk "gno.land/p/arobi/assurance"
	"gno.land/p/arobi/signals"
	"gno.land/p/nt/avl/v0"
)

const (
	// MinBlocksBetween rate-limits anchoring per agent to prevent spam.
	MinBlocksBetween int64 = 5
	// DemoAgentID is the built-in live governed agent anyone can test on gno.land.
	DemoAgentID = "immaculate-demo-agent"
)

// AgentPassport is the on-chain identity and checkpoint tip for a governed agent.
type AgentPassport struct {
	AgentID          string
	Owner            address
	DisplayName      string
	PolicyDigest     [32]byte
	MetadataURI      string
	RegisteredHeight int64
	Revoked          bool
	LastAnchorID     uint64
	LastAnchorHeight int64
	LastRoot         [32]byte
	TotalLeaves      uint64
	TotalReceipts    uint64
	TotalClosures    uint64
	AnchorCount      uint64
}

var (
	passports  = avl.NewTree() // agentID -> *AgentPassport
	agentOrder []string
	anchors    []sdk.AnchorRecord
	globalAcc  sdk.Accumulator

	// Built-in interactive governed demo agent powered directly by gno.land/p/arobi/assurance.
	demoAgent      *sdk.Agent
	demoDriftGuard *sdk.DriftGuardPolicy
	demoCoherence  *sdk.CoherenceGuardPolicy
	demoLastOut    string
	demoLastErr    string
	demoLastRoot   string
)

func ensureDemoAgent() *sdk.Agent {
	if demoAgent == nil {
		initDemoAgent()
	}
	return demoAgent
}

func demoSummarizeHandler(w sdk.EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
	digest := sdk.Hex(sdk.HashBytes(input))
	out := []byte("summarized(" + digest[:16] + ")")
	witness := []byte("warrant:" + strconv.FormatUint(w.ID, 10))
	return out, witness, 0, nil
}

func demoAttestHandler(w sdk.EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
	out := []byte("attested:" + sdk.Hex(sdk.HashBytes(input))[:16])
	witness := []byte("attest-warrant:" + strconv.FormatUint(w.ID, 10))
	return out, witness, 100, nil
}

func demoEscrowHandler(w sdk.EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
	return []byte("transferred"), nil, 500, nil
}

func demoWipeHandler(w sdk.EffectWarrant, input []byte) ([]byte, []byte, int64, error) {
	return []byte("wiped"), nil, 0, nil
}

func initDemoAgent() {
	base := signals.Baseline{
		MeanFixed: 100 * signals.Scale,
		SDFixed:   20 * signals.Scale,
	}
	b := sdk.NewAgentBuilder(DemoAgentID).
		WithChain("gnoland-testnet", "gno.land/r/arobi/assurance").
		WithPrincipal("demo-governance-principal").
		WithPolicyID("immaculate-demo-policy-v2").
		AllowActions("summarize", "attest", "escrow_transfer", "wipe_state").
		WithBudgetCap(2500).
		WithRiskGate(false, false).
		WithDriftGuard(base, 5*signals.Scale, signals.Scale, 5, false, true).
		WithCoherenceGuard(750000, false, false, false).
		WithTool(sdk.ToolSpec{
			Name:           "summarize",
			Description:    "Low-risk deterministic digest & summary action",
			RiskTier:       sdk.RiskLow,
			MaxBudgetUgnot: 1000,
		}, demoSummarizeHandler).
		WithTool(sdk.ToolSpec{
			Name:           "attest",
			Description:    "Medium-risk attestation with witness digest",
			RiskTier:       sdk.RiskMedium,
			MaxBudgetUgnot: 2500,
		}, demoAttestHandler).
		WithTool(sdk.ToolSpec{
			Name:           "escrow_transfer",
			Description:    "High-risk transfer requiring explicit human approval",
			RiskTier:       sdk.RiskHigh,
			MaxBudgetUgnot: 2500,
		}, demoEscrowHandler).
		WithTool(sdk.ToolSpec{
			Name:           "wipe_state",
			Description:    "Critical destructive operation escalated to governance",
			RiskTier:       sdk.RiskCritical,
			MaxBudgetUgnot: 0,
		}, demoWipeHandler)

	ag, err := b.Build()
	if err != nil {
		panic("init demo agent: " + err.Error())
	}
	demoAgent = ag
	demoDriftGuard = b.DriftGuard()
	demoCoherence = b.CoherenceGuard()
}

// RegisterAgent registers a new owner-bound AgentPassport on gno.land.
func RegisterAgent(cur realm, agentID, displayName, policyDigestHex, metadataURI string) {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("register agent with a direct user call")
	}
	assertNoCoinsSent()
	if !isValidAgentID(agentID) {
		panic("agentID must be 3..48 lowercase alphanumeric, hyphen, or underscore characters")
	}
	if passports.Has(agentID) {
		panic("agentID already registered: " + agentID)
	}
	if len(displayName) == 0 || len(displayName) > 80 {
		panic("displayName must be 1..80 characters")
	}
	if len(metadataURI) > 256 {
		panic("metadataURI too long (max 256)")
	}
	pDigest, err := sdk.ParseDigest(policyDigestHex)
	if err != nil {
		panic("policyDigestHex: " + err.Error())
	}

	owner := prev.Address()
	height := runtime.ChainHeight()
	pp := &AgentPassport{
		AgentID:          agentID,
		Owner:            owner,
		DisplayName:      displayName,
		PolicyDigest:     pDigest,
		MetadataURI:      metadataURI,
		RegisteredHeight: height,
	}
	passports.Set(agentID, pp)
	agentOrder = append(agentOrder, agentID)

	chain.Emit("ImmaculateAgentRegistered",
		"agent_id", agentID,
		"owner", owner.String(),
		"policy_digest", policyDigestHex,
		"height", strconv.FormatInt(height, 10),
	)
}

// UpdateAgentPolicy updates the registered policy digest for an active agent (owner only).
func UpdateAgentPolicy(cur realm, agentID, newPolicyDigestHex string) {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("update agent policy with a direct user call")
	}
	assertNoCoinsSent()
	pp := mustOwnedActiveAgent(agentID, prev.Address())
	pDigest, err := sdk.ParseDigest(newPolicyDigestHex)
	if err != nil {
		panic("newPolicyDigestHex: " + err.Error())
	}
	pp.PolicyDigest = pDigest
	chain.Emit("ImmaculateAgentPolicyUpdated",
		"agent_id", agentID,
		"policy_digest", newPolicyDigestHex,
		"height", strconv.FormatInt(runtime.ChainHeight(), 10),
	)
}

// RevokeAgent permanently revokes an agent passport so it can no longer anchor new checkpoints.
func RevokeAgent(cur realm, agentID string) {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("revoke agent with a direct user call")
	}
	assertNoCoinsSent()
	pp := mustOwnedActiveAgent(agentID, prev.Address())
	pp.Revoked = true
	chain.Emit("ImmaculateAgentRevoked",
		"agent_id", agentID,
		"owner", prev.Address().String(),
		"height", strconv.FormatInt(runtime.ChainHeight(), 10),
	)
}

// AnchorCheckpoint anchors an agent's RFC 6962 evidence accumulator root on gno.land.
//
// Enforces:
//   - Direct user call by the registered, non-revoked agent owner
//   - Zero coin custody (refuses any attached coins)
//   - Strict prevRoot chaining (prevents rollback / equivocation)
//   - Monotonic leaf, receipt, and closure counters
//   - Per-agent block rate limit
func AnchorCheckpoint(
	cur realm,
	agentID string,
	checkpointRootHex string,
	prevRootHex string,
	leafCount uint64,
	receiptCount uint64,
	closureCount uint64,
) uint64 {
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("anchor with a direct user call")
	}
	assertNoCoinsSent()
	caller := prev.Address()
	pp := mustOwnedActiveAgent(agentID, caller)

	cpRoot, err := sdk.ParseDigest(checkpointRootHex)
	if err != nil {
		panic("checkpointRootHex: " + err.Error())
	}
	prevRoot, err := sdk.ParseDigest(prevRootHex)
	if err != nil {
		panic("prevRootHex: " + err.Error())
	}
	if prevRoot != pp.LastRoot {
		panic("prevRoot mismatch: expected " + sdk.Hex(pp.LastRoot) + ", got " + prevRootHex)
	}
	if leafCount == 0 || leafCount < pp.TotalLeaves {
		panic("leafCount must be positive and non-decreasing")
	}
	if receiptCount < pp.TotalReceipts || closureCount < pp.TotalClosures {
		panic("receiptCount and closureCount must be non-decreasing")
	}
	if leafCount == pp.TotalLeaves && cpRoot == pp.LastRoot {
		panic("checkpoint has no new evidence leaves since last anchor")
	}

	height := runtime.ChainHeight()
	if pp.AnchorCount > 0 && height-pp.LastAnchorHeight < MinBlocksBetween {
		panic("rate limit: wait " + strconv.FormatInt(MinBlocksBetween, 10) + " blocks between anchors for " + agentID)
	}

	rec := sdk.AnchorRecord{
		ChainID:        runtime.ChainID(),
		Realm:          cur.PkgPath(),
		AnchorID:       uint64(len(anchors)) + 1,
		AgentID:        agentID,
		Caller:         caller.String(),
		Height:         height,
		PrevRoot:       prevRoot,
		CheckpointRoot: cpRoot,
		LeafCount:      leafCount,
		ReceiptCount:   receiptCount,
		ClosureCount:   closureCount,
	}

	leaf := rec.LeafHash()
	anchors = append(anchors, rec)
	globalAcc.Append(leaf)

	pp.LastAnchorID = rec.AnchorID
	pp.LastAnchorHeight = height
	pp.LastRoot = cpRoot
	pp.TotalLeaves = leafCount
	pp.TotalReceipts = receiptCount
	pp.TotalClosures = closureCount
	pp.AnchorCount++

	chain.Emit("ImmaculateAssuranceAnchor",
		"id", strconv.FormatUint(rec.AnchorID, 10),
		"agent_id", agentID,
		"checkpoint_root", checkpointRootHex,
		"leaf", sdk.Hex(leaf),
		"size", strconv.FormatUint(globalAcc.Size(), 10),
		"global_root", sdk.Hex(globalAcc.Root()),
		"height", strconv.FormatInt(height, 10),
	)

	return rec.AnchorID
}

// RunDemoAction executes a live action through the built-in Immaculate SDK demo agent.
// Anyone can call this on testnet (zero coins) to observe fail-closed policy verdicts,
// single-use warrant issuance, hash-chained closures, and self-verifying RFC 6962 bundles.
func RunDemoAction(cur realm, action, target, payload string, budgetUgnot int64) string {
	assertNoCoinsSent()
	caller := cur.Previous().Address().String()
	height := runtime.ChainHeight()
	out, bundle, err := ensureDemoAgent().Execute(caller, action, target, []byte(payload), []byte("gno-live-demo"), budgetUgnot, height)
	if vErr := bundle.Verify(); vErr != nil {
		panic("internal evidence bundle verification failed: " + vErr.Error())
	}

	demoLastRoot = sdk.Hex(bundle.AccumulatorRoot)
	if err != nil {
		demoLastOut = ""
		demoLastErr = err.Error()
	} else {
		demoLastOut = string(out)
		demoLastErr = ""
	}

	chain.Emit("ImmaculateDemoEvidence",
		"agent_id", DemoAgentID,
		"action", action,
		"verdict", string(bundle.Decision.Verdict),
		"outcome", string(bundle.Closure.Outcome),
		"receipt_leaf", sdk.Hex(bundle.Receipt.LeafHash()),
		"closure_leaf", sdk.Hex(bundle.Closure.LeafHash()),
		"acc_root", demoLastRoot,
		"acc_size", strconv.FormatUint(bundle.AccumulatorSize, 10),
	)

	return string(bundle.Decision.Verdict) + "|" + string(bundle.Closure.Outcome) + "|" + demoLastRoot
}

// RunAdaptiveDemoAction stages a spherical coherence score (in fixed-point Scale=1_000_000)
// and executes through the Hampel-guarded CUSUM + Coherence + RiskGate demo agent.
// Pass coherenceScoreFixed < 750000 to see memory-poisoning refusal live on-chain.
func RunAdaptiveDemoAction(cur realm, action, target, payload string, budgetUgnot, coherenceScoreFixed int64) string {
	_ = ensureDemoAgent()
	if demoCoherence != nil {
		demoCoherence.StageScore(coherenceScoreFixed)
	}
	return RunDemoAction(cur, action, target, payload, budgetUgnot)
}

// ResetDemoCircuitBreaker resets a latched drift circuit breaker on the live demo agent.
func ResetDemoCircuitBreaker(cur realm) {
	assertNoCoinsSent()
	_ = ensureDemoAgent()
	if demoDriftGuard != nil {
		demoDriftGuard.Reset()
	}
}

// Size returns the total number of anchored agent evidence checkpoints.
func Size() uint64 {
	return globalAcc.Size()
}

// Root returns the global RFC 6962 accumulator root across all anchored checkpoints.
func Root() string {
	return sdk.Hex(globalAcc.Root())
}

// DemoRoot returns the current RFC 6962 evidence root of the built-in live demo agent.
func DemoRoot() string {
	return sdk.Hex(ensureDemoAgent().Checkpoint().CheckpointRoot)
}

// ProofFor returns the comma-separated RFC 6962 inclusion proof for anchorID at treeSize.
func ProofFor(anchorID, treeSize uint64) string {
	if anchorID == 0 || anchorID > uint64(len(anchors)) {
		panic("no anchor " + strconv.FormatUint(anchorID, 10))
	}
	proof, err := globalAcc.Proof(anchorID-1, treeSize)
	if err != nil {
		panic(err.Error())
	}
	parts := make([]string, len(proof))
	for i, h := range proof {
		parts[i] = sdk.Hex(h)
	}
	return strings.Join(parts, ",")
}

// VerifyCheckpointProof verifies an RFC 6962 inclusion proof on-chain against the historical root at treeSize.
func VerifyCheckpointProof(anchorID, treeSize uint64, leafHex, proofCSV string) bool {
	if anchorID == 0 || anchorID > treeSize || treeSize > globalAcc.Size() {
		return false
	}
	leaf, err := sdk.ParseDigest(leafHex)
	if err != nil {
		return false
	}
	rootAt, err := globalAcc.RootAt(treeSize)
	if err != nil {
		return false
	}
	var proof [][32]byte
	if strings.TrimSpace(proofCSV) != "" {
		for _, tok := range strings.Split(proofCSV, ",") {
			d, err := sdk.ParseDigest(strings.TrimSpace(tok))
			if err != nil {
				return false
			}
			proof = append(proof, d)
		}
	}
	return sdk.VerifyInclusion(anchorID-1, treeSize, leaf, proof, rootAt)
}

// AnchorLeafHex returns the RFC 6962 leaf hash of anchorID.
func AnchorLeafHex(anchorID uint64) string {
	if anchorID == 0 || anchorID > uint64(len(anchors)) {
		panic("no anchor " + strconv.FormatUint(anchorID, 10))
	}
	return sdk.Hex(anchors[anchorID-1].LeafHash())
}

func mustOwnedActiveAgent(agentID string, caller address) *AgentPassport {
	pp, ok := passports.Get(agentID).(*AgentPassport)
	if !ok || pp == nil {
		panic("agent not registered: " + agentID)
	}
	if pp.Owner != caller {
		panic("only agent owner " + pp.Owner.String() + " may act for " + agentID)
	}
	if pp.Revoked {
		panic("agent passport is revoked: " + agentID)
	}
	return pp
}

func isValidAgentID(id string) bool {
	if len(id) < 3 || len(id) > 48 {
		return false
	}
	for i := 0; i < len(id); i++ {
		c := id[i]
		ok := (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_'
		if !ok {
			return false
		}
	}
	return true
}

func assertNoCoinsSent() {
	for _, c := range unsafe.OriginSend() {
		if c.Amount != 0 {
			panic("non-custodial anchor realm refuses attached coins")
		}
	}
}
