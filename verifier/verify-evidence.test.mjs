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
  checkpointDigest,
  execReceiptLeafHash,
  buildOrderedReceiptTree,
  verifyCrossChainCheckpoint,
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

test('E14 cross-chain CanonicalCheckpoint and strictly ordered ExecutionReceipt tree match Gno v1.8.0 golden hashes', () => {
  const checkpoint = {
    chainId: 'arobi-testnet-1',
    height: 4200,
    headerHash: sha256Hex('hdr-4200'),
    appHash: sha256Hex('app-4200'),
    validatorsHash: sha256Hex('val-4200'),
    nextValidatorsHash: sha256Hex('nval-4200'),
  };
  const receipts = [
    {
      chainId: 'arobi-testnet-1',
      height: 4200,
      txIndex: 0,
      txHash: sha256Hex('tx-0'),
      caller: 'g1alice',
      contract: 'wasm/escrow-v1',
      gasUsed: 125000,
      exitCode: 0,
      resultHash: sha256Hex('res-0'),
    },
    {
      chainId: 'arobi-testnet-1',
      height: 4200,
      txIndex: 1,
      txHash: sha256Hex('tx-1'),
      caller: 'g1bob',
      contract: 'wasm/escrow-v1',
      gasUsed: 98000,
      exitCode: 0,
      resultHash: sha256Hex('res-1'),
    },
    {
      chainId: 'arobi-testnet-1',
      height: 4201,
      txIndex: 0,
      txHash: sha256Hex('tx-2'),
      caller: 'g1carol',
      contract: 'wasm/govern-v1',
      gasUsed: 210000,
      exitCode: 0,
      resultHash: sha256Hex('res-2'),
    },
  ];

  // Exact golden digests verified by Gno v1.8.0 TestE14CrossChainCheckpointAndOrderedReceiptTree
  const cpDigest = checkpointDigest(checkpoint);
  const tree = buildOrderedReceiptTree(receipts);
  const leaf1 = execReceiptLeafHash(receipts[1]);
  assert.equal(cpDigest, 'e75622556eac5ddfd47a99210a1f8d701ac0511f4eb0ba278541e954fa7b40d9');
  assert.equal(tree.root, '4f8658ea53439ef542d01aa959fa6bd1a333480d6f81fac00aa166e8c45cd4cb');
  assert.equal(leaf1, '68943efe05303e4017a85fb37a392fc3ebe52f89933e99682064594f8f70d22b');

  const ok = verifyCrossChainCheckpoint({
    checkpoint,
    expectedCheckpointDigest: cpDigest,
    receipts,
    expectedReceiptsRoot: tree.root,
    targetReceiptIndex: 1,
    targetProof: auditPath(1, tree.leaves),
  });
  assert.equal(ok.verified, true);

  // Swapped order must fail closed.
  const badOrder = verifyCrossChainCheckpoint({
    checkpoint,
    expectedCheckpointDigest: cpDigest,
    receipts: [receipts[1], receipts[0], receipts[2]],
    expectedReceiptsRoot: tree.root,
  });
  assert.equal(badOrder.verified, false);
});
