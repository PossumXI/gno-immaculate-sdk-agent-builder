// Ullumii Harness Adapter for Immaculate SDK Agent Builder.
//
// Bridges Ullumii governed tool executions, MCP calls, and work handoffs into
// deterministic RFC 6962 EvidenceBundles compatible with gno.land/r/arobi/assurance
// and cross-harness Whisper Agent Bus handoffs.

import { GnoshAssuranceSession, harnessFrameDigest, ASSURANCE_REALM_PATH } from './gnosh-adapter.mjs';
import { sha256Hex } from '../verifier/verify-evidence.mjs';

export const ULLUMII_HARNESS_ID = 'ullumii';

/**
 * UllumiiAssuranceBridge wraps an Ullumii workspace/agent run so every governed MCP tool
 * call or work handoff emits an independently verifiable RFC 6962 EvidenceBundle and a
 * ready-to-anchor Gno.land `AnchorCheckpoint` payload.
 */
export class UllumiiAssuranceBridge extends GnoshAssuranceSession {
  constructor({
    agentId,
    workspaceId,
    principal,
    caller,
    policyDigest = sha256Hex('ullumii-policy-v1'),
    chainId = 'onyx-1',
    realm = ASSURANCE_REALM_PATH,
  }) {
    super({
      agentId,
      principal,
      caller,
      sessionId: workspaceId,
      policyDigest,
      chainId,
      realm,
    });
    this.workspaceId = workspaceId;
  }

  /** Record a governed Ullumii MCP tool invocation or work handoff. */
  recordUllumiiAction({
    handoffId,
    parentHandoffId = '',
    mcpServer = 'immaculate-mcp',
    toolName,
    input = '',
    output = '',
    witness = '',
    verdict = 'ALLOW',
    reasonCode = 'ULLUMII_GATE_PASS',
    outcome = 'EXECUTED',
    riskTier = 'LOW',
    budgetUgnot = 0,
    spentUgnot = 0,
    height = 1,
  }) {
    const frame = {
      harness: ULLUMII_HARNESS_ID,
      sessionId: this.workspaceId,
      frameId: handoffId,
      parentFrameId: parentHandoffId,
      action: toolName,
      target: `${mcpServer}:${toolName}`,
      height,
    };
    const fDig = harnessFrameDigest(frame);
    const bundle = this.recordFrameEvent({
      frameId: handoffId,
      parentFrameId: parentHandoffId,
      toolName,
      target: frame.target,
      input,
      output,
      witness,
      verdict,
      reasonCode,
      outcome,
      riskTier,
      budgetUgnot,
      spentUgnot,
      height,
      extraContext: `ullumii:${fDig}`,
    });
    bundle.ullumiiFrame = frame;
    bundle.ullumiiFrameDigest = fDig;
    return bundle;
  }

  /**
   * Build a cross-harness handoff payload formatted for Arobi Whisper's Agent Bus so an
   * Ullumii agent can securely dispatch work or evidence receipts to a gnosh.ai or shell agent.
   */
  exportWhisperHandoff({ toHarness = 'gnosh.ai', toAgentId, taskPayload, correlationId }) {
    const latest = this.bundles[this.bundles.length - 1] || null;
    return {
      version: 'whisper-agent-bus/1',
      fromHarness: ULLUMII_HARNESS_ID,
      fromAgentId: this.agentId,
      toHarness,
      toAgentId,
      kind: 'handoff',
      correlationId: correlationId || `${this.workspaceId}-${this.bundles.length}`,
      evidenceRootHex: latest ? latest.accumulatorRoot : null,
      parentWarrantDigest: latest?.receipt?.warrantDigest || null,
      payloadDigestHex: sha256Hex(JSON.stringify(taskPayload)),
      payload: taskPayload,
    };
  }
}
