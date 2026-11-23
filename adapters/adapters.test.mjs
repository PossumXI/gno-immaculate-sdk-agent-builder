import test from 'node:test';
import assert from 'node:assert/strict';
import { GnoshAssuranceSession, harnessFrameDigest } from './gnosh-adapter.mjs';
import { UllumiiAssuranceBridge } from './ullumii-adapter.mjs';
import { verifyEvidenceBundle } from '../verifier/verify-evidence.mjs';

test('gnosh.ai NDJSON frame stream builds verified RFC 6962 bundles and AnchorCheckpoint tx', () => {
  const session = new GnoshAssuranceSession({
    agentId: 'gnosh-coder-1',
    principal: 'g1principal000000000000000000000000000000',
    caller: 'g1operator0000000000000000000000000000000',
    sessionId: 'gnosh-sess-42',
  });

  const ndjson = [
    JSON.stringify({ type: 'frame_push', frame_id: 'f1' }),
    JSON.stringify({
      type: 'tool_result',
      frame_id: 'f1',
      tool: 'edit_file',
      target: 'src/main.gno',
      input: 'patch-1',
      output: 'ok',
      witness: 'git-diff-sha',
      verdict: 'ALLOW',
      budget_ugnot: 100,
      spent_ugnot: 100,
    }),
    JSON.stringify({
      type: 'tool_result',
      frame_id: 'f2',
      parent_frame_id: 'f1',
      tool: 'shell_exec',
      target: 'rm -rf /',
      input: 'dangerous',
      verdict: 'DENY',
      reason_code: 'CRITICAL_RISK_DENIED',
      risk_tier: 'CRITICAL',
    }),
  ].join('\n');

  const bundles = session.ingestNdjsonStream(ndjson, 500);
  assert.equal(bundles.length, 2);
  assert.equal(verifyEvidenceBundle(bundles[0]).verified, true);
  assert.equal(verifyEvidenceBundle(bundles[1]).verified, true);
  assert.equal(bundles[1].closure.outcome, 'REFUSED');

  const tx = session.buildAnchorCheckpointTx(1000);
  assert.equal(tx.messages[0].value.func, 'AnchorCheckpoint');
  assert.equal(tx.messages[0].value.send, '1000ugnot');
  assert.equal(tx.messages[0].value.args[0], 'gnosh-coder-1');
  assert.equal(tx.messages[0].value.args[3], '4'); // 2 receipts + 2 closures
  assert.match(harnessFrameDigest(bundles[0].harnessFrame), /^[0-9a-f]{64}$/);
});

test('Ullumii bridge records governed MCP actions and exports Whisper cross-harness handoff', () => {
  const bridge = new UllumiiAssuranceBridge({
    agentId: 'ullumii-coord-1',
    workspaceId: 'ws-arobi-demo',
    principal: 'g1principal000000000000000000000000000000',
    caller: 'g1operator0000000000000000000000000000000',
  });

  const b = bridge.recordUllumiiAction({
    handoffId: 'ho-1',
    mcpServer: 'immaculate-mcp',
    toolName: 'verify_policy',
    input: '{"action":"deploy"}',
    output: '{"verdict":"ALLOW"}',
    witness: 'attest-sig-1',
    budgetUgnot: 250,
    spentUgnot: 250,
    height: 700,
  });
  assert.equal(verifyEvidenceBundle(b).verified, true);

  const handoff = bridge.exportWhisperHandoff({
    toHarness: 'gnosh.ai',
    toAgentId: 'gnosh-coder-1',
    taskPayload: { repo: 'gno-immaculate-sdk-agent-builder', task: 'run gno test' },
  });
  assert.equal(handoff.version, 'whisper-agent-bus/1');
  assert.equal(handoff.fromHarness, 'ullumii');
  assert.equal(handoff.toHarness, 'gnosh.ai');
  assert.equal(handoff.evidenceRootHex, b.accumulatorRoot);
  assert.match(handoff.payloadDigestHex, /^[0-9a-f]{64}$/);
});
