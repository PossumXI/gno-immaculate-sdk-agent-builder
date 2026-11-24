// Tests for verify-effect.mjs. A life is built here with the verifier's own encoders; the cross-check against the
// realm's own bytes is the txtar acceptance test, which runs this verifier on EffectJSON from a real node.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { encodeEvent, encodeSpec, leafHash, parseEffectJson, verifyEffect } from './verify-effect.mjs';

const h = (s) => crypto.createHash('sha256').update(s).digest('hex');
const ZERO = '0'.repeat(64);

function life() {
  const spec = {
    agent_id: 'worker-1', effect_key: 'ledger:alice', idempotency_key: 'pay-1', attempt: 1, steps: 3,
    reversal: 'COMPENSABLE', inverse: 'restore', read_back: 'REALM', downstream_honours_live: true, pre_state: h('before'), postcondition: h('after'),
    deadline_blocks: 3, cleanup_owner: 'g1cleanup', approval_id: 0, compensates: 0,
  };
  const raw = [
    { kind: 'START', state: 'STARTED', actor: 'g1exec', height: 10, digest: crypto.createHash('sha256').update(encodeSpec(spec)).digest('hex') },
    { kind: 'STEP', state: 'STARTED', actor: 'g1exec', height: 11, step_index: 1, digest: h('r1') },
    { kind: 'IN_DOUBT', state: 'IN_DOUBT', actor: 'g1anyone', height: 14 },
    { kind: 'COMPENSATE', state: 'IN_DOUBT', actor: 'g1cleanup', height: 15, link: 2 },
    { kind: 'COMPENSATED', state: 'COMPENSATED', actor: 'g1cleanup', height: 18, digest: spec.pre_state, link: 2 },
  ];
  return { id: 1, spec, raw };
}

function seal({ id, spec, raw }) {
  let prev = ZERO;
  const events = raw.map((e, seq) => {
    const ev = { attempt: spec.attempt, seq, prev_hash: prev, step_index: 0, digest: ZERO, observed_height: 0, link: 0, ...e };
    ev.leaf = leafHash(encodeEvent(id, ev)).toString('hex');
    prev = ev.leaf;
    return ev;
  });
  const state = events.at(-1).state;
  return { id, spec, spec_digest: crypto.createHash('sha256').update(encodeSpec(spec)).digest('hex'), state, events };
}

test('a compensated life verifies', () => {
  assert.deepEqual(verifyEffect(seal(life())), { state: 'COMPENSATED', events: 5 });
});

test('gnokey qeval output is accepted as well as raw JSON', () => {
  const doc = seal(life());
  const wrapped = `height: 0\ndata: (${JSON.stringify(JSON.stringify(doc))} string)\n`;
  assert.equal(parseEffectJson(wrapped).id, 1);
  assert.equal(parseEffectJson(JSON.stringify(doc)).id, 1);
});

test('a tampered chain does not verify: gap, fork, reorder, edited field', () => {
  const gap = seal(life()); gap.events.splice(2, 1);
  assert.throws(() => verifyEffect(gap), /leaf|hash chain/);
  const fork = seal(life()); fork.events[1].digest = h('another receipt');
  assert.throws(() => verifyEffect(fork), /leaf does not match/);
  const reorder = seal(life()); [reorder.events[1], reorder.events[2]] = [reorder.events[2], reorder.events[1]];
  assert.throws(() => verifyEffect(reorder), /hash chain|lifecycle|step/);
  const swapped = seal(life()); swapped.spec.deadline_blocks = 30;
  assert.throws(() => verifyEffect(swapped), /spec_digest/);
});

test('an asserted outcome does not verify: a pre-state read-back before any fence is IN_DOUBT, not ABORTED', () => {
  const l = life();
  l.raw = [
    l.raw[0], l.raw[1],
    { kind: 'CLOSE', state: 'ABORTED', actor: 'g1exec', height: 12, digest: l.spec.pre_state, observed_height: 12 },
  ];
  assert.throws(() => verifyEffect(seal(l)), /seals ABORTED where the lifecycle gives IN_DOUBT/);
  l.raw[2] = { ...l.raw[2], state: 'IN_DOUBT' };
  l.raw.push({ kind: 'FENCE', state: 'IN_DOUBT', actor: 'g1cleanup', height: 13 });
  l.raw.push({ kind: 'CLOSE', state: 'ABORTED', actor: 'g1cleanup', height: 13, digest: l.spec.pre_state, observed_height: 13 });
  assert.deepEqual(verifyEffect(seal(l)), { state: 'ABORTED', events: 5 });
});

test('a step under another attempt, or after the deadline, does not verify', () => {
  const other = life(); other.raw[1] = { ...other.raw[1], attempt: 2 };
  assert.throws(() => verifyEffect(seal(other)), /another attempt/);
  const late = life(); late.raw[1] = { ...late.raw[1], height: 14 };
  assert.throws(() => verifyEffect(seal(late)), /not a step/);
});

test('an external effect whose downstream does not honour EffectLive never reads ABORTED, and its undo needs the approval', () => {
  const l = life();
  l.spec = { ...l.spec, read_back: 'AGENT', downstream_honours_live: false };
  const start = { ...l.raw[0], digest: crypto.createHash('sha256').update(encodeSpec(l.spec)).digest('hex') };
  const fenceThenClose = (state) => [
    start, l.raw[1],
    { kind: 'FENCE', state: 'STARTED', actor: 'g1exec', height: 12 },
    { kind: 'CLOSE', state, actor: 'g1exec', height: 13, digest: l.spec.pre_state, observed_height: 13 },
  ];
  assert.deepEqual(verifyEffect(seal({ ...l, raw: fenceThenClose('IN_DOUBT') })), { state: 'IN_DOUBT', events: 4 });
  assert.throws(() => verifyEffect(seal({ ...l, raw: fenceThenClose('ABORTED') })), /lifecycle gives IN_DOUBT/);
  const undo = (digest) => [start, l.raw[1], l.raw[2], { ...l.raw[3], ...(digest ? { digest } : {}) }];
  assert.throws(() => verifyEffect(seal({ ...l, raw: undo(null) })), /recorded approval/);
  assert.deepEqual(verifyEffect(seal({ ...l, raw: undo(h('approval 1')) })), { state: 'IN_DOUBT', events: 4 });
});

test('an IN_DOUBT effect is accepted only after a fence', () => {
  const l = life();
  const accept = { kind: 'ACCEPT', state: 'ACCEPTED', actor: 'g1cleanup', height: 16, digest: h('ok') };
  assert.throws(() => verifyEffect(seal({ ...l, raw: [l.raw[0], l.raw[1], l.raw[2], accept] })), /fenced first/);
  const fence = { kind: 'FENCE', state: 'IN_DOUBT', actor: 'g1cleanup', height: 15 };
  assert.deepEqual(verifyEffect(seal({ ...l, raw: [l.raw[0], l.raw[1], l.raw[2], fence, accept] })), { state: 'ACCEPTED', events: 5 });
});
