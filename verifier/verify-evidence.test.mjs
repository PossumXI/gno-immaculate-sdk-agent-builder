import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ZERO_DIGEST_HEX,
  sha256Hex,
  projectionDigest,
  warrantDigest,
  decisionReceiptLeafHash,
  effectClosureLeafHash,
  anchorRecordLeafHash,
  merkleTreeHead,
  auditPath,
  verifyInclusion,
  verifyEvidenceBundle,
} from './verify-evidence.mjs';

test('RFC 6962 accumulator and proofs verify for every leaf and reject tampering', () => {
  assert.equal(merkleTreeHead([]), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');

  const leaves = Array.from({ length: 6 }, (_, i) => sha256Hex(`leaf-${i}`));
  const root = merkleTreeHead(leaves);
  for (let i = 0; i < leaves.length; i++) {
    const proof = auditPath(i, leaves);
    assert.equal(verifyInclusion(i, leaves.length, leaves[i], proof, root), true);
    const badLeaf = (leaves[i][0] === '0' ? '1' : '0') + leaves[i].slice(1);
    assert.equal(verifyInclusion(i, leaves.length, badLeaf, proof, root), false);
  }
});

test('verifyEvidenceBundle validates allowed execution and catches forgery', () => {
  const policyDigest = sha256Hex('policy:demo-v1');
  const projection = {
    chainId: 'gnoland-testnet',
    realm: 'gno.land/r/arobi/assurance',
    agentId: 'immaculate-worker-1',
    principal: 'g1principal000000000000000000000000000000',
    caller: 'g1operator',
    action: 'summarize',
    target: 'doc:spec',
    inputDigest: sha256Hex('hello'),
    contextDigest: sha256Hex('ctx-1'),
    budgetUgnot: 500,
    riskTier: 'LOW',
    height: 100,
  };
  const pDig = projectionDigest(projection);
  const warrant = {
    id: 1,
    agentId: 'ullumii-worker-1',
    projectionDigest: pDig,
    policyDigest,
    action: 'summarize',
    target: 'doc:spec',
    maxSpendUgnot: 500,
    issuedHeight: 100,
    expiryHeight: 110,
  };
  const wDig = warrantDigest(warrant);
  const receipt = {
    seq: 1,
    prevHash: ZERO_DIGEST_HEX,
    chainId: 'gnoland-testnet',
    realm: 'gno.land/r/arobi/assurance',
    agentId: 'ullumii-worker-1',
    caller: 'g1operator',
    projectionDigest: pDig,
    policyDigest,
    verdict: 'ALLOW',
    reasonCode: 'ALL_RULES_PASSED',
    warrantDigest: wDig,
    height: 100,
  };
  const rLeaf = decisionReceiptLeafHash(receipt);
  const closure = {
    seq: 2,
    prevHash: rLeaf,
    agentId: 'ullumii-worker-1',
    warrantDigest: wDig,
    decisionLeafHash: rLeaf,
    outputDigest: sha256Hex('summary:hello'),
    witnessDigest: sha256Hex('witness:ok'),
    outcome: 'EXECUTED',
    spentUgnot: 100,
    height: 100,
  };
  const cLeaf = effectClosureLeafHash(closure);
  const leaves = [rLeaf, cLeaf];
  const root = merkleTreeHead(leaves);

  const bundle = {
    projection,
    decision: { verdict: 'ALLOW', policyDigest },
    warrant,
    receipt,
    closure,
    receiptLeafIndex: 0,
    closureLeafIndex: 1,
    accumulatorSize: 2,
    accumulatorRoot: root,
    receiptProof: auditPath(0, leaves),
    closureProof: auditPath(1, leaves),
  };

  const ok = verifyEvidenceBundle(bundle);
  assert.equal(ok.verified, true);
  assert.deepEqual(ok.errors, []);

  // Tamper with output digest -> fails RFC 6962 proof immediately!
  const forged = structuredClone(bundle);
  forged.closure.outputDigest = sha256Hex('forged-output');
  const bad = verifyEvidenceBundle(forged);
  assert.equal(bad.verified, false);
  assert.ok(bad.errors.some((e) => e.includes('effect closure RFC 6962')));

  // Anchor record leaf hash computes cleanly.
  const aLeaf = anchorRecordLeafHash({
    chainId: 'gnoland-testnet',
    realm: 'gno.land/r/arobi/assurance',
    anchorId: 1,
    agentId: 'immaculate-worker-1',
    caller: 'g1operator',
    height: 105,
    prevRoot: ZERO_DIGEST_HEX,
    checkpointRoot: root,
    leafCount: 2,
    receiptCount: 1,
    closureCount: 1,
  });
  assert.match(aLeaf, /^[0-9a-f]{64}$/);
});
