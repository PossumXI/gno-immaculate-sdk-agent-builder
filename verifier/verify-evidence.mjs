// Arobi Assurance Agent SDK — Standalone Zero-Dependency Offline Evidence Verifier.
//
// Byte-for-byte twin of gno.land/p/arobi/assurance (encoding version 1, RFC 6962 / RFC 9162).
// Verifies PolicyInputProjection digests, EffectWarrant bindings, DecisionReceipt &
// EffectClosure hash-chain links, and RFC 6962 Merkle inclusion proofs without trusting
// the executing agent or any centralized server.
//
// CLI usage:
//   node verifier/verify-evidence.mjs <evidence-bundle.json>

import crypto from 'node:crypto';
import fs from 'node:fs';

export const ENCODING_VERSION = 1;
export const DOMAIN_PROJECTION = 'arobi-assurance-projection-v1';
export const DOMAIN_WARRANT = 'arobi-assurance-warrant-v1';
export const DOMAIN_RECEIPT = 'arobi-assurance-decision-receipt-v1';
export const DOMAIN_CLOSURE = 'arobi-assurance-effect-closure-v1';
export const DOMAIN_ANCHOR = 'arobi-assurance-anchor-v1';
export const DOMAIN_CHECKPOINT = 'arobi-checkpoint-v1';
export const DOMAIN_EXEC_RECEIPT = 'arobi-exec-receipt-v1';
export const DOMAIN_EFFECT_EVENT = 'arobi-assurance-effect-event-v1';
export const ZERO_DIGEST_HEX = '0'.repeat(64);

export function sha256(buf) {
  return crypto.createHash('sha256').update(buf).digest();
}

export function sha256Hex(data) {
  return sha256(typeof data === 'string' ? Buffer.from(data, 'utf8') : data).toString('hex');
}

export function fromDigestHex(hex) {
  if (typeof hex !== 'string' || !/^[0-9a-f]{64}$/.test(hex)) {
    throw new Error(`invalid 64-char lowercase hex digest: ${String(hex)}`);
  }
  return Buffer.from(hex, 'hex');
}

function encStr(s) {
  const bytes = Buffer.from(String(s ?? ''), 'utf8');
  const len = Buffer.alloc(4);
  len.writeUInt32BE(bytes.length, 0);
  return Buffer.concat([len, bytes]);
}

function encU32(n) {
  const buf = Buffer.alloc(4);
  buf.writeUInt32BE(Number(n) >>> 0, 0);
  return buf;
}

function encU64(n) {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64BE(BigInt(n), 0);
  return buf;
}

function encI64(n) {
  const buf = Buffer.alloc(8);
  buf.writeBigInt64BE(BigInt(n), 0);
  return buf;
}

export function leafHash(data) {
  const bytes = Buffer.isBuffer(data) ? data : Buffer.from(data);
  return sha256(Buffer.concat([Buffer.from([0x00]), bytes]));
}

export function nodeHash(left, right) {
  return sha256(Buffer.concat([Buffer.from([0x01]), left, right]));
}

export function encodeProjection(p) {
  return Buffer.concat([
    encStr(DOMAIN_PROJECTION),
    Buffer.from([ENCODING_VERSION]),
    encStr(p.chainId),
    encStr(p.realm),
    encStr(p.agentId),
    encStr(p.principal),
    encStr(p.caller),
    encStr(p.action),
    encStr(p.target),
    fromDigestHex(p.inputDigest),
    fromDigestHex(p.contextDigest),
    encI64(p.budgetUgnot),
    encStr(p.riskTier),
    encI64(p.height),
  ]);
}

export function projectionDigest(p) {
  return sha256(encodeProjection(p)).toString('hex');
}

export function encodeWarrant(w) {
  return Buffer.concat([
    encStr(DOMAIN_WARRANT),
    Buffer.from([ENCODING_VERSION]),
    encU64(w.id),
    encStr(w.agentId),
    fromDigestHex(w.projectionDigest),
    fromDigestHex(w.policyDigest),
    encStr(w.action),
    encStr(w.target),
    encI64(w.maxSpendUgnot),
    encI64(w.issuedHeight),
    encI64(w.expiryHeight),
  ]);
}

export function warrantDigest(w) {
  return sha256(encodeWarrant(w)).toString('hex');
}

export function encodeDecisionReceipt(r) {
  return Buffer.concat([
    encStr(DOMAIN_RECEIPT),
    Buffer.from([ENCODING_VERSION]),
    encU64(r.seq),
    fromDigestHex(r.prevHash),
    encStr(r.chainId),
    encStr(r.realm),
    encStr(r.agentId),
    encStr(r.caller),
    fromDigestHex(r.projectionDigest),
    fromDigestHex(r.policyDigest),
    encStr(r.verdict),
    encStr(r.reasonCode),
    fromDigestHex(r.warrantDigest),
    encI64(r.height),
  ]);
}

export function decisionReceiptLeafHash(r) {
  return leafHash(encodeDecisionReceipt(r)).toString('hex');
}

export function encodeEffectClosure(c) {
  return Buffer.concat([
    encStr(DOMAIN_CLOSURE),
    Buffer.from([ENCODING_VERSION]),
    encU64(c.seq),
    fromDigestHex(c.prevHash),
    encStr(c.agentId),
    fromDigestHex(c.warrantDigest),
    fromDigestHex(c.decisionLeafHash),
    fromDigestHex(c.outputDigest),
    fromDigestHex(c.witnessDigest),
    encStr(c.outcome),
    encI64(c.spentUgnot),
    encI64(c.height),
  ]);
}

export function effectClosureLeafHash(c) {
  return leafHash(encodeEffectClosure(c)).toString('hex');
}

export function encodeAnchorRecord(a) {
  return Buffer.concat([
    encStr(DOMAIN_ANCHOR),
    Buffer.from([ENCODING_VERSION]),
    encStr(a.chainId),
    encStr(a.realm),
    encU64(a.anchorId),
    encStr(a.agentId),
    encStr(a.caller),
    encI64(a.height),
    fromDigestHex(a.prevRoot),
    fromDigestHex(a.checkpointRoot),
    encU64(a.leafCount),
    encU64(a.receiptCount),
    encU64(a.closureCount),
  ]);
}

export function anchorRecordLeafHash(a) {
  return leafHash(encodeAnchorRecord(a)).toString('hex');
}

/** RFC 9162 section 2.1.3.2 inclusion proof verifier. */
export function verifyInclusion(index, size, leafHex, proofHexList, rootHex) {
  let fn = BigInt(index);
  const total = BigInt(size);
  if (fn < 0n || fn >= total) return false;
  let sn = total - 1n;
  let r = fromDigestHex(leafHex);
  const expectedRoot = fromDigestHex(rootHex);

  for (const stepHex of proofHexList) {
    if (sn === 0n) return false;
    const p = fromDigestHex(stepHex);
    if ((fn & 1n) === 1n || fn === sn) {
      r = nodeHash(p, r);
      if ((fn & 1n) === 0n) {
        while ((fn & 1n) === 0n && fn !== 0n) {
          fn >>= 1n;
          sn >>= 1n;
        }
      }
    } else {
      r = nodeHash(r, p);
    }
    fn >>= 1n;
    sn >>= 1n;
  }
  return sn === 0n && r.equals(expectedRoot);
}

/** Recompute RFC 6962 MTH(D[n]) from leaf hashes (for test & audit tooling). */
export function merkleTreeHead(leafHexList) {
  const n = leafHexList.length;
  if (n === 0) return sha256(Buffer.alloc(0)).toString('hex');
  if (n === 1) return fromDigestHex(leafHexList[0]).toString('hex');
  let k = 1;
  while (k * 2 < n) k *= 2;
  const left = fromDigestHex(merkleTreeHead(leafHexList.slice(0, k)));
  const right = fromDigestHex(merkleTreeHead(leafHexList.slice(k)));
  return nodeHash(left, right).toString('hex');
}

/** Generate RFC 6962 audit path for leaf index m in leaves[0..n). */
export function auditPath(m, leafHexList) {
  const n = leafHexList.length;
  if (n <= 1) return [];
  let k = 1;
  while (k * 2 < n) k *= 2;
  if (m < k) {
    return [...auditPath(m, leafHexList.slice(0, k)), merkleTreeHead(leafHexList.slice(k))];
  }
  return [...auditPath(m - k, leafHexList.slice(k)), merkleTreeHead(leafHexList.slice(0, k))];
}

function subproof(m, leafHexList, startFromOldRoot) {
  const n = leafHexList.length;
  if (m === n) {
    return startFromOldRoot ? [] : [merkleTreeHead(leafHexList)];
  }
  let k = 1;
  while (k * 2 < n) k *= 2;
  if (m <= k) {
    return [...subproof(m, leafHexList.slice(0, k), startFromOldRoot), merkleTreeHead(leafHexList.slice(k))];
  }
  return [...subproof(m - k, leafHexList.slice(k), false), merkleTreeHead(leafHexList.slice(0, k))];
}

/** Generate RFC 6962 / RFC 9162 section 2.1.4.2 Merkle consistency proof between sizes first and second. */
export function consistencyProof(first, second, leafHexList) {
  const f = Number(first);
  const s = Number(second);
  if (!Number.isInteger(f) || !Number.isInteger(s) || f <= 0 || f > s || s > leafHexList.length) {
    throw new Error(`invalid consistency proof range: first=${first} second=${second} total=${leafHexList.length}`);
  }
  return subproof(f, leafHexList.slice(0, s), true);
}

/** Verify RFC 6962 / RFC 9162 section 2.1.4.2 Merkle consistency proof offline. */
export function verifyConsistencyProof(first, second, firstRootHex, secondRootHex, proofHexList) {
  const f = BigInt(first);
  const s = BigInt(second);
  if (f <= 0n || f > s || !Array.isArray(proofHexList)) return false;
  const firstRoot = fromDigestHex(firstRootHex);
  const secondRoot = fromDigestHex(secondRootHex);
  if (f === s) {
    return proofHexList.length === 0 && firstRoot.equals(secondRoot);
  }
  if (proofHexList.length === 0) return false;

  let node;
  let idx = 0;
  if ((f & (f - 1n)) === 0n) {
    node = firstRoot;
  } else {
    node = fromDigestHex(proofHexList[0]);
    idx = 1;
  }

  let fn = f - 1n;
  let sn = s - 1n;
  while ((fn & 1n) === 1n) {
    fn >>= 1n;
    sn >>= 1n;
  }

  let fr = node;
  let sr = node;
  for (; idx < proofHexList.length; idx++) {
    if (sn === 0n) return false;
    const c = fromDigestHex(proofHexList[idx]);
    if ((fn & 1n) === 1n || fn === sn) {
      fr = nodeHash(c, fr);
      sr = nodeHash(c, sr);
      if ((fn & 1n) === 0n) {
        while ((fn & 1n) === 0n && fn !== 0n) {
          fn >>= 1n;
          sn >>= 1n;
        }
      }
    } else {
      sr = nodeHash(sr, c);
    }
    fn >>= 1n;
    sn >>= 1n;
  }
  return sn === 0n && fr.equals(firstRoot) && sr.equals(secondRoot);
}

/** Independently verify a full EvidenceBundle exported from a Gno agent. */
export function verifyEvidenceBundle(b) {
  const errors = [];
  const projDig = projectionDigest(b.projection);
  if (b.receipt.projectionDigest !== projDig) errors.push('receipt projectionDigest mismatch');
  if (b.receipt.policyDigest !== b.decision.policyDigest) errors.push('receipt policyDigest mismatch');
  if (b.receipt.verdict !== b.decision.verdict) errors.push('receipt verdict mismatch');

  if (b.decision.verdict === 'ALLOW') {
    if (!b.warrant) {
      errors.push('ALLOW decision missing warrant');
    } else {
      const wDig = warrantDigest(b.warrant);
      if (b.warrant.projectionDigest !== projDig) errors.push('warrant projectionDigest mismatch');
      if (b.warrant.policyDigest !== b.decision.policyDigest) errors.push('warrant policyDigest mismatch');
      if (b.receipt.warrantDigest !== wDig) errors.push('receipt warrantDigest mismatch');
      if (b.closure.warrantDigest !== wDig) errors.push('closure warrantDigest mismatch');
    }
  } else {
    if (b.warrant) errors.push('non-ALLOW decision must not carry a warrant');
    if (b.receipt.warrantDigest !== ZERO_DIGEST_HEX || b.closure.warrantDigest !== ZERO_DIGEST_HEX) {
      errors.push('non-ALLOW decision must have zero warrantDigest');
    }
    if (b.closure.outcome !== 'REFUSED') errors.push('non-ALLOW decision must close as REFUSED');
  }

  const rLeaf = decisionReceiptLeafHash(b.receipt);
  const cLeaf = effectClosureLeafHash(b.closure);
  if (b.closure.decisionLeafHash !== rLeaf) errors.push('closure decisionLeafHash mismatch');
  if (b.closure.prevHash !== rLeaf) errors.push('closure prevHash does not chain to receipt leaf');

  if (!verifyInclusion(b.receiptLeafIndex, b.accumulatorSize, rLeaf, b.receiptProof, b.accumulatorRoot)) {
    errors.push('decision receipt RFC 6962 inclusion proof failed');
  }
  if (!verifyInclusion(b.closureLeafIndex, b.accumulatorSize, cLeaf, b.closureProof, b.accumulatorRoot)) {
    errors.push('effect closure RFC 6962 inclusion proof failed');
  }

  return {
    verified: errors.length === 0,
    projectionDigest: projDig,
    receiptLeafHash: rLeaf,
    closureLeafHash: cLeaf,
    errors,
  };
}

/** Canonical byte-for-byte twin of CanonicalCheckpoint.Encode (Experiment E14). */
export function encodeCanonicalCheckpoint(c) {
  const chainID = c?.chainID ?? c?.chainId;
  if (!chainID) throw new Error('checkpoint chainID required');
  if (BigInt(c.height ?? 0) <= 0n) throw new Error('checkpoint height must be > 0');
  return Buffer.concat([
    encStr(DOMAIN_CHECKPOINT),
    Buffer.from([ENCODING_VERSION]),
    encStr(chainID),
    encU64(c.height),
    fromDigestHex(c.headerHash),
    fromDigestHex(c.appHash),
    fromDigestHex(c.validatorsHash),
    fromDigestHex(c.nextValidatorsHash),
  ]);
}

export function checkpointDigest(c) {
  return sha256(encodeCanonicalCheckpoint(c)).toString('hex');
}

/** Canonical byte-for-byte twin of ExecutionReceipt.Encode (Experiment E14). */
export function encodeExecutionReceipt(r) {
  const chainID = r?.chainID ?? r?.chainId;
  if (!chainID) throw new Error('receipt chainID required');
  if (BigInt(r.height ?? 0) <= 0n) throw new Error('receipt height must be > 0');
  if (!r.caller || !r.contract) throw new Error('receipt caller and contract required');
  return Buffer.concat([
    encStr(DOMAIN_EXEC_RECEIPT),
    Buffer.from([ENCODING_VERSION]),
    encStr(chainID),
    encU64(r.height),
    encU32(r.txIndex),
    fromDigestHex(r.txHash),
    encStr(r.caller),
    encStr(r.contract),
    encU64(r.gasUsed),
    encU32(r.exitCode),
    fromDigestHex(r.resultHash),
  ]);
}

export function execReceiptLeafHash(r) {
  return leafHash(encodeExecutionReceipt(r)).toString('hex');
}

/**
 * Enforces strictly increasing (height, txIndex) order and single-chain membership across
 * execution receipts, returning their RFC 6962 leaf hashes and Merkle root (Experiment E14).
 */
export function buildOrderedReceiptTree(receipts) {
  if (!Array.isArray(receipts) || receipts.length === 0) {
    throw new Error('receipt batch cannot be empty');
  }
  const chainID = receipts[0]?.chainID ?? receipts[0]?.chainId;
  if (!chainID) throw new Error('receipt chainID required');
  const leaves = [];
  let prevHeight = 0n;
  let prevTx = -1;
  for (let i = 0; i < receipts.length; i++) {
    const rec = receipts[i];
    const recChain = rec?.chainID ?? rec?.chainId;
    if (recChain !== chainID) throw new Error('mixed chainID inside receipt batch');
    const h = BigInt(rec.height);
    const tx = Number(rec.txIndex);
    if (i > 0 && (h < prevHeight || (h === prevHeight && tx <= prevTx))) {
      throw new Error('execution receipts must be in strictly increasing (height, tx_index) order');
    }
    leaves.push(execReceiptLeafHash(rec));
    prevHeight = h;
    prevTx = tx;
  }
  return {
    chainID,
    count: leaves.length,
    leaves,
    root: merkleTreeHead(leaves),
  };
}

/** Independently verify a cross-chain checkpoint and/or strictly-ordered execution receipt batch. */
export function verifyCrossChainCheckpoint({
  checkpoint,
  receipts,
  expectedCheckpointDigest,
  expectedReceiptRoot,
  expectedReceiptsRoot,
  verifyIndex,
  targetReceiptIndex,
  targetProof,
}) {
  const errors = [];
  const expRoot = expectedReceiptRoot ?? expectedReceiptsRoot;
  const idx = verifyIndex ?? targetReceiptIndex;
  let computedCheckpointDigest = null;
  if (checkpoint) {
    try {
      computedCheckpointDigest = checkpointDigest(checkpoint);
      if (expectedCheckpointDigest && computedCheckpointDigest !== expectedCheckpointDigest) {
        errors.push('checkpoint digest mismatch');
      }
    } catch (err) {
      errors.push(String(err.message || err));
    }
  }
  let tree = null;
  let inclusionProof = null;
  let inclusionVerified = null;
  if (receipts) {
    try {
      tree = buildOrderedReceiptTree(receipts);
      const cpChain = checkpoint?.chainID ?? checkpoint?.chainId;
      if (checkpoint && tree.chainID !== cpChain) {
        errors.push('receipt batch chainID does not match checkpoint chainID');
      }
      if (expRoot && tree.root !== expRoot) {
        errors.push('receipt tree root mismatch');
      }
      if (Number.isInteger(idx) && idx >= 0 && idx < tree.count) {
        inclusionProof = targetProof ?? auditPath(idx, tree.leaves);
        inclusionVerified = verifyInclusion(idx, tree.count, tree.leaves[idx], inclusionProof, expRoot ?? tree.root);
        if (!inclusionVerified) errors.push('receipt inclusion proof failed');
      }
    } catch (err) {
      errors.push(String(err.message || err));
    }
  }
  return {
    verified: errors.length === 0,
    checkpointDigest: computedCheckpointDigest,
    receiptRoot: tree?.root ?? null,
    receiptCount: tree?.count ?? 0,
    inclusionProof,
    inclusionVerified,
    errors,
  };
}

/**
 * Canonical byte-for-byte twin of gno.land/p/arobi/assurance EffectEvent.Encode().
 * Encodes one partial-effect lifecycle transition (START, STEP, CLOSE, IN_DOUBT, COMPENSATE, ACCEPT).
 */
export function encodeEffectEvent(e) {
  return Buffer.concat([
    encStr(DOMAIN_EFFECT_EVENT),
    Buffer.from([ENCODING_VERSION]),
    encU64(e.seq),
    fromDigestHex(e.prevHash),
    encStr(e.effectId),
    encStr(e.effectKey),
    encStr(e.idempotencyKey),
    encStr(e.kind),
    encStr(e.state),
    encU32(e.stepIndex ?? 0),
    encU32(e.totalSteps ?? 0),
    encStr(e.actor),
    encStr(e.owner),
    encStr(e.reversalClass),
    Buffer.from([e.stateChanged ? 1 : 0]),
    fromDigestHex(e.readbackDigest ?? ZERO_DIGEST_HEX),
    encStr(e.supersedesId ?? ''),
    encStr(e.humanApproval ?? ''),
    encI64(e.deadlineHeight ?? 0),
    encI64(e.height ?? 0),
  ]);
}

export function effectEventLeafHash(e) {
  return leafHash(encodeEffectEvent(e)).toString('hex');
}

const VALID_REVERSAL_CLASSES = new Set(['REVERSIBLE', 'COMPENSABLE', 'IRREVERSIBLE']);

/**
 * Independently verify an entire partial-effect lifecycle hash chain & RFC 6962 accumulator offline.
 * Checks hash-chain links, Merkle root, deadline proofs for IN_DOUBT, human approval for IRREVERSIBLE
 * and ACCEPTED, read-back verification for COMMITTED, and linked reversal proof for COMPENSATED.
 */
export function verifyEffectLifecycleChain(bundle) {
  const errors = [];
  const events = Array.isArray(bundle) ? bundle : bundle?.events;
  const expectedRoot = Array.isArray(bundle) ? null : (bundle?.expectedRootHex ?? bundle?.rootHex ?? null);
  if (!Array.isArray(events) || events.length === 0) {
    return { verified: false, rootHex: null, eventCount: 0, finalStates: {}, leaves: [], errors: ['lifecycle event list is empty'] };
  }

  const leaves = [];
  const finalStates = {};
  const committedCompensations = new Map();
  let prevLeaf = ZERO_DIGEST_HEX;

  for (let i = 0; i < events.length; i++) {
    const ev = events[i];
    const expectedSeq = i + 1;
    if (Number(ev.seq) !== expectedSeq) {
      errors.push(`event[${i}] seq expected ${expectedSeq}, got ${ev.seq}`);
    }
    if (ev.prevHash !== prevLeaf) {
      errors.push(`event[${i}] prevHash chain break`);
    }
    if (!ev.effectId || !ev.effectKey || !ev.idempotencyKey) {
      errors.push(`event[${i}] missing effectId, effectKey, or idempotencyKey`);
    }
    if (!ev.owner) {
      errors.push(`event[${i}] missing cleanup owner`);
    }
    if (!VALID_REVERSAL_CLASSES.has(ev.reversalClass)) {
      errors.push(`event[${i}] invalid reversalClass: ${String(ev.reversalClass)}`);
    }

    const readback = ev.readbackDigest ?? ZERO_DIGEST_HEX;
    if (ev.kind === 'START') {
      if (BigInt(ev.deadlineHeight ?? 0) <= BigInt(ev.height ?? 0)) {
        errors.push(`event[${i}] START deadline must be strictly greater than start height/timestamp`);
      }
      if (ev.reversalClass === 'IRREVERSIBLE' && !String(ev.humanApproval || '').trim()) {
        errors.push(`event[${i}] IRREVERSIBLE effect started without humanApproval`);
      }
    } else if (ev.kind === 'IN_DOUBT') {
      if (BigInt(ev.height ?? 0) < BigInt(ev.deadlineHeight ?? 0)) {
        errors.push(`event[${i}] IN_DOUBT recorded before deadline`);
      }
    } else if (ev.kind === 'CLOSE' && ev.state === 'COMMITTED') {
      if (!ev.stateChanged || readback === ZERO_DIGEST_HEX) {
        errors.push(`event[${i}] COMMITTED requires stateChanged=true and non-zero readbackDigest`);
      }
      if (Number(ev.stepIndex ?? 0) < Number(ev.totalSteps ?? 1)) {
        errors.push(`event[${i}] COMMITTED requires all declared steps recorded`);
      }
    } else if (ev.kind === 'COMPENSATE' && ev.state === 'COMMITTED') {
      if (!ev.stateChanged || readback === ZERO_DIGEST_HEX || !ev.supersedesId) {
        errors.push(`event[${i}] compensation commit missing supersedesId or non-zero restored readbackDigest`);
      } else {
        committedCompensations.set(ev.effectId, { supersedesId: ev.supersedesId, readbackDigest: readback });
      }
    } else if (ev.kind === 'COMPENSATE' && ev.state === 'COMPENSATED') {
      if (!ev.supersedesId || !ev.stateChanged || readback === ZERO_DIGEST_HEX) {
        errors.push(`event[${i}] COMPENSATED missing linked compensation id or restored readbackDigest`);
      } else {
        const linked = committedCompensations.get(ev.supersedesId);
        if (!linked || linked.supersedesId !== ev.effectId || linked.readbackDigest !== readback) {
          errors.push(`event[${i}] COMPENSATED linked reversal ${ev.supersedesId} not verified in chain`);
        }
      }
    } else if (ev.kind === 'ACCEPT' && ev.state === 'ACCEPTED') {
      if (!String(ev.humanApproval || '').trim() || readback === ZERO_DIGEST_HEX) {
        errors.push(`event[${i}] ACCEPTED requires humanApproval and non-zero reason readbackDigest`);
      }
    }

    let leaf;
    try {
      leaf = effectEventLeafHash(ev);
    } catch (err) {
      errors.push(`event[${i}] encode error: ${String(err.message || err)}`);
      leaf = ZERO_DIGEST_HEX;
    }
    if (ev.leafHash && ev.leafHash !== leaf) {
      errors.push(`event[${i}] leafHash mismatch`);
    }
    leaves.push(leaf);
    prevLeaf = leaf;
    finalStates[ev.effectId] = ev.state;
  }

  const rootHex = merkleTreeHead(leaves);
  if (expectedRoot && rootHex !== expectedRoot) {
    errors.push(`lifecycle RFC 6962 root mismatch: expected ${expectedRoot}, got ${rootHex}`);
  }
  if (!Array.isArray(bundle) && bundle?.targetEffectId && bundle?.expectedFinalState) {
    const gotState = finalStates[bundle.targetEffectId];
    if (gotState !== bundle.expectedFinalState) {
      errors.push(`effect ${bundle.targetEffectId} final state expected ${bundle.expectedFinalState}, got ${gotState}`);
    }
  }

  return {
    verified: errors.length === 0,
    rootHex,
    eventCount: events.length,
    finalStates,
    leaves,
    errors,
  };
}

// CLI entrypoint
if (import.meta.url === `file://${process.argv[1]?.replace(/\\/g, '/')}` || process.argv[1]?.endsWith('verify-evidence.mjs')) {
  const file = process.argv[2];
  if (file) {
    const bundle = JSON.parse(fs.readFileSync(file, 'utf8'));
    const res = Array.isArray(bundle?.events) && !bundle?.projection
      ? verifyEffectLifecycleChain(bundle)
      : verifyEvidenceBundle(bundle);
    console.log(JSON.stringify(res, null, 2));
    process.exit(res.verified ? 0 : 1);
  }
}
