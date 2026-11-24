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
  ZERO_DIGEST_HEX,
  verifyEvidenceBundle,
  verifyCrossChainCheckpoint,
  effectEventLeafHash,
  verifyEffectLifecycleChain,
  consistencyProof,
  verifyConsistencyProof,
  merkleTreeHead,
  sha256Hex,
} from '../verifier/verify-evidence.mjs';

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
  effects: new Map(),
  openEffectsByKey: new Map(),
  effectsByIdempotency: new Map(),
  effectEvents: [],
  effectLeaves: [],
  effectLastHash: ZERO_DIGEST_HEX,
  effectCount: 0,
  sessionPaused: false,
};

const VALID_REVERSAL_CLASSES = new Set(['REVERSIBLE', 'COMPENSABLE', 'IRREVERSIBLE']);
const DEFAULT_MAX_RECOVERY_ATTEMPTS = 3;
const DEFAULT_MAX_READBACK_AGE_MS = 60_000;

function deriveLeaseToken(effectId, attempt, idempotencyKey) {
  return sha256Hex(`arobi-lease-v1|${effectId}|${attempt}|${idempotencyKey}`);
}

function resolveDigest(digestHex, rawPayload) {
  if (typeof digestHex === 'string' && /^[0-9a-f]{64}$/.test(digestHex.trim())) {
    return digestHex.trim();
  }
  if (rawPayload !== undefined && rawPayload !== null && String(rawPayload).length > 0) {
    return sha256Hex(typeof rawPayload === 'string' ? rawPayload : JSON.stringify(rawPayload));
  }
  return ZERO_DIGEST_HEX;
}

function sealLifecycleEvent(ev) {
  const full = {
    seq: state.effectEvents.length + 1,
    prevHash: state.effectLastHash,
    effectId: ev.effectId,
    effectKey: ev.effectKey,
    idempotencyKey: ev.idempotencyKey,
    kind: ev.kind,
    state: ev.state,
    attempt: Number(ev.attempt ?? 1),
    stepIndex: Number(ev.stepIndex ?? 0),
    totalSteps: Number(ev.totalSteps ?? 0),
    actor: String(ev.actor || state.session.caller),
    owner: String(ev.owner),
    reversalClass: String(ev.reversalClass),
    stateChanged: Boolean(ev.stateChanged),
    readbackDigest: ev.readbackDigest || ZERO_DIGEST_HEX,
    fenceDigest: ev.fenceDigest || ZERO_DIGEST_HEX,
    observedHeight: Number(ev.observedHeight ?? 0),
    supersedesId: String(ev.supersedesId || ''),
    humanApproval: String(ev.humanApproval || ''),
    deadlineHeight: Number(ev.deadlineHeight ?? 0),
    height: Number(ev.height ?? 0),
  };
  const leaf = effectEventLeafHash(full);
  full.leafHash = leaf;
  state.effectEvents.push(full);
  state.effectLeaves.push(leaf);
  state.effectLastHash = leaf;
  return full;
}

function effectLifecycleRootHex() {
  return merkleTreeHead(state.effectLeaves);
}

function sweepOverdueEffects(nowMs, actor = 'clock-sweep') {
  const now = Number.isFinite(Number(nowMs)) ? Math.trunc(Number(nowMs)) : Date.now();
  const transitioned = [];
  for (const effectId of state.openEffectsByKey.values()) {
    const rec = state.effects.get(effectId);
    if (rec && rec.state === 'STARTED' && now >= rec.deadlineMs) {
      rec.state = 'IN_DOUBT';
      const ev = sealLifecycleEvent({
        effectId: rec.id,
        effectKey: rec.effectKey,
        idempotencyKey: rec.idempotencyKey,
        kind: 'IN_DOUBT',
        state: 'IN_DOUBT',
        attempt: rec.attempt,
        stepIndex: rec.steps.length,
        totalSteps: rec.totalSteps,
        actor,
        owner: rec.cleanupOwner,
        reversalClass: rec.reversalClass,
        stateChanged: false,
        readbackDigest: ZERO_DIGEST_HEX,
        fenceDigest: ZERO_DIGEST_HEX,
        observedHeight: 0,
        deadlineHeight: rec.deadlineMs,
        height: now,
      });
      rec.lastEventHash = ev.leafHash;
      transitioned.push(rec.id);
    }
  }
  return transitioned;
}

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
    name: 'arobi_begin_effect',
    description: 'Seal STARTED for a governed multi-step effect with mandatory deadline, cleanup owner (defaults to grant issuer), postcondition, reversal class, and attempt/lease token. Denies IRREVERSIBLE without human approval (leaving zero STARTED record), deduplicates retries by idempotencyKey, and fences open effectKeys.',
    inputSchema: {
      type: 'object',
      required: ['effectKey', 'idempotencyKey', 'totalSteps', 'postcondition', 'reversalClass'],
      properties: {
        effectKey: { type: 'string' },
        idempotencyKey: { type: 'string' },
        totalSteps: { type: 'number' },
        postcondition: { type: 'string' },
        reversalClass: { type: 'string', enum: ['REVERSIBLE', 'COMPENSABLE', 'IRREVERSIBLE'] },
        undoSpec: { type: 'string' },
        deadlineMs: { type: 'number' },
        deadlineSeconds: { type: 'number' },
        maxRecoveryAttempts: { type: 'number' },
        maxReadbackAgeMs: { type: 'number' },
        cleanupOwner: { type: 'string' },
        grantIssuer: { type: 'string' },
        humanApprovalId: { type: 'string' },
        actor: { type: 'string' },
        nowMs: { type: 'number' },
      },
    },
  },
  {
    name: 'arobi_record_step',
    description: 'Seal one step receipt inside an active STARTED effect, fenced by attempt number and leaseToken.',
    inputSchema: {
      type: 'object',
      required: ['effectId', 'stepIndex', 'stepName'],
      properties: {
        effectId: { type: 'string' },
        attempt: { type: 'number' },
        leaseToken: { type: 'string' },
        stepIndex: { type: 'number' },
        stepName: { type: 'string' },
        output: { type: 'string' },
        outputDigest: { type: 'string' },
        stateChanged: { type: 'boolean' },
        actor: { type: 'string' },
        nowMs: { type: 'number' },
      },
    },
  },
  {
    name: 'arobi_close_effect',
    description: 'Close a STARTED or IN_DOUBT effect by verifying attempt/lease binding, read-back observation freshness, and sink/grant fence evidence. Unfenced no-effect stays IN_DOUBT (never ABORTED); only once fenceDigest/fenceProof proves the grant cannot land later does no-effect close ABORTED.',
    inputSchema: {
      type: 'object',
      required: ['effectId'],
      properties: {
        effectId: { type: 'string' },
        attempt: { type: 'number' },
        leaseToken: { type: 'string' },
        requestedOutcome: { type: 'string', enum: ['COMMITTED', 'ABORTED', 'PARTIAL'] },
        readback: { type: 'string' },
        readbackDigest: { type: 'string' },
        observedMs: { type: 'number' },
        fenceProof: { type: 'string' },
        fenceDigest: { type: 'string' },
        stateChanged: { type: 'boolean' },
        exitCode: { type: 'number' },
        actor: { type: 'string' },
        nowMs: { type: 'number' },
      },
    },
  },
  {
    name: 'arobi_list_open_effects',
    description: 'Sweep overdue STARTED effects into IN_DOUBT by clock and list every open IN_DOUBT or PARTIAL obligation with its cleanup owner, attempt, age, recovery budget, and recorded step receipts.',
    inputSchema: {
      type: 'object',
      properties: {
        nowMs: { type: 'number' },
      },
    },
  },
  {
    name: 'arobi_compensate',
    description: 'Run a bounded linked reversal effect for an IN_DOUBT or PARTIAL effect (refused while session/grant is paused, capped at maxRecoveryAttempts, requiring fresh read-back confirming the restored state) or seal human AcceptPartial approval.',
    inputSchema: {
      type: 'object',
      required: ['originalEffectId'],
      properties: {
        originalEffectId: { type: 'string' },
        compIdempotencyKey: { type: 'string' },
        readback: { type: 'string' },
        readbackDigest: { type: 'string' },
        observedMs: { type: 'number' },
        compDeadlineMs: { type: 'number' },
        restoredOriginalState: { type: 'boolean' },
        acceptPartial: { type: 'boolean' },
        humanApprover: { type: 'string' },
        reason: { type: 'string' },
        actor: { type: 'string' },
        nowMs: { type: 'number' },
      },
    },
  },
  {
    name: 'arobi_set_pause',
    description: 'Pause or resume the local governed effect session; while paused, new starts and automated compensations are refused.',
    inputSchema: {
      type: 'object',
      required: ['paused'],
      properties: {
        paused: { type: 'boolean' },
      },
    },
  },
];

function handleToolCall(name, args = {}) {
  // Run overdue partial-effect sweep on every MCP call so quiet executors become IN_DOUBT by clock.
  sweepOverdueEffects(args?.nowMs, 'mcp-clock-sweep');

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

    case 'arobi_set_pause': {
      state.sessionPaused = Boolean(args.paused);
      return { paused: state.sessionPaused };
    }

    case 'arobi_begin_effect': {
      if (state.sessionPaused) {
        return {
          allowed: false,
          verdict: 'DENY',
          reasonCode: 'SESSION_PAUSED',
          message: 'DENIED: session is paused',
        };
      }
      const now = Number.isFinite(Number(args.nowMs)) ? Math.trunc(Number(args.nowMs)) : Date.now();
      const effectKey = String(args.effectKey || '').trim();
      const idempotencyKey = String(args.idempotencyKey || '').trim();
      const totalSteps = Number(args.totalSteps ?? args.steps ?? 0);
      const postcondition = String(args.postcondition || '').trim();
      const reversalClass = String(args.reversalClass || '').trim();
      const undoSpec = String(args.undoSpec || '').trim();
      const humanApprovalId = String(args.humanApprovalId || '').trim();
      const cleanupOwner = String(args.cleanupOwner || args.grantIssuer || state.session.caller || '').trim();
      const actor = String(args.actor || state.session.caller);
      const maxRecoveryAttempts = args.maxRecoveryAttempts !== undefined
        ? Math.max(1, Math.min(10, Math.trunc(Number(args.maxRecoveryAttempts))))
        : DEFAULT_MAX_RECOVERY_ATTEMPTS;
      const maxReadbackAgeMs = args.maxReadbackAgeMs !== undefined
        ? Math.max(1, Math.trunc(Number(args.maxReadbackAgeMs)))
        : DEFAULT_MAX_READBACK_AGE_MS;
      const deadlineMs = args.deadlineMs !== undefined
        ? Math.trunc(Number(args.deadlineMs))
        : args.deadlineSeconds !== undefined
          ? now + Math.trunc(Number(args.deadlineSeconds) * 1000)
          : 0;

      if (!effectKey || !idempotencyKey || !postcondition || !cleanupOwner) {
        return {
          allowed: false,
          verdict: 'DENY',
          reasonCode: 'INCOMPLETE_EFFECT_SPEC',
          message: 'effectKey, idempotencyKey, postcondition, and cleanupOwner are required',
        };
      }
      if (!Number.isInteger(totalSteps) || totalSteps < 1 || totalSteps > 64) {
        return {
          allowed: false,
          verdict: 'DENY',
          reasonCode: 'INVALID_TOTAL_STEPS',
          message: 'totalSteps must be an integer between 1 and 64',
        };
      }
      if (!Number.isFinite(deadlineMs) || deadlineMs <= now) {
        return {
          allowed: false,
          verdict: 'DENY',
          reasonCode: 'MISSING_OR_PAST_DEADLINE',
          message: 'deadlineMs must be strictly greater than start timestamp',
        };
      }
      if (!VALID_REVERSAL_CLASSES.has(reversalClass)) {
        return {
          allowed: false,
          verdict: 'DENY',
          reasonCode: 'INVALID_REVERSAL_CLASS',
          message: 'reversalClass must be REVERSIBLE, COMPENSABLE, or IRREVERSIBLE',
        };
      }
      if (reversalClass === 'IRREVERSIBLE' && !humanApprovalId) {
        return {
          allowed: false,
          verdict: 'DENY',
          reasonCode: 'IRREVERSIBLE_REQUIRES_HUMAN_APPROVAL',
          message: 'DENIED: IRREVERSIBLE effect requires prior human approval',
        };
      }
      if ((reversalClass === 'REVERSIBLE' || reversalClass === 'COMPENSABLE') && !undoSpec) {
        return {
          allowed: false,
          verdict: 'DENY',
          reasonCode: 'MISSING_UNDO_SPEC',
          message: `${reversalClass} effect requires undoSpec`,
        };
      }

      if (state.effectsByIdempotency.has(idempotencyKey)) {
        const existingId = state.effectsByIdempotency.get(idempotencyKey);
        const existing = state.effects.get(existingId);
        return {
          allowed: true,
          verdict: 'ALLOW',
          deduplicated: true,
          applied: false,
          effectId: existing.id,
          attempt: existing.attempt,
          leaseToken: existing.leaseToken,
          state: existing.state,
          cleanupOwner: existing.cleanupOwner,
          stepsRecorded: existing.steps.length,
          totalSteps: existing.totalSteps,
          rootHex: effectLifecycleRootHex(),
        };
      }

      if (state.openEffectsByKey.has(effectKey)) {
        const openId = state.openEffectsByKey.get(effectKey);
        const open = state.effects.get(openId);
        return {
          allowed: false,
          verdict: 'DENY',
          reasonCode: 'EFFECT_KEY_FENCED',
          openEffectId: open.id,
          openState: open.state,
          cleanupOwner: open.cleanupOwner,
          message: `DENIED: effect key ${effectKey} is fenced by open effect ${open.id} (${open.state})`,
        };
      }

      state.effectCount += 1;
      const id = `eff-${state.effectCount}`;
      const attempt = 1;
      const leaseToken = deriveLeaseToken(id, attempt, idempotencyKey);
      const rec = {
        id,
        effectKey,
        idempotencyKey,
        state: 'STARTED',
        attempt,
        leaseToken,
        totalSteps,
        postcondition,
        reversalClass,
        undoSpec,
        cleanupOwner,
        humanApprovalId,
        startMs: now,
        deadlineMs,
        closedMs: null,
        maxReadbackAgeMs,
        maxRecoveryAttempts,
        recoveryAttempts: 0,
        steps: [],
        readbackDigest: ZERO_DIGEST_HEX,
        fenceDigest: ZERO_DIGEST_HEX,
        compensatedById: null,
        supersedesId: '',
        lastEventHash: ZERO_DIGEST_HEX,
      };
      const ev = sealLifecycleEvent({
        effectId: rec.id,
        effectKey: rec.effectKey,
        idempotencyKey: rec.idempotencyKey,
        kind: 'START',
        state: 'STARTED',
        attempt: rec.attempt,
        stepIndex: 0,
        totalSteps: rec.totalSteps,
        actor,
        owner: rec.cleanupOwner,
        reversalClass: rec.reversalClass,
        stateChanged: false,
        readbackDigest: ZERO_DIGEST_HEX,
        fenceDigest: ZERO_DIGEST_HEX,
        observedHeight: 0,
        humanApproval: rec.humanApprovalId,
        deadlineHeight: rec.deadlineMs,
        height: now,
      });
      rec.lastEventHash = ev.leafHash;
      state.effects.set(rec.id, rec);
      state.openEffectsByKey.set(rec.effectKey, rec.id);
      state.effectsByIdempotency.set(rec.idempotencyKey, rec.id);

      return {
        allowed: true,
        verdict: 'ALLOW',
        deduplicated: false,
        applied: true,
        effectId: rec.id,
        attempt: rec.attempt,
        leaseToken: rec.leaseToken,
        state: rec.state,
        cleanupOwner: rec.cleanupOwner,
        deadlineMs: rec.deadlineMs,
        rootHex: effectLifecycleRootHex(),
        event: ev,
      };
    }

    case 'arobi_record_step': {
      const now = Number.isFinite(Number(args.nowMs)) ? Math.trunc(Number(args.nowMs)) : Date.now();
      const effectId = String(args.effectId || '').trim();
      const rec = state.effects.get(effectId);
      if (!rec) throw new Error(`unknown effectId: ${effectId}`);
      if (rec.state !== 'STARTED') {
        return {
          recorded: false,
          effectId: rec.id,
          state: rec.state,
          reasonCode: rec.state === 'IN_DOUBT' ? 'EFFECT_DEADLINE_EXCEEDED' : 'EFFECT_NOT_STARTED',
        };
      }
      const attempt = args.attempt !== undefined ? Number(args.attempt) : rec.attempt;
      const leaseToken = args.leaseToken !== undefined ? String(args.leaseToken) : rec.leaseToken;
      if (attempt !== rec.attempt || leaseToken !== rec.leaseToken) {
        return {
          recorded: false,
          effectId: rec.id,
          state: rec.state,
          reasonCode: 'STALE_ATTEMPT_OR_LEASE',
          message: 'DENIED: stale attempt number or lease token',
        };
      }
      const stepIndex = Number(args.stepIndex);
      if (!Number.isInteger(stepIndex) || stepIndex < 1 || stepIndex > rec.totalSteps) {
        throw new Error(`stepIndex ${stepIndex} out of bounds 1..${rec.totalSteps}`);
      }
      const existing = rec.steps.find((s) => s.stepIndex === stepIndex);
      if (existing) {
        return {
          recorded: true,
          deduplicated: true,
          effectId: rec.id,
          attempt: rec.attempt,
          stepIndex,
          totalSteps: rec.totalSteps,
          state: rec.state,
          receipt: existing,
          rootHex: effectLifecycleRootHex(),
        };
      }
      const outputDigest = resolveDigest(args.outputDigest, args.output);
      const stateChanged = Boolean(args.stateChanged);
      const ev = sealLifecycleEvent({
        effectId: rec.id,
        effectKey: rec.effectKey,
        idempotencyKey: rec.idempotencyKey,
        kind: 'STEP',
        state: 'STARTED',
        attempt: rec.attempt,
        stepIndex,
        totalSteps: rec.totalSteps,
        actor: String(args.actor || state.session.caller),
        owner: rec.cleanupOwner,
        reversalClass: rec.reversalClass,
        stateChanged,
        readbackDigest: outputDigest,
        fenceDigest: ZERO_DIGEST_HEX,
        observedHeight: now,
        deadlineHeight: rec.deadlineMs,
        height: now,
      });
      const receipt = {
        attempt: rec.attempt,
        stepIndex,
        totalSteps: rec.totalSteps,
        stepName: String(args.stepName || `step-${stepIndex}`),
        outputDigest,
        stateChanged,
        atMs: now,
        leafHash: ev.leafHash,
      };
      rec.steps.push(receipt);
      rec.lastEventHash = ev.leafHash;
      return {
        recorded: true,
        deduplicated: false,
        effectId: rec.id,
        attempt: rec.attempt,
        stepIndex,
        totalSteps: rec.totalSteps,
        state: rec.state,
        receipt,
        rootHex: effectLifecycleRootHex(),
      };
    }

    case 'arobi_close_effect': {
      const now = Number.isFinite(Number(args.nowMs)) ? Math.trunc(Number(args.nowMs)) : Date.now();
      const effectId = String(args.effectId || '').trim();
      const rec = state.effects.get(effectId);
      if (!rec) throw new Error(`unknown effectId: ${effectId}`);
      if (rec.state !== 'STARTED' && rec.state !== 'IN_DOUBT') {
        throw new Error(`cannot close effect ${effectId} in state ${rec.state}`);
      }
      const attempt = args.attempt !== undefined ? Number(args.attempt) : rec.attempt;
      const leaseToken = args.leaseToken !== undefined ? String(args.leaseToken) : rec.leaseToken;
      if (attempt !== rec.attempt || leaseToken !== rec.leaseToken) {
        return {
          closed: false,
          verdict: 'DENY',
          effectId: rec.id,
          state: rec.state,
          reasonCode: 'STALE_ATTEMPT_OR_LEASE',
          message: 'DENIED: stale attempt number or lease token',
        };
      }

      const requested = String(args.requestedOutcome || 'COMMITTED').trim();
      if (!['COMMITTED', 'ABORTED', 'PARTIAL'].includes(requested)) {
        throw new Error(`requestedOutcome must be COMMITTED, ABORTED, or PARTIAL`);
      }
      const readbackDigest = resolveDigest(args.readbackDigest, args.readback);
      const fenceDigest = resolveDigest(args.fenceDigest, args.fenceProof);
      const observedMs = args.observedMs !== undefined ? Math.trunc(Number(args.observedMs)) : now;

      if (readbackDigest !== ZERO_DIGEST_HEX) {
        if (observedMs < rec.startMs) {
          return {
            closed: false,
            verdict: 'DENY',
            effectId: rec.id,
            state: rec.state,
            reasonCode: 'READBACK_BEFORE_START',
            message: 'DENIED: read-back observation timestamp predates effect start',
          };
        }
        if (observedMs > now) {
          return {
            closed: false,
            verdict: 'DENY',
            effectId: rec.id,
            state: rec.state,
            reasonCode: 'READBACK_IN_FUTURE',
            message: 'DENIED: read-back observation timestamp is in the future',
          };
        }
        if (now - observedMs > rec.maxReadbackAgeMs) {
          return {
            closed: false,
            verdict: 'DENY',
            effectId: rec.id,
            state: rec.state,
            reasonCode: 'READBACK_TOO_OLD',
            message: 'DENIED: read-back observation exceeds allowed age',
          };
        }
      }

      const stateChanged = Boolean(args.stateChanged);
      const anyStepChanged = rec.steps.some((s) => s.stateChanged);

      // Checked close:
      // - COMMITTED requires fresh readback, stateChanged=true, and all steps recorded.
      // - "Nothing seen" closes ABORTED ONLY with a non-zero fenceDigest proving the grant cannot land later;
      //   without a fence it remains IN_DOUBT and holds the effect-key fence.
      let finalState = requested;
      if (requested === 'COMMITTED') {
        if (!stateChanged || readbackDigest === ZERO_DIGEST_HEX) {
          if (anyStepChanged) {
            finalState = 'PARTIAL';
          } else if (fenceDigest !== ZERO_DIGEST_HEX) {
            finalState = 'ABORTED';
          } else {
            finalState = 'IN_DOUBT';
          }
        } else if (rec.steps.length < rec.totalSteps) {
          finalState = 'PARTIAL';
        }
      } else if (requested === 'ABORTED') {
        if (anyStepChanged) {
          finalState = 'PARTIAL';
        } else if (fenceDigest === ZERO_DIGEST_HEX) {
          finalState = 'IN_DOUBT';
        }
      }

      rec.state = finalState;
      rec.readbackDigest = readbackDigest;
      rec.fenceDigest = fenceDigest;
      if (finalState === 'COMMITTED' || finalState === 'ABORTED') {
        rec.closedMs = now;
        state.openEffectsByKey.delete(rec.effectKey);
      }

      const ev = sealLifecycleEvent({
        effectId: rec.id,
        effectKey: rec.effectKey,
        idempotencyKey: rec.idempotencyKey,
        kind: 'CLOSE',
        state: finalState,
        attempt: rec.attempt,
        stepIndex: rec.steps.length,
        totalSteps: rec.totalSteps,
        actor: String(args.actor || state.session.caller),
        owner: rec.cleanupOwner,
        reversalClass: rec.reversalClass,
        stateChanged: stateChanged || anyStepChanged,
        readbackDigest,
        fenceDigest,
        observedHeight: observedMs,
        deadlineHeight: rec.deadlineMs,
        height: now,
      });
      rec.lastEventHash = ev.leafHash;

      const rootHex = effectLifecycleRootHex();
      const lifecycleBundle = {
        events: state.effectEvents.map((e) => ({ ...e })),
        rootHex,
        targetEffectId: rec.id,
        expectedFinalState: finalState,
      };
      const verified = verifyEffectLifecycleChain(lifecycleBundle);
      return {
        closed: true,
        effectId: rec.id,
        attempt: rec.attempt,
        requestedOutcome: requested,
        state: finalState,
        fenced: state.openEffectsByKey.has(rec.effectKey),
        readbackDigest,
        fenceDigest,
        rootHex,
        verified: verified.verified,
        lifecycleBundle,
      };
    }

    case 'arobi_list_open_effects': {
      const now = Number.isFinite(Number(args.nowMs)) ? Math.trunc(Number(args.nowMs)) : Date.now();
      const obligations = [];
      for (const effectId of state.openEffectsByKey.values()) {
        const rec = state.effects.get(effectId);
        if (rec && (rec.state === 'IN_DOUBT' || rec.state === 'PARTIAL')) {
          obligations.push({
            effectId: rec.id,
            effectKey: rec.effectKey,
            state: rec.state,
            attempt: rec.attempt,
            cleanupOwner: rec.cleanupOwner,
            reversalClass: rec.reversalClass,
            ageMs: Math.max(0, now - rec.startMs),
            stepsRecorded: rec.steps.length,
            totalSteps: rec.totalSteps,
            steps: rec.steps,
            recoveryAttempts: rec.recoveryAttempts,
            maxRecoveryAttempts: rec.maxRecoveryAttempts,
            deadlineMs: rec.deadlineMs,
            postcondition: rec.postcondition,
            undoSpec: rec.undoSpec,
          });
        }
      }
      return {
        count: obligations.length,
        obligations,
        rootHex: effectLifecycleRootHex(),
        eventCount: state.effectEvents.length,
      };
    }

    case 'arobi_compensate': {
      if (state.sessionPaused) {
        return {
          compensated: false,
          verdict: 'DENY',
          reasonCode: 'COMPENSATION_BLOCKED_WHILE_PAUSED',
          message: 'DENIED: compensation cannot start while session or grant is paused',
        };
      }
      const now = Number.isFinite(Number(args.nowMs)) ? Math.trunc(Number(args.nowMs)) : Date.now();
      const originalEffectId = String(args.originalEffectId || args.effectId || '').trim();
      const orig = state.effects.get(originalEffectId);
      if (!orig) throw new Error(`unknown effectId: ${originalEffectId}`);
      if (orig.state !== 'IN_DOUBT' && orig.state !== 'PARTIAL') {
        throw new Error(`only IN_DOUBT or PARTIAL effects may be compensated or accepted; state=${orig.state}`);
      }

      if (args.acceptPartial) {
        const humanApprover = String(args.humanApprover || '').trim();
        const reasonDigest = resolveDigest(args.readbackDigest, args.reason || args.readback);
        if (!humanApprover || reasonDigest === ZERO_DIGEST_HEX) {
          return {
            accepted: false,
            verdict: 'DENY',
            reasonCode: 'HUMAN_APPROVAL_AND_REASON_REQUIRED',
          };
        }
        orig.state = 'ACCEPTED';
        orig.humanApprovalId = humanApprover;
        orig.readbackDigest = reasonDigest;
        orig.closedMs = now;
        state.openEffectsByKey.delete(orig.effectKey);
        const ev = sealLifecycleEvent({
          effectId: orig.id,
          effectKey: orig.effectKey,
          idempotencyKey: orig.idempotencyKey,
          kind: 'ACCEPT',
          state: 'ACCEPTED',
          attempt: orig.attempt,
          stepIndex: orig.steps.length,
          totalSteps: orig.totalSteps,
          actor: humanApprover,
          owner: orig.cleanupOwner,
          reversalClass: orig.reversalClass,
          stateChanged: false,
          readbackDigest: reasonDigest,
          fenceDigest: ZERO_DIGEST_HEX,
          observedHeight: now,
          humanApproval: humanApprover,
          deadlineHeight: orig.deadlineMs,
          height: now,
        });
        orig.lastEventHash = ev.leafHash;
        const rootHex = effectLifecycleRootHex();
        const lifecycleBundle = {
          events: state.effectEvents.map((e) => ({ ...e })),
          rootHex,
          targetEffectId: orig.id,
          expectedFinalState: 'ACCEPTED',
        };
        return {
          accepted: true,
          originalEffectId: orig.id,
          state: 'ACCEPTED',
          fenced: false,
          rootHex,
          verified: verifyEffectLifecycleChain(lifecycleBundle).verified,
          lifecycleBundle,
        };
      }

      if (orig.reversalClass === 'IRREVERSIBLE') {
        return {
          compensated: false,
          verdict: 'DENY',
          reasonCode: 'IRREVERSIBLE_CANNOT_AUTO_COMPENSATE',
          message: 'IRREVERSIBLE effect requires explicit human acceptPartial=true',
        };
      }

      const compIdem = String(args.compIdempotencyKey || `comp:${orig.id}:${orig.recoveryAttempts + 1}`).trim();
      if (state.effectsByIdempotency.has(compIdem)) {
        const compId = state.effectsByIdempotency.get(compIdem);
        return {
          compensated: true,
          deduplicated: true,
          originalEffectId: orig.id,
          compensationEffectId: compId,
          state: orig.state,
          fenced: state.openEffectsByKey.has(orig.effectKey),
          rootHex: effectLifecycleRootHex(),
        };
      }

      if (orig.recoveryAttempts >= orig.maxRecoveryAttempts) {
        return {
          compensated: false,
          verdict: 'DENY',
          reasonCode: 'RECOVERY_LIMIT_EXCEEDED',
          recoveryAttempts: orig.recoveryAttempts,
          maxRecoveryAttempts: orig.maxRecoveryAttempts,
          message: 'DENIED: bounded recovery attempt limit exceeded',
        };
      }

      const compDeadlineMs = args.compDeadlineMs !== undefined ? Math.trunc(Number(args.compDeadlineMs)) : now + 10_000;
      if (compDeadlineMs <= now) {
        return {
          compensated: false,
          verdict: 'DENY',
          reasonCode: 'INVALID_COMPENSATION_DEADLINE',
          message: 'compDeadlineMs must be strictly greater than current timestamp',
        };
      }

      orig.recoveryAttempts += 1;
      const recAttempt = orig.recoveryAttempts;
      state.effectCount += 1;
      const compId = `eff-${state.effectCount}`;
      const compLease = deriveLeaseToken(compId, recAttempt, compIdem);
      const actor = String(args.actor || orig.cleanupOwner);
      const readbackDigest = resolveDigest(args.readbackDigest, args.readback);
      const observedMs = args.observedMs !== undefined ? Math.trunc(Number(args.observedMs)) : now;
      const readbackFresh = readbackDigest !== ZERO_DIGEST_HEX
        && observedMs >= orig.startMs
        && observedMs <= now
        && (now - observedMs) <= orig.maxReadbackAgeMs;

      if (!args.restoredOriginalState || !readbackFresh) {
        const failedComp = {
          id: compId,
          effectKey: `${orig.effectKey}:compensate:${recAttempt}`,
          idempotencyKey: compIdem,
          state: 'IN_DOUBT',
          attempt: recAttempt,
          leaseToken: compLease,
          totalSteps: 1,
          postcondition: `restored state prior to ${orig.id}`,
          reversalClass: 'COMPENSABLE',
          undoSpec: orig.undoSpec,
          cleanupOwner: orig.cleanupOwner,
          humanApprovalId: '',
          startMs: now,
          deadlineMs: compDeadlineMs,
          closedMs: null,
          maxReadbackAgeMs: orig.maxReadbackAgeMs,
          maxRecoveryAttempts: 1,
          recoveryAttempts: 0,
          steps: [],
          readbackDigest,
          fenceDigest: ZERO_DIGEST_HEX,
          compensatedById: null,
          supersedesId: orig.id,
          lastEventHash: ZERO_DIGEST_HEX,
        };
        const failEv = sealLifecycleEvent({
          effectId: failedComp.id,
          effectKey: failedComp.effectKey,
          idempotencyKey: failedComp.idempotencyKey,
          kind: 'COMPENSATE',
          state: 'IN_DOUBT',
          attempt: recAttempt,
          stepIndex: 0,
          totalSteps: 1,
          actor,
          owner: failedComp.cleanupOwner,
          reversalClass: failedComp.reversalClass,
          stateChanged: false,
          readbackDigest,
          fenceDigest: ZERO_DIGEST_HEX,
          observedHeight: observedMs,
          supersedesId: orig.id,
          deadlineHeight: failedComp.deadlineMs,
          height: now,
        });
        failedComp.lastEventHash = failEv.leafHash;
        state.effects.set(failedComp.id, failedComp);
        state.effectsByIdempotency.set(failedComp.idempotencyKey, failedComp.id);
        return {
          compensated: false,
          verdict: 'DENY',
          reasonCode: 'RESTORED_READBACK_REQUIRED',
          originalEffectId: orig.id,
          compensationEffectId: failedComp.id,
          compensationState: 'IN_DOUBT',
          recoveryAttempts: orig.recoveryAttempts,
          maxRecoveryAttempts: orig.maxRecoveryAttempts,
          rootHex: effectLifecycleRootHex(),
          message: 'COMPENSATED requires fresh non-zero read-back confirming restored state; recovery marked IN_DOUBT',
        };
      }

      const comp = {
        id: compId,
        effectKey: `${orig.effectKey}:compensate:${recAttempt}`,
        idempotencyKey: compIdem,
        state: 'COMMITTED',
        attempt: recAttempt,
        leaseToken: compLease,
        totalSteps: 1,
        postcondition: `restored state prior to ${orig.id}`,
        reversalClass: 'COMPENSABLE',
        undoSpec: orig.undoSpec,
        cleanupOwner: orig.cleanupOwner,
        humanApprovalId: '',
        startMs: now,
        deadlineMs: compDeadlineMs,
        closedMs: now,
        maxReadbackAgeMs: orig.maxReadbackAgeMs,
        maxRecoveryAttempts: 1,
        recoveryAttempts: 0,
        steps: [],
        readbackDigest,
        fenceDigest: ZERO_DIGEST_HEX,
        compensatedById: null,
        supersedesId: orig.id,
        lastEventHash: ZERO_DIGEST_HEX,
      };
      const compEv = sealLifecycleEvent({
        effectId: comp.id,
        effectKey: comp.effectKey,
        idempotencyKey: comp.idempotencyKey,
        kind: 'COMPENSATE',
        state: 'COMMITTED',
        attempt: recAttempt,
        stepIndex: 1,
        totalSteps: 1,
        actor,
        owner: comp.cleanupOwner,
        reversalClass: comp.reversalClass,
        stateChanged: true,
        readbackDigest,
        fenceDigest: ZERO_DIGEST_HEX,
        observedHeight: observedMs,
        supersedesId: orig.id,
        deadlineHeight: comp.deadlineMs,
        height: now,
      });
      comp.lastEventHash = compEv.leafHash;
      state.effects.set(comp.id, comp);
      state.effectsByIdempotency.set(comp.idempotencyKey, comp.id);

      orig.state = 'COMPENSATED';
      orig.compensatedById = comp.id;
      orig.readbackDigest = readbackDigest;
      orig.closedMs = now;
      state.openEffectsByKey.delete(orig.effectKey);

      const origEv = sealLifecycleEvent({
        effectId: orig.id,
        effectKey: orig.effectKey,
        idempotencyKey: orig.idempotencyKey,
        kind: 'COMPENSATE',
        state: 'COMPENSATED',
        attempt: recAttempt,
        stepIndex: orig.steps.length,
        totalSteps: orig.totalSteps,
        actor,
        owner: orig.cleanupOwner,
        reversalClass: orig.reversalClass,
        stateChanged: true,
        readbackDigest,
        fenceDigest: ZERO_DIGEST_HEX,
        observedHeight: observedMs,
        supersedesId: comp.id,
        deadlineHeight: orig.deadlineMs,
        height: now,
      });
      orig.lastEventHash = origEv.leafHash;

      const rootHex = effectLifecycleRootHex();
      const lifecycleBundle = {
        events: state.effectEvents.map((e) => ({ ...e })),
        rootHex,
        targetEffectId: orig.id,
        expectedFinalState: 'COMPENSATED',
      };
      const verified = verifyEffectLifecycleChain(lifecycleBundle);
      return {
        compensated: true,
        deduplicated: false,
        originalEffectId: orig.id,
        compensationEffectId: comp.id,
        recoveryAttempt: recAttempt,
        state: orig.state,
        fenced: state.openEffectsByKey.has(orig.effectKey),
        readbackDigest,
        rootHex,
        verified: verified.verified,
        lifecycleBundle,
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
