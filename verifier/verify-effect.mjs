// Arobi Assurance Agent SDK: offline verifier for one effect's whole life.
//
// Byte-for-byte twin of EffectSpec, EffectEvent and VerifyEffectLife in gno.land/p/arobi/assurance (encoding
// version 1). It reads the JSON that gno.land/r/arobi/effects returns from EffectJSON(id), as the raw JSON or as the
// `data: ("..." string)` line of `gnokey query vm/qeval`, and checks without trusting the agent or the realm's reads:
//   - the spec digest and every event's RFC 6962 leaf are recomputed from their fields;
//   - the events form one hash chain from a zero genesis, with no gap, fork or reordering;
//   - every transition is one the lifecycle allows, by the actor allowed to make it, at a height it allows, and every
//     close's state is the one its read-back computes (a pre-state read-back is ABORTED only after a fence);
//   - with a "proofs" object ({ "<leaf index>": ["hex", ...] }), each event's inclusion in the tree of tree_size
//     under root.
// Zero dependencies. CLI: node verifier/verify-effect.mjs <effect.json>  (exit 0 and the final state when it verifies)

import crypto from 'node:crypto';
import fs from 'node:fs';
import { verifyInclusion } from './verify-evidence.mjs';

export const ENCODING_VERSION = 1;
export const DOMAIN_EFFECT_SPEC = 'arobi-assurance-effect-spec-v1';
export const DOMAIN_EFFECT_EVENT = 'arobi-assurance-effect-event-v1';
export const MAX_EFFECT_STEPS = 32;
export const MAX_EFFECT_DEADLINE_BLOCKS = 302400;
export const MAX_READ_BACK_AGE_BLOCKS = 600;
export const MAX_COMPENSATIONS = 3;
const ZERO = '0'.repeat(64);
const TERMINAL = new Set(['ABORTED', 'COMPENSATED', 'ACCEPTED']);

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest();
const str = (s) => {
  const b = Buffer.from(String(s), 'utf8');
  const n = Buffer.alloc(4);
  n.writeUInt32BE(b.length);
  return Buffer.concat([n, b]);
};
const u32 = (v) => { const b = Buffer.alloc(4); b.writeUInt32BE(Number(v)); return b; };
const u64 = (v) => { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt.asUintN(64, BigInt(v))); return b; };
const dig = (hex) => {
  if (typeof hex !== 'string' || !/^[0-9a-f]{64}$/.test(hex)) throw new Error(`not a 64-character hex digest: ${hex}`);
  return Buffer.from(hex, 'hex');
};
export const leafHash = (data) => sha256(Buffer.concat([Buffer.from([0x00]), data]));

export function encodeSpec(s) {
  return Buffer.concat([
    str(DOMAIN_EFFECT_SPEC), Buffer.from([ENCODING_VERSION]), str(s.agent_id), str(s.effect_key), str(s.idempotency_key),
    u32(s.attempt), u32(s.steps), str(s.reversal), str(s.inverse), str(s.read_back),
    Buffer.from([s.downstream_honours_live ? 1 : 0]), dig(s.pre_state), dig(s.postcondition),
    u64(s.deadline_blocks), str(s.cleanup_owner), u64(s.approval_id), u64(s.compensates),
  ]);
}

export function encodeEvent(id, e) {
  return Buffer.concat([
    str(DOMAIN_EFFECT_EVENT), Buffer.from([ENCODING_VERSION]), u64(id), u32(e.attempt), u32(e.seq), dig(e.prev_hash),
    str(e.kind), str(e.state), str(e.actor), u64(e.height), u32(e.step_index), dig(e.digest), u64(e.observed_height), u64(e.link),
  ]);
}

export function validateSpec(s) {
  const fail = (m) => { throw new Error(`spec: ${m}`); };
  if (!s.agent_id) fail('agent id is empty');
  if (!s.effect_key || s.effect_key.length > 96 || !s.idempotency_key || s.idempotency_key.length > 96) fail('keys must be 1..96 bytes');
  if (s.attempt < 1) fail('attempt starts at 1');
  if (s.steps < 1 || s.steps > MAX_EFFECT_STEPS) fail('steps out of range');
  if (s.deadline_blocks < 1 || s.deadline_blocks > MAX_EFFECT_DEADLINE_BLOCKS) fail('a deadline is required');
  if (!s.cleanup_owner) fail('a cleanup owner is required');
  if (s.read_back !== 'REALM' && s.read_back !== 'AGENT') fail('read-back must be REALM or AGENT');
  if (typeof s.downstream_honours_live !== 'boolean') fail('downstream_honours_live must be true or false');
  if (s.read_back === 'REALM' && !s.downstream_honours_live) fail("a realm read-back's downstream is the realm, which honours EffectLive");
  if (s.pre_state === s.postcondition) fail('the postcondition equals the pre-state');
  if (s.reversal === 'REVERSIBLE' || s.reversal === 'COMPENSABLE') {
    if (!s.inverse) fail(`a ${s.reversal} effect names how it is undone`);
    if (s.approval_id !== 0 && s.compensates === 0) fail('only an IRREVERSIBLE effect, or the compensation of an effect that may still land, consumes an approval');
  } else if (s.reversal === 'IRREVERSIBLE') {
    if (s.inverse) fail('an IRREVERSIBLE effect has no inverse');
    if (s.approval_id === 0) fail('an IRREVERSIBLE effect needs a recorded human approval');
    if (s.compensates !== 0) fail('a compensation cannot be IRREVERSIBLE');
  } else fail('unknown reversal class');
}

/** Something sent under the effect may still land after a fence or the deadline (EffectSpec.Landable). */
export const landable = (s) => s.read_back === 'AGENT' && !s.downstream_honours_live;

export function closeOutcome(s, readBack, fencedBeforeRead) {
  if (readBack === s.postcondition) return 'COMMITTED';
  if (readBack === s.pre_state) return fencedBeforeRead ? 'ABORTED' : 'IN_DOUBT';
  return 'PARTIAL';
}

/** The lifecycle check of VerifyEffectLife. Returns the last sealed state or throws why the life does not verify. */
export function verifyLife(id, s, events) {
  validateSpec(s);
  if (!events.length) throw new Error('no events');
  const first = events[0];
  if (first.kind !== 'START' || first.seq !== 0 || first.prev_hash !== ZERO || first.state !== 'STARTED' || first.attempt !== s.attempt) {
    throw new Error('the first event must be START, seq 0, of this attempt, with a zero previous hash');
  }
  if (first.digest !== sha256(encodeSpec(s)).toString('hex')) throw new Error('START does not seal this spec');
  const executor = first.actor, deadline = first.height + s.deadline_blocks;
  let state = 'STARTED', steps = 0, lastStepHeight = first.height, fenced = false, fenceSeq = 0, fenceHeight = 0, comps = 0;
  const links = new Set();
  for (let i = 1; i < events.length; i++) {
    const ev = events[i], prev = events[i - 1], at = `event ${i}: `;
    if (ev.attempt !== s.attempt) throw new Error(at + 'belongs to another attempt');
    if (ev.seq !== i || ev.prev_hash !== leafHash(encodeEvent(id, prev)).toString('hex')) throw new Error(at + 'breaks the hash chain (a gap, a fork or a reordering)');
    if (ev.height < prev.height) throw new Error(at + 'goes back in height');
    if (TERMINAL.has(state)) throw new Error(at + 'follows a terminal state');
    let next = state;
    switch (ev.kind) {
      case 'STEP':
        if (state !== 'STARTED' || fenced || ev.actor !== executor || ev.height > deadline || ev.step_index !== steps + 1 || ev.step_index > s.steps) {
          throw new Error(at + 'is not a step the executor may record here');
        }
        steps++; lastStepHeight = ev.height;
        break;
      case 'FENCE':
        if (fenced || (state !== 'STARTED' && state !== 'IN_DOUBT') || (ev.actor !== executor && ev.actor !== s.cleanup_owner)) {
          throw new Error(at + 'is not a fence this actor may seal here');
        }
        fenced = true; fenceSeq = ev.seq; fenceHeight = ev.height;
        break;
      case 'CLOSE': {
        const byExecutor = state === 'STARTED' && ev.actor === executor && ev.height <= deadline;
        const byOwner = state === 'IN_DOUBT' && ev.actor === s.cleanup_owner;
        if (!byExecutor && !byOwner) throw new Error(at + 'is not a close this actor may make here');
        let fencedBefore;
        if (s.read_back === 'REALM') {
          if (ev.observed_height !== ev.height) throw new Error(at + 'a realm read-back is observed at its own close');
          fencedBefore = (fenced && fenceSeq < ev.seq) || ev.height > deadline;
        } else {
          if (ev.observed_height < lastStepHeight || ev.observed_height > ev.height || ev.height - ev.observed_height > MAX_READ_BACK_AGE_BLOCKS) {
            throw new Error(at + 'the read-back is older than the last step, from the future, or too old');
          }
          // A fence or the clock proves nothing about a downstream that does not honour EffectLive.
          fencedBefore = !landable(s) && ((fenced && ev.observed_height > fenceHeight) || ev.observed_height > deadline);
        }
        if (ev.digest === ZERO) throw new Error(at + 'a close needs a read-back digest');
        next = closeOutcome(s, ev.digest, fencedBefore);
        break;
      }
      case 'IN_DOUBT':
        if (state !== 'STARTED' || ev.height <= deadline) throw new Error(at + 'IN_DOUBT before the deadline height');
        next = 'IN_DOUBT';
        break;
      case 'COMPENSATE':
        if (s.reversal === 'IRREVERSIBLE' || ev.actor !== s.cleanup_owner || ev.link === 0 || !['PARTIAL', 'IN_DOUBT', 'COMMITTED'].includes(state)) {
          throw new Error(at + 'is not a compensation the cleanup owner may start here');
        }
        if (++comps > MAX_COMPENSATIONS) throw new Error(at + 'more compensations than allowed');
        if (landable(s) && state !== 'COMMITTED' && ev.digest === ZERO) {
          throw new Error(at + "compensates an effect that may still land without the owner's recorded approval");
        }
        links.add(ev.link);
        break;
      case 'COMPENSATED':
        if (!links.has(ev.link) || ev.digest !== s.pre_state) throw new Error(at + 'COMPENSATED without its compensation, or not back at the pre-state');
        next = 'COMPENSATED';
        break;
      case 'ACCEPT':
        if (ev.actor !== s.cleanup_owner || (state !== 'PARTIAL' && state !== 'IN_DOUBT') || (state === 'IN_DOUBT' && !fenced)) {
          throw new Error(at + 'is not an acceptance the cleanup owner may make here (an IN_DOUBT effect is fenced first)');
        }
        next = 'ACCEPTED';
        break;
      default:
        throw new Error(at + `unknown kind ${ev.kind}`);
    }
    if (ev.state !== next) throw new Error(at + `seals ${ev.state} where the lifecycle gives ${next}`);
    state = next;
  }
  return state;
}

/** Parses EffectJSON output, raw or as gnokey's `data: ("..." string)` line. */
export function parseEffectJson(text) {
  const t = String(text).trim();
  const m = t.match(/\("((?:[^"\\]|\\.)*)" string\)/s);
  return JSON.parse(m ? JSON.parse(`"${m[1]}"`) : t);
}

/** Verifies one effect's life as EffectJSON returns it. Returns { state, events } or throws. */
export function verifyEffect(doc) {
  const s = doc.spec;
  if (doc.spec_digest !== sha256(encodeSpec(s)).toString('hex')) throw new Error('spec_digest does not match the spec');
  for (const ev of doc.events) {
    if (ev.leaf !== leafHash(encodeEvent(doc.id, ev)).toString('hex')) throw new Error(`event ${ev.seq}: its leaf does not match its fields`);
  }
  const state = verifyLife(doc.id, s, doc.events);
  if (state !== doc.state) throw new Error(`the events end in ${state}, the realm says ${doc.state}`);
  if (doc.proofs) {
    for (const ev of doc.events) {
      const proof = doc.proofs[String(ev.index)] ?? [];
      if (!verifyInclusion(ev.index, doc.tree_size, ev.leaf, proof, doc.root)) throw new Error(`event ${ev.seq}: not included under the root`);
    }
  }
  return { state, events: doc.events.length };
}

if (process.argv[1]?.replace(/\\/g, '/').endsWith('verify-effect.mjs')) {
  try {
    const r = verifyEffect(parseEffectJson(fs.readFileSync(process.argv[2], 'utf8')));
    console.log(`VERIFIED effect life: ${r.events} events, ${r.state}`);
  } catch (e) {
    console.error(`NOT VERIFIED: ${e.message}`);
    process.exit(1);
  }
}
