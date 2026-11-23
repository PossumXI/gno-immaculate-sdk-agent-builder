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

// CLI entrypoint
if (import.meta.url === `file://${process.argv[1]?.replace(/\\/g, '/')}` || process.argv[1]?.endsWith('verify-evidence.mjs')) {
  const file = process.argv[2];
  if (file) {
    const bundle = JSON.parse(fs.readFileSync(file, 'utf8'));
    const res = verifyEvidenceBundle(bundle);
    console.log(JSON.stringify(res, null, 2));
    process.exit(res.verified ? 0 : 1);
  }
}
