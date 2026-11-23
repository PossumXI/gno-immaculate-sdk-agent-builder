// gnosh.ai Harness Adapter for Immaculate SDK Agent Builder.
//
// Consumes streamed JSON / Gno `mem` frame events emitted by gnosh (`gnosh -p`,
// frame push/tool_call/tool_result/frame_pop) and converts every governed action into
// a deterministic, RFC 6962 EvidenceBundle verifiable by verifier/verify-evidence.mjs
// plus ready-to-broadcast Gno.land `AnchorCheckpoint` payloads.

import crypto from 'node:crypto';
import {
  ZERO_DIGEST_HEX,
  sha256Hex,
  projectionDigest,
  warrantDigest,
  decisionReceiptLeafHash,
  effectClosureLeafHash,
  merkleTreeHead,
  auditPath,
  verifyEvidenceBundle,
} from '../verifier/verify-evidence.mjs';

export const GNOSH_HARNESS_ID = 'gnosh.ai';
export const ASSURANCE_REALM_PATH = 'gno.land/r/arobi/assurance';

function encStr(s) {
  const b = Buffer.from(String(s ?? ''), 'utf8');
  const len = Buffer.alloc(4);
  len.writeUInt32BE(b.length, 0);
  return Buffer.concat([len, b]);
}
function encI64(n) {
  const buf = Buffer.alloc(8);
  buf.writeBigInt64BE(BigInt(n), 0);
  return buf;
}

/** Byte-for-byte twin of gno.land/p/arobi/assurance.HarnessFrame.Digest(). */
export function harnessFrameDigest(frame) {
  const raw = Buffer.concat([
    encStr('arobi-assurance-harness-frame-v1'),
    Buffer.from([1]),
    encStr(frame.harness),
    encStr(frame.sessionId),
    encStr(frame.frameId),
    encStr(frame.parentFrameId || ''),
    encStr(frame.action),
    encStr(frame.target),
    encI64(frame.height),
  ]);
  return crypto.createHash('sha256').update(raw).digest('hex');
}

/** Stateful bridge wrapping a gnosh.ai session into an RFC 6962 evidence accumulator. */
export class GnoshAssuranceSession {
  constructor({
    agentId,
    principal,
    caller,
    sessionId,
    policyDigest = sha256Hex('gnosh-default-policy-v1'),
    chainId = 'onyx-1',
    realm = ASSURANCE_REALM_PATH,
  }) {
    this.agentId = agentId;
    this.principal = principal;
    this.caller = caller;
    this.sessionId = sessionId;
    this.policyDigest = policyDigest;
    this.chainId = chainId;
    this.realm = realm;
    this.seq = 0;
    this.warrantSeq = 0;
    this.lastHash = ZERO_DIGEST_HEX;
    this.leaves = [];
    this.bundles = [];
    this.lastAnchoredRoot = ZERO_DIGEST_HEX;
  }

  /**
   * Record one gnosh.ai frame tool execution (or refusal) and return a self-verifying
   * RFC 6962 EvidenceBundle.
   */
  recordFrameEvent({
    frameId,
    parentFrameId = '',
    toolName,
    target = 'workspace',
    input = '',
    output = '',
    witness = '',
    verdict = 'ALLOW',
    reasonCode = 'GNOSH_POLICY_ALLOW',
    outcome = 'EXECUTED',
    riskTier = 'LOW',
    budgetUgnot = 0,
    spentUgnot = 0,
    height = 1,
    extraContext = '',
  }) {
    const frame = {
      harness: GNOSH_HARNESS_ID,
      sessionId: this.sessionId,
      frameId,
      parentFrameId,
      action: toolName,
      target,
      height,
    };
    const fDigHex = harnessFrameDigest(frame);
    const boundCtxBuf = Buffer.concat([
      Buffer.from(fDigHex, 'hex'),
      Buffer.from(String(extraContext), 'utf8'),
    ]);

    const projection = {
      chainId: this.chainId,
      realm: this.realm,
      agentId: this.agentId,
      principal: this.principal,
      caller: this.caller,
      action: toolName,
      target,
      inputDigest: sha256Hex(String(input)),
      contextDigest: crypto.createHash('sha256').update(boundCtxBuf).digest('hex'),
      budgetUgnot,
      riskTier,
      height,
    };
    const pDig = projectionDigest(projection);

    let warrant = null;
    let wDig = ZERO_DIGEST_HEX;
    let effectiveOutcome = outcome;
    if (verdict === 'ALLOW') {
      this.warrantSeq += 1;
      warrant = {
        id: this.warrantSeq,
        agentId: this.agentId,
        projectionDigest: pDig,
        policyDigest: this.policyDigest,
        action: toolName,
        target,
        maxSpendUgnot: budgetUgnot,
        issuedHeight: height,
        expiryHeight: height + 10,
      };
      wDig = warrantDigest(warrant);
    } else {
      effectiveOutcome = 'REFUSED';
    }

    this.seq += 1;
    const receipt = {
      seq: this.seq,
      prevHash: this.lastHash,
      chainId: this.chainId,
      realm: this.realm,
      agentId: this.agentId,
      caller: this.caller,
      projectionDigest: pDig,
      policyDigest: this.policyDigest,
      verdict,
      reasonCode,
      warrantDigest: wDig,
      height,
    };
    const rLeaf = decisionReceiptLeafHash(receipt);
    const rIdx = this.leaves.length;
    this.leaves.push(rLeaf);
    this.lastHash = rLeaf;

    this.seq += 1;
    const closure = {
      seq: this.seq,
      prevHash: this.lastHash,
      agentId: this.agentId,
      warrantDigest: wDig,
      decisionLeafHash: rLeaf,
      outputDigest: sha256Hex(String(output)),
      witnessDigest: sha256Hex(String(witness)),
      outcome: effectiveOutcome,
      spentUgnot: verdict === 'ALLOW' ? spentUgnot : 0,
      height,
    };
    const cLeaf = effectClosureLeafHash(closure);
    const cIdx = this.leaves.length;
    this.leaves.push(cLeaf);
    this.lastHash = cLeaf;

    const root = merkleTreeHead(this.leaves);
    const bundle = {
      harnessFrame: frame,
      harnessFrameDigest: fDigHex,
      projection,
      decision: { verdict, policyDigest: this.policyDigest },
      warrant,
      receipt,
      closure,
      receiptLeafIndex: rIdx,
      closureLeafIndex: cIdx,
      accumulatorSize: this.leaves.length,
      accumulatorRoot: root,
      receiptProof: auditPath(rIdx, this.leaves),
      closureProof: auditPath(cIdx, this.leaves),
    };

    const verification = verifyEvidenceBundle(bundle);
    if (!verification.verified) {
      throw new Error(`GnoshAssuranceSession internal verification failed: ${verification.errors.join('; ')}`);
    }
    this.bundles.push(bundle);
    return bundle;
  }

  /** Parse newline-delimited JSON lines from `gnosh -p --output-format stream-json`. */
  ingestNdjsonStream(ndjsonText, baseHeight = 1) {
    const recorded = [];
    let offset = 0;
    for (const rawLine of String(ndjsonText).split(/\r?\n/)) {
      const line = rawLine.trim();
      if (!line) continue;
      const ev = JSON.parse(line);
      if (ev.type === 'tool_result' || ev.type === 'frame_pop') {
        recorded.push(
          this.recordFrameEvent({
            frameId: ev.frame_id || `frame-${offset + 1}`,
            parentFrameId: ev.parent_frame_id || '',
            toolName: ev.tool || ev.action || 'gnosh_step',
            target: ev.target || 'workspace',
            input: ev.input ?? '',
            output: ev.output ?? '',
            witness: ev.witness ?? '',
            verdict: ev.verdict || 'ALLOW',
            reasonCode: ev.reason_code || 'GNOSH_FRAME_OK',
            outcome: ev.outcome || (ev.error ? 'FAILED' : 'EXECUTED'),
            riskTier: ev.risk_tier || 'LOW',
            budgetUgnot: Number(ev.budget_ugnot || 0),
            spentUgnot: Number(ev.spent_ugnot || 0),
            height: baseHeight + offset,
          }),
        );
        offset += 1;
      }
    }
    return recorded;
  }

  /** Build a Gno.land `/vm.m_call` payload to anchor this session's Merkle root on-chain. */
  buildAnchorCheckpointTx(anchorFeeUgnot = 1000) {
    const root = merkleTreeHead(this.leaves);
    const receiptCount = this.bundles.length;
    const closureCount = this.bundles.length;
    return {
      messages: [
        {
          type: '/vm.m_call',
          value: {
            caller: this.caller,
            send: anchorFeeUgnot > 0 ? `${Math.trunc(anchorFeeUgnot)}ugnot` : '',
            pkg_path: this.realm,
            func: 'AnchorCheckpoint',
            args: [
              this.agentId,
              root,
              this.lastAnchoredRoot,
              String(this.leaves.length),
              String(receiptCount),
              String(closureCount),
            ],
          },
        },
      ],
      gasFee: 1000000,
      gasWanted: 5000000,
      memo: `gnosh.ai evidence anchor (${this.sessionId})`,
    };
  }
}
