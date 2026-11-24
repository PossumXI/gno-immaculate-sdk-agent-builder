#!/usr/bin/env node
/**
 * Immaculate SDK Agent Builder — Zero-Dependency Model Context Protocol (MCP) Stdio Server.
 *
 * Exposes Arobi Assurance governed execution, poison-resistant Familiar MemoryVault
 * (Spherical Quarantine + Overlap-Weighted Hybrid RRF k=60), standalone RFC 6962
 * offline verification, Gno.land AnchorCheckpoint tx generation, and cross-harness
 * Whisper Agent Bus handoffs over standard JSON-RPC 2.0 stdio so Claude, Antigravity,
 * Ullumii, gnosh.ai, and gnomcp clients can call the SDK natively.
 */

import readline from 'node:readline';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {
  GnoshAssuranceSession,
  estimateGnoshContextBudget,
  inspectSkillPreflight,
  buildGnoshPeersPlanGno,
} from '../adapters/gnosh-adapter.mjs';
import { UllumiiAssuranceBridge } from '../adapters/ullumii-adapter.mjs';
import {
  verifyEvidenceBundle,
  verifyCrossChainCheckpoint,
  consistencyProof,
  verifyConsistencyProof,
  merkleTreeHead,
  sha256Hex,
} from '../verifier/verify-evidence.mjs';
import { parseEffectJson, verifyEffect } from '../verifier/verify-effect.mjs';

const SERVER_INFO = {
  name: 'immaculate-sdk-agent-mcp',
  version: '1.1.0',
};

if (process.argv.includes('--print-gnosh-mcp')) {
  const scriptPath = fileURLToPath(import.meta.url);
  const cfg = {
    command: 'node',
    args: [scriptPath],
    env: {
      IMMACULATE_AGENT_ID: process.env.IMMACULATE_AGENT_ID || 'gnosh-familiar',
    },
  };
  console.log(`gnosh mcp add-json immaculate-sdk '${JSON.stringify(cfg)}'`);
  process.exit(0);
}

const SCALE = 1_000_000;
const QUARANTINE_COS = 0.55;
const RRF_K = 60;

// In-memory governed Familiar MemoryVault & Assurance Session for live MCP turns
const state = {
  session: new GnoshAssuranceSession({
    agentId: process.env.IMMACULATE_AGENT_ID || 'immaculate-mcp-familiar',
    principal: process.env.IMMACULATE_PRINCIPAL || 'g1principal000000000000000000000000000000',
    caller: process.env.IMMACULATE_CALLER || 'g1operator0000000000000000000000000000000',
    sessionId: process.env.IMMACULATE_SESSION_ID || 'mcp-session-1',
    realm: process.env.IMMACULATE_REALM || 'gno.land/r/arobi/assurance',
  }),
  bridge: new UllumiiAssuranceBridge({
    agentId: process.env.IMMACULATE_AGENT_ID || 'immaculate-mcp-familiar',
    workspaceId: process.env.IMMACULATE_SESSION_ID || 'mcp-session-1',
    principal: process.env.IMMACULATE_PRINCIPAL || 'g1principal000000000000000000000000000000',
    caller: process.env.IMMACULATE_CALLER || 'g1operator0000000000000000000000000000000',
    realm: process.env.IMMACULATE_REALM || 'gno.land/r/arobi/assurance',
  }),
  allowedActions: new Set(['summarize', 'rebalance', 'query_balance', 'delegate_task', 'recall_brief']),
  maxBudgetUgnot: Number(process.env.IMMACULATE_MAX_BUDGET_UGNOT || 5000),
  activeMemories: [],
  quarantinedMemories: [],
  nextMemoryId: 1,
  frameSeq: 0,
};

function normVec(v) {
  const n = Math.sqrt(v.reduce((s, x) => s + x * x, 0));
  if (!Number.isFinite(n) || n <= 1e-12) throw new Error('zero or invalid embedding vector');
  return v.map((x) => x / n);
}
function dot(a, b) {
  let s = 0;
  for (let i = 0; i < a.length; i++) s += a[i] * b[i];
  return Math.max(-1, Math.min(1, s));
}
function tokenize(text) {
  return [...new Set((String(text || '').toLowerCase().match(/[a-z0-9_-]{2,}/g) || []))];
}
function lexicalCoverage(qTerms, docTerms) {
  if (!qTerms.length || !docTerms.length) return 0;
  let hits = 0;
  for (const t of qTerms) if (docTerms.includes(t)) hits++;
  return hits / qTerms.length;
}

const TOOLS = [
  {
    name: 'governed_execute',
    description: 'Run an agent action through fail-closed policy enforcement (allowlist + budget cap) and emit a self-verifying RFC 6962 EvidenceBundle.',
    inputSchema: {
      type: 'object',
      required: ['action', 'target'],
      properties: {
        action: { type: 'string' },
        target: { type: 'string' },
        input: { type: 'string' },
        budgetUgnot: { type: 'number' },
        height: { type: 'number' },
      },
    },
  },
  {
    name: 'familiar_remember',
    description: 'Ingest an episodic/semantic memory into the Familiar MemoryVault through the spherical poisoning quarantine firewall.',
    inputSchema: {
      type: 'object',
      required: ['text', 'embedding'],
      properties: {
        kind: { type: 'string' },
        text: { type: 'string' },
        embedding: { type: 'array', items: { type: 'number' } },
      },
    },
  },
  {
    name: 'familiar_recall',
    description: 'Retrieve Top-K memories using Overlap-Weighted Hybrid Reciprocal Rank Fusion (RRF k=60) and return a cryptographic MemoryRecallProof digest.',
    inputSchema: {
      type: 'object',
      required: ['queryText', 'queryEmbedding'],
      properties: {
        queryText: { type: 'string' },
        queryEmbedding: { type: 'array', items: { type: 'number' } },
        topK: { type: 'number' },
      },
    },
  },
  {
    name: 'verify_evidence_bundle',
    description: 'Verify any RFC 6962 EvidenceBundle offline (projection, warrant, receipt, closure, and Merkle inclusion proofs).',
    inputSchema: {
      type: 'object',
      required: ['bundle'],
      properties: {
        bundle: { type: 'object' },
      },
    },
  },
  {
    name: 'build_anchor_tx',
    description: 'Build a Gno.land /vm.m_call AnchorCheckpoint transaction for the current session accumulator root.',
    inputSchema: {
      type: 'object',
      properties: {
        anchorFeeUgnot: { type: 'number' },
      },
    },
  },
  {
    name: 'export_whisper_handoff',
    description: 'Build a cross-harness handoff packet bound to the current RFC 6962 Merkle root for encrypted delivery over Arobi Whisper Agent Bus.',
    inputSchema: {
      type: 'object',
      required: ['toHarness', 'toAgentId', 'taskPayload'],
      properties: {
        toHarness: { type: 'string' },
        toAgentId: { type: 'string' },
        taskPayload: { type: 'object' },
        correlationId: { type: 'string' },
      },
    },
  },
  {
    name: 'estimate_context_budget',
    description: 'Estimate pre-send draft token usage (prose, JSON, @file attachments, images) and warn before crossing gnosh/Ullumii compaction or context window thresholds.',
    inputSchema: {
      type: 'object',
      properties: {
        usedTokens: { type: 'number' },
        windowTokens: { type: 'number' },
        compactPointTokens: { type: 'number' },
        draftText: { type: 'string' },
        attachments: { type: 'array', items: { type: 'object' } },
      },
    },
  },
  {
    name: 'inspect_skill_preflight',
    description: 'Run fail-closed monotone static security preflight on an untrusted skill or MCP prompt before loading it into gnosh.ai or Ullumii.',
    inputSchema: {
      type: 'object',
      required: ['body'],
      properties: {
        name: { type: 'string' },
        source: { type: 'string' },
        body: { type: 'string' },
      },
    },
  },
  {
    name: 'gnosh_peers_plan',
    description: 'Emit valid gnomem/v2 Gno plan code honoring gnosh peers.md (.Parallel() on parent group only, ordered final verification step) bound to the session RFC 6962 Merkle root.',
    inputSchema: {
      type: 'object',
      required: ['parallelSteps'],
      properties: {
        rootName: { type: 'string' },
        rootTitle: { type: 'string' },
        parallelGroupName: { type: 'string' },
        parallelGroupTitle: { type: 'string' },
        parallelSteps: { type: 'array', items: { type: 'object' } },
        finalCheckName: { type: 'string' },
        finalCheckTitle: { type: 'string' },
      },
    },
  },
  {
    name: 'verify_consistency_proof',
    description: 'Generate or verify an RFC 6962 / RFC 9162 section 2.1.4.2 logarithmic Merkle consistency proof between two accumulator tree sizes.',
    inputSchema: {
      type: 'object',
      required: ['firstSize', 'secondSize'],
      properties: {
        firstSize: { type: 'number' },
        secondSize: { type: 'number' },
        firstRootHex: { type: 'string' },
        secondRootHex: { type: 'string' },
        proofHexList: { type: 'array', items: { type: 'string' } },
      },
    },
  },
  {
    name: 'verify_cross_chain_checkpoint',
    description: 'Verify a canonical cross-chain checkpoint digest (arobi-checkpoint-v1) and strictly-ordered execution receipt batch RFC 6962 tree (arobi-exec-receipt-v1, Experiment E14).',
    inputSchema: {
      type: 'object',
      properties: {
        checkpoint: { type: 'object' },
        receipts: { type: 'array', items: { type: 'object' } },
        expectedCheckpointDigest: { type: 'string' },
        expectedReceiptRoot: { type: 'string' },
        verifyIndex: { type: 'number' },
      },
    },
  },
  {
    name: 'verify_effect_life',
    description: 'Verify one effect\'s whole life offline, from gno.land/r/arobi/effects EffectJSON(id) (the JSON, or gnokey qeval output): the spec digest, every RFC 6962 leaf, the hash chain, every lifecycle transition and every computed close.',
    inputSchema: {
      type: 'object',
      required: ['effect'],
      properties: {
        effect: { description: 'the EffectJSON document, or its text as gnokey query vm/qeval prints it' },
      },
    },
  },
];

function handleToolCall(name, args = {}) {
  switch (name) {
    case 'governed_execute': {
      state.frameSeq += 1;
      const action = String(args.action || '');
      const target = String(args.target || '');
      const input = String(args.input || '');
      const budgetUgnot = Number(args.budgetUgnot || 0);
      const height = Number(args.height || state.frameSeq);
      const allowed = state.allowedActions.has(action) && budgetUgnot >= 0 && budgetUgnot <= state.maxBudgetUgnot;
      const reasonCode = !state.allowedActions.has(action)
        ? 'ACTION_NOT_ALLOWLISTED'
        : budgetUgnot > state.maxBudgetUgnot
          ? 'BUDGET_CAP_EXCEEDED'
          : 'ALL_RULES_PASSED';
      const bundle = state.session.recordFrameEvent({
        frameId: `mcp-frame-${state.frameSeq}`,
        toolName: action,
        target,
        input,
        output: allowed ? `executed:${action}:${target}` : '',
        witness: allowed ? `mcp-ok:${state.frameSeq}` : reasonCode,
        verdict: allowed ? 'ALLOW' : 'DENY',
        reasonCode,
        outcome: allowed ? 'EXECUTED' : 'REFUSED',
        budgetUgnot,
        spentUgnot: allowed ? budgetUgnot : 0,
        height,
      });
      return {
        allowed,
        reasonCode,
        accumulatorRoot: bundle.accumulatorRoot,
        accumulatorSize: bundle.accumulatorSize,
        verified: verifyEvidenceBundle(bundle).verified,
        bundle,
      };
    }

    case 'familiar_remember': {
      const vec = normVec(args.embedding || []);
      const text = String(args.text || '');
      const id = state.nextMemoryId++;
      const record = {
        id,
        kind: String(args.kind || 'episodic'),
        text,
        terms: tokenize(text),
        vec,
        contentDigest: sha256Hex(text),
      };
      if (state.activeMemories.length === 1) {
        // Variance-calibrated cold-start guard (tau^2) closes the k=1->k=2 base-case gap (Experiment E6b).
        const cos = dot(vec, state.activeMemories[0].vec);
        const pairThresh = QUARANTINE_COS * QUARANTINE_COS;
        if (cos < pairThresh) {
          state.quarantinedMemories.push({ ...record, cosToCentroid: cos });
          return {
            admitted: false,
            quarantined: true,
            reasonCode: 'MEMORY_COLD_START_PAIRWISE_QUARANTINE',
            recordId: id,
            cosToCentroid: Number(cos.toFixed(6)),
            activeCount: state.activeMemories.length,
            quarantinedCount: state.quarantinedMemories.length,
          };
        }
      } else if (state.activeMemories.length >= 2) {
        const dim = vec.length;
        const sum = new Array(dim).fill(0);
        for (const m of state.activeMemories) for (let j = 0; j < dim; j++) sum[j] += m.vec[j];
        const centroid = normVec(sum);
        const cos = dot(vec, centroid);
        if (cos < QUARANTINE_COS) {
          state.quarantinedMemories.push({ ...record, cosToCentroid: cos });
          return {
            admitted: false,
            quarantined: true,
            reasonCode: 'MEMORY_SPHERICAL_QUARANTINE',
            recordId: id,
            cosToCentroid: Number(cos.toFixed(6)),
            activeCount: state.activeMemories.length,
            quarantinedCount: state.quarantinedMemories.length,
          };
        }
      }
      state.activeMemories.push(record);
      return {
        admitted: true,
        quarantined: false,
        reasonCode: 'MEMORY_ADMITTED',
        recordId: id,
        activeCount: state.activeMemories.length,
        quarantinedCount: state.quarantinedMemories.length,
      };
    }

    case 'familiar_recall': {
      const qVec = normVec(args.queryEmbedding || []);
      const qTerms = tokenize(args.queryText || '');
      const topK = Math.max(1, Number(args.topK || 3));
      const items = state.activeMemories.map((m) => ({
        ...m,
        dense: dot(qVec, m.vec),
        lexCov: lexicalCoverage(qTerms, m.terms),
      }));
      const byDense = [...items].sort((a, b) => (b.dense !== a.dense ? b.dense - a.dense : a.id - b.id));
      const byLex = [...items].sort((a, b) => (b.lexCov !== a.lexCov ? b.lexCov - a.lexCov : a.id - b.id));
      const dRank = new Map(byDense.map((m, i) => [m.id, i + 1]));
      const lRank = new Map(byLex.map((m, i) => [m.id, i + 1]));
      const scored = items
        .map((m) => {
          const rrfD = Math.trunc(SCALE / (RRF_K + dRank.get(m.id)));
          const rrfL = m.lexCov > 0 ? Math.trunc((SCALE / (RRF_K + lRank.get(m.id))) * m.lexCov) : 0;
          return { id: m.id, kind: m.kind, text: m.text, contentDigest: m.contentDigest, rrfScore: rrfD + rrfL };
        })
        .sort((a, b) => (b.rrfScore !== a.rrfScore ? b.rrfScore - a.rrfScore : a.id - b.id))
        .slice(0, topK);
      const recallDigest = crypto
        .createHash('sha256')
        .update(JSON.stringify({ q: args.queryText, ids: scored.map((s) => s.id), qCount: state.quarantinedMemories.length }))
        .digest('hex');
      return {
        results: scored,
        quarantinedCount: state.quarantinedMemories.length,
        recallProofDigest: recallDigest,
      };
    }

    case 'verify_evidence_bundle': {
      return verifyEvidenceBundle(args.bundle);
    }

    case 'build_anchor_tx': {
      const fee = args.anchorFeeUgnot === undefined ? 1000 : Number(args.anchorFeeUgnot);
      return state.session.buildAnchorCheckpointTx(fee);
    }

    case 'export_whisper_handoff': {
      const latest = state.session.bundles[state.session.bundles.length - 1] || null;
      return {
        version: 'whisper-agent-bus/1',
        fromHarness: 'mcp',
        fromAgentId: state.session.agentId,
        toHarness: String(args.toHarness),
        toAgentId: String(args.toAgentId),
        kind: 'handoff',
        correlationId: String(args.correlationId || `mcp-${state.frameSeq}`),
        evidenceRootHex: latest ? latest.accumulatorRoot : null,
        parentWarrantDigest: latest?.receipt?.warrantDigest || null,
        payloadDigestHex: sha256Hex(JSON.stringify(args.taskPayload || {})),
        payload: args.taskPayload || {},
      };
    }

    case 'estimate_context_budget': {
      return estimateGnoshContextBudget(args);
    }

    case 'inspect_skill_preflight': {
      return inspectSkillPreflight(args);
    }

    case 'gnosh_peers_plan': {
      const latest = state.session.bundles[state.session.bundles.length - 1] || null;
      return buildGnoshPeersPlanGno({
        ...args,
        warrantRootHex: latest ? latest.accumulatorRoot : '',
      });
    }

    case 'verify_consistency_proof': {
      const first = Number(args.firstSize);
      const second = Number(args.secondSize);
      if (Array.isArray(args.proofHexList) && args.firstRootHex && args.secondRootHex) {
        const verified = verifyConsistencyProof(first, second, args.firstRootHex, args.secondRootHex, args.proofHexList);
        return { firstSize: first, secondSize: second, verified, proofLength: args.proofHexList.length };
      }
      const leaves = state.session.leaves;
      const firstRootHex = merkleTreeHead(leaves.slice(0, first));
      const secondRootHex = merkleTreeHead(leaves.slice(0, second));
      const proof = consistencyProof(first, second, leaves);
      const verified = verifyConsistencyProof(first, second, firstRootHex, secondRootHex, proof);
      return {
        firstSize: first,
        secondSize: second,
        firstRootHex,
        secondRootHex,
        proofHexList: proof,
        proofLength: proof.length,
        verified,
      };
    }

    case 'verify_cross_chain_checkpoint': {
      return verifyCrossChainCheckpoint({
        checkpoint: args.checkpoint,
        receipts: args.receipts,
        expectedCheckpointDigest: args.expectedCheckpointDigest,
        expectedReceiptRoot: args.expectedReceiptRoot,
        verifyIndex: args.verifyIndex,
      });
    }

    case 'verify_effect_life': {
      try {
        const doc = typeof args.effect === 'string' ? parseEffectJson(args.effect) : args.effect;
        return { verified: true, ...verifyEffect(doc) };
      } catch (e) {
        return { verified: false, reason: e.message };
      }
    }

    default:
      throw new Error(`Unknown MCP tool: ${name}`);
  }
}

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + '\n');
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on('line', (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  let req;
  try {
    req = JSON.parse(trimmed);
  } catch (err) {
    send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: `Parse error: ${err.message}` } });
    return;
  }

  const { id, method, params } = req;
  if (method === 'notifications/initialized') return;

  try {
    if (method === 'initialize') {
      send({
        jsonrpc: '2.0',
        id,
        result: {
          protocolVersion: '2024-11-05',
          serverInfo: SERVER_INFO,
          capabilities: { tools: {} },
        },
      });
    } else if (method === 'tools/list') {
      send({ jsonrpc: '2.0', id, result: { tools: TOOLS } });
    } else if (method === 'tools/call') {
      const data = handleToolCall(params?.name, params?.arguments || {});
      send({
        jsonrpc: '2.0',
        id,
        result: {
          content: [{ type: 'text', text: JSON.stringify(data) }],
          structuredContent: data,
        },
      });
    } else {
      send({ jsonrpc: '2.0', id, error: { code: -32601, message: `Method not found: ${method}` } });
    }
  } catch (err) {
    send({ jsonrpc: '2.0', id, error: { code: -32000, message: String(err.message || err) } });
  }
});
