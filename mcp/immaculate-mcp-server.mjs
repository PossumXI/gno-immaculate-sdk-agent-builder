#!/usr/bin/env node
/**
 * Immaculate Agent SDK — Zero-Dependency Model Context Protocol (MCP) Stdio Server.
 *
 * Exposes Arobi Assurance governed execution, poison-resistant Familiar MemoryVault
 * (Spherical Quarantine + Overlap-Weighted Hybrid RRF k=60), standalone RFC 6962
 * offline verification, Gno.land AnchorCheckpoint tx generation, and cross-harness
 * Whisper Agent Bus handoffs over standard JSON-RPC 2.0 stdio so Claude, Antigravity,
 * Ullumii, gnosh.ai, and gnomcp clients can call the SDK natively.
 */

import readline from 'node:readline';
import crypto from 'node:crypto';
import { GnoshAssuranceSession } from '../adapters/gnosh-adapter.mjs';
import { UllumiiAssuranceBridge } from '../adapters/ullumii-adapter.mjs';
import { verifyEvidenceBundle, sha256Hex } from '../verifier/verify-evidence.mjs';

const SERVER_INFO = {
  name: 'immaculate-agent-sdk-mcp',
  version: '1.0.0',
};

const SCALE = 1_000_000;
const QUARANTINE_COS = 0.55;
const RRF_K = 60;

// In-memory governed Familiar MemoryVault & Assurance Session for live MCP turns
const state = {
  session: new GnoshAssuranceSession({
    agentId: process.env.IMMACULATE_AGENT_ID || 'immaculate-mcp-familiar',
    principal: process.env.IMMACULATE_PRINCIPAL || 'g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t',
    caller: process.env.IMMACULATE_CALLER || 'g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t',
    sessionId: process.env.IMMACULATE_SESSION_ID || 'mcp-session-1',
    realm: process.env.IMMACULATE_REALM || 'gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/assurance',
  }),
  bridge: new UllumiiAssuranceBridge({
    agentId: process.env.IMMACULATE_AGENT_ID || 'immaculate-mcp-familiar',
    workspaceId: process.env.IMMACULATE_SESSION_ID || 'mcp-session-1',
    principal: process.env.IMMACULATE_PRINCIPAL || 'g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t',
    caller: process.env.IMMACULATE_CALLER || 'g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t',
    realm: process.env.IMMACULATE_REALM || 'gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/assurance',
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
      if (state.activeMemories.length >= 2) {
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
