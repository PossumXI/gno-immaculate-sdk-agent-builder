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
    this.compactions = { auto: 0, manual: 0, maxPreTokens: 0, events: [] };
    this.sessionMeta = { model: '', cwd: '', gnoshVersion: '' };
    this._pendingToolUses = new Map();
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

  /**
   * Parse newline-delimited JSON lines from `gnosh -p --output-format stream-json --verbose`
   * (supporting native Gnosh `system`/`init`, `system`/`compact_boundary`, `assistant` `tool_use`,
   * `user` `tool_result`, and `result` `permission_denials`, as well as legacy `tool_result`/`frame_pop` lines).
   */
  ingestNdjsonStream(ndjsonText, baseHeight = 1) {
    const recorded = [];
    let offset = 0;

    const flattenContent = (content) => {
      if (typeof content === 'string') return content;
      if (Array.isArray(content)) {
        return content
          .map((b) => (typeof b === 'string' ? b : b?.text || b?.type || JSON.stringify(b)))
          .join('\n');
      }
      return content == null ? '' : JSON.stringify(content);
    };

    for (const rawLine of String(ndjsonText).split(/\r?\n/)) {
      const line = rawLine.trim();
      if (!line) continue;
      const ev = JSON.parse(line);

      // 1. Native gnosh stream-json: system/init & system/compact_boundary
      if (ev.type === 'system') {
        if (ev.subtype === 'init') {
          if (ev.session_id && !this.sessionId) this.sessionId = String(ev.session_id);
          this.sessionMeta = {
            model: String(ev.model || ''),
            cwd: String(ev.cwd || ''),
            gnoshVersion: String(ev.gnosh_version || ''),
          };
        } else if (ev.subtype === 'compact_boundary') {
          const meta = ev.compact_metadata || {};
          const trigger = String(meta.trigger || 'unknown');
          const preTokens = Number(meta.pre_tokens || 0);
          if (trigger === 'auto') this.compactions.auto += 1;
          else if (trigger === 'manual') this.compactions.manual += 1;
          if (preTokens > this.compactions.maxPreTokens) this.compactions.maxPreTokens = preTokens;
          this.compactions.events.push({ trigger, preTokens, uuid: ev.uuid || '' });
          recorded.push(
            this.recordFrameEvent({
              frameId: ev.uuid || `compact-${offset + 1}`,
              toolName: `compact_boundary:${trigger}`,
              target: 'context_window',
              input: JSON.stringify({ trigger, preTokens }),
              output: `compacted:${trigger}:${preTokens}`,
              witness: `gnosh-compact:${trigger}`,
              verdict: 'ALLOW',
              reasonCode: trigger === 'auto' ? 'GNOSH_AUTO_COMPACT' : 'GNOSH_MANUAL_COMPACT',
              outcome: 'EXECUTED',
              riskTier: 'LOW',
              height: baseHeight + offset,
            }),
          );
          offset += 1;
        }
        continue;
      }

      // 2. Native gnosh stream-json: assistant message containing tool_use blocks
      if (ev.type === 'assistant' && Array.isArray(ev.message?.content)) {
        for (const blk of ev.message.content) {
          if (blk && blk.type === 'tool_use' && blk.id) {
            this._pendingToolUses.set(String(blk.id), {
              id: String(blk.id),
              parentId: ev.parent_tool_use_id ? String(ev.parent_tool_use_id) : '',
              name: String(blk.name || 'gnosh_tool'),
              input: blk.input ?? {},
            });
          }
        }
        continue;
      }

      // 3. Native gnosh stream-json: user message containing tool_result blocks
      if (ev.type === 'user' && Array.isArray(ev.message?.content)) {
        for (const blk of ev.message.content) {
          if (blk && blk.type === 'tool_result') {
            const callId = String(blk.tool_use_id || `call-${offset + 1}`);
            const use = this._pendingToolUses.get(callId);
            if (use) this._pendingToolUses.delete(callId);
            const inputObj = use?.input ?? {};
            const target =
              (typeof inputObj === 'object' && inputObj && (inputObj.file_path || inputObj.path || inputObj.command))
                ? String(inputObj.file_path || inputObj.path || inputObj.command).slice(0, 160)
                : 'workspace';
            recorded.push(
              this.recordFrameEvent({
                frameId: callId,
                parentFrameId: use?.parentId || (ev.parent_tool_use_id ? String(ev.parent_tool_use_id) : ''),
                toolName: use?.name || 'gnosh_tool',
                target,
                input: typeof inputObj === 'string' ? inputObj : JSON.stringify(inputObj),
                output: flattenContent(blk.content),
                witness: ev.uuid || callId,
                verdict: 'ALLOW',
                reasonCode: blk.is_error ? 'GNOSH_TOOL_ERROR' : 'GNOSH_FRAME_OK',
                outcome: blk.is_error ? 'FAILED' : 'EXECUTED',
                riskTier: 'LOW',
                height: baseHeight + offset,
              }),
            );
            offset += 1;
          }
        }
        continue;
      }

      // 4. Native gnosh stream-json: result line permission_denials -> fail-closed DENY bundles
      if (ev.type === 'result' && Array.isArray(ev.permission_denials)) {
        for (const d of ev.permission_denials) {
          recorded.push(
            this.recordFrameEvent({
              frameId: String(d.tool_use_id || `deny-${offset + 1}`),
              toolName: String(d.tool_name || 'gnosh_tool'),
              target: 'permission_gate',
              input: typeof d.tool_input === 'string' ? d.tool_input : JSON.stringify(d.tool_input ?? {}),
              output: '',
              witness: 'gnosh-permission-denial',
              verdict: 'DENY',
              reasonCode: 'GNOSH_PERMISSION_DENIED',
              outcome: 'REFUSED',
              riskTier: 'HIGH',
              height: baseHeight + offset,
            }),
          );
          offset += 1;
        }
        continue;
      }

      // 5. Legacy flat frame events (`tool_result` / `frame_pop`)
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

// ---------------------------------------------------------------------------
// Cross-harness helpers shared between gnosh.ai, Ullumii, and Immaculate SDK
// ---------------------------------------------------------------------------

const DRAFT_JSON_SNIFF_BYTES = 64 * 1024;
const DRAFT_IMAGE_TOKENS = 1600;
const DRAFT_MAX_FILE_BYTES = 256 * 1024;

function looksLikeJson(text) {
  const head = text.slice(0, DRAFT_JSON_SNIFF_BYTES).trimStart();
  if (!head || (head[0] !== '{' && head[0] !== '[')) return false;
  const sample = head.slice(0, 4096);
  let punct = 0;
  for (let i = 0; i < sample.length; i++) {
    const ch = sample[i];
    if (ch === '{' || ch === '}' || ch === '[' || ch === ']' || ch === '"' || ch === ':' || ch === ',') punct++;
  }
  return punct * 100 > sample.length * 8;
}

/**
 * Pure local pre-send context budget estimator matching gnosh's `internal/ui/draftcontext.go`
 * and Ullumii/HUE's `contextBudget.ts` (bytes/3 prose, bytes/2 JSON, 1600 tokens/image).
 */
export function estimateGnoshContextBudget({
  usedTokens = 0,
  windowTokens = 200_000,
  compactPointTokens = 0,
  draftText = '',
  attachments = [],
} = {}) {
  const used = Math.max(0, Math.trunc(Number(usedTokens) || 0));
  const win = Math.max(1, Math.trunc(Number(windowTokens) || 200_000));
  const point = Math.max(0, Math.trunc(Number(compactPointTokens) || Math.floor(win * 0.85)));

  const textStr = String(draftText || '');
  const textBytes = Buffer.byteLength(textStr, 'utf8');
  let draftTokens = textBytes === 0 ? 0 : looksLikeJson(textStr) ? Math.ceil(textBytes / 2) : Math.ceil(textBytes / 3);

  const items = Array.isArray(attachments) ? attachments.slice(0, 10) : [];
  for (const att of items) {
    if (!att || typeof att !== 'object') continue;
    if (att.kind === 'image') {
      draftTokens += DRAFT_IMAGE_TOKENS;
      continue;
    }
    const sz = Math.min(DRAFT_MAX_FILE_BYTES, Math.max(0, Math.trunc(Number(att.bytes) || 0)));
    if (sz === 0) continue;
    const isJson = Boolean(att.isJson) || /\.(json|jsonl|jsonc)$/i.test(String(att.name || ''));
    draftTokens += isJson ? Math.ceil(sz / 2) : Math.ceil(sz / 3);
  }

  const projectedTokens = used + draftTokens;
  const overWindow = projectedTokens > win;
  const willCompact = !overWindow && point > 0 && projectedTokens >= point;
  const nearCompact = !overWindow && !willCompact && point > 0 && projectedTokens * 10 >= point * 9;
  const significant = draftTokens * 100 >= win || willCompact || overWindow;

  const status = overWindow ? 'over_window' : willCompact ? 'will_compact' : nearCompact ? 'near_compact' : 'ok';
  return {
    usedTokens: used,
    draftTokens,
    projectedTokens,
    windowTokens: win,
    compactPointTokens: point,
    usedPct: Math.floor((used * 100) / win),
    projectedPct: Math.floor((projectedTokens * 100) / win),
    significant,
    willCompact,
    overWindow,
    status,
  };
}

const PREFLIGHT_RULES = [
  {
    id: 'SKILL_PIPE_TO_SHELL',
    severity: 'CRITICAL',
    re: /\b(?:curl|wget)\b[^\n|]{0,200}\|\s*(?:sh|bash|zsh|pwsh|powershell|python3?)\b/i,
    reason: 'Remote script piped directly into a local shell',
  },
  {
    id: 'SKILL_PROMPT_OVERRIDE',
    severity: 'HIGH',
    re: /\b(?:ignore\s+(?:all\s+)?(?:previous|prior|system)\s+instructions|disable\s+(?:permission|safety|guard)|bypass\s+(?:sandbox|policy))\b/i,
    reason: 'Attempts to override harness safety or permission boundaries',
  },
  {
    id: 'SKILL_SECRET_EXFIL',
    severity: 'CRITICAL',
    re: /(?:~\/\.ssh|id_rsa|id_ed25519|\.aws\/credentials|ANTHROPIC_API_KEY|OPENAI_API_KEY|PRIVATE_KEY)[^\n]{0,120}(?:curl|wget|nc\b|http:\/\/|https:\/\/|base64)/i,
    reason: 'Potential credential harvesting or exfiltration pattern',
  },
  {
    id: 'SKILL_HIDDEN_UNICODE',
    severity: 'HIGH',
    re: /[\u202A-\u202E\u2066-\u2069\u200B-\u200F\uFEFF]/,
    reason: 'Contains invisible bidi/zero-width control characters that can spoof code review',
  },
];

/**
 * Monotone static preflight inspector for untrusted agent skills / MCP prompts
 * before loading them into gnosh.ai or Ullumii. Strictly fail-closed on CRITICAL/HIGH hits.
 */
export function inspectSkillPreflight({ name = 'unnamed-skill', source = 'unknown', body = '' } = {}) {
  const text = String(body || '');
  const findings = [];
  for (const rule of PREFLIGHT_RULES) {
    if (rule.re.test(text)) {
      findings.push({ id: rule.id, severity: rule.severity, reason: rule.reason });
    }
  }
  const hasCritical = findings.some((f) => f.severity === 'CRITICAL');
  const hasHigh = findings.some((f) => f.severity === 'HIGH');
  const verdict = hasCritical ? 'DENY' : hasHigh ? 'QUARANTINE' : 'ALLOW';
  return {
    name: String(name),
    source: String(source),
    contentDigest: sha256Hex(text),
    verdict,
    safeToLoad: verdict === 'ALLOW',
    findings,
  };
}

/**
 * Emit valid `gnomem/v2` Gno plan code honoring gnosh's `spec/gnosh/peers.md` §3 invariant:
 * `.Parallel()` is placed ONLY on the parent container todo (never on leaf todos, which gnosh
 * refuses because it causes helper sessions to serialize/wait), followed by an ordered final check.
 */
export function buildGnoshPeersPlanGno({
  rootName = 'plan',
  rootTitle = 'Governed parallel swarm plan',
  parallelGroupName = 'work',
  parallelGroupTitle = 'Run independent tasks in parallel',
  parallelSteps = [],
  finalCheckName = 'verify',
  finalCheckTitle = 'Verify combined result and anchor checkpoint',
  warrantRootHex = '',
} = {}) {
  if (!Array.isArray(parallelSteps) || parallelSteps.length < 2) {
    throw new Error('parallelSteps must contain at least 2 independent steps for a .Parallel() group');
  }
  const esc = (s) => JSON.stringify(String(s || ''));
  const lines = [
    `root := mem.Todo(${esc(rootName)}, ${esc(rootTitle)})`,
  ];
  if (warrantRootHex) {
    lines.push(`root.Note("immaculate_root", ${esc(String(warrantRootHex))})`);
  }
  lines.push(`grp := root.Todo(${esc(parallelGroupName)}, ${esc(parallelGroupTitle)}).Parallel()`);
  const seen = new Set();
  for (let i = 0; i < parallelSteps.length; i++) {
    const step = parallelSteps[i];
    const id = String(step?.name || `step_${i + 1}`).replace(/[^a-zA-Z0-9_-]/g, '_');
    if (seen.has(id)) throw new Error(`duplicate step name: ${id}`);
    seen.add(id);
    const title = String(step?.title || id);
    lines.push(`grp.Todo(${esc(id)}, ${esc(title)})`);
  }
  lines.push(`root.Todo(${esc(finalCheckName)}, ${esc(finalCheckTitle)})`);
  lines.push('mem.Next()');
  const gnoCode = lines.join('\n') + '\n';
  return {
    gnoCode,
    planDigestHex: sha256Hex(gnoCode),
    parallelGroup: `${rootName}/${parallelGroupName}`,
    orderedCheck: `${rootName}/${finalCheckName}`,
    stepCount: parallelSteps.length,
  };
}
