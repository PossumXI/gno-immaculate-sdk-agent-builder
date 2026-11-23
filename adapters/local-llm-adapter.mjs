// Sovereign Local LLM & OpenAI-Compatible Governed Runner for Immaculate SDK Agent Builder.
//
// Connects any local llama-server (e.g. Inkling-2-Mini on local GPU), Ollama, or
// OpenAI-compatible endpoint directly through deterministic RFC 6962 EvidenceBundle
// recording so every prompt, tool call, memory recall, and completion produces a
// verifiable checkpoint ready to anchor on Gno.land (`gno.land/r/arobi/assurance`).

import { GnoshAssuranceSession } from './gnosh-adapter.mjs';
import { sha256Hex } from '../verifier/verify-evidence.mjs';

export class LocalLLMAssuranceRunner {
  constructor({
    baseUrl = 'http://127.0.0.1:8080/v1',
    model = 'local-model',
    apiKey = '',
    agentId = 'local-sovereign-familiar',
    principal,
    caller,
    sessionId = `llm-${Date.now()}`,
    allowedActions = ['chat_completion', 'tool_call'],
    maxBudgetUgnot = 5000,
    fetchImpl = globalThis.fetch,
  }) {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
    this.model = model;
    this.apiKey = apiKey;
    this.allowedActions = new Set(allowedActions);
    this.maxBudgetUgnot = maxBudgetUgnot;
    this.fetchImpl = fetchImpl;
    this.turnSeq = 0;
    this.session = new GnoshAssuranceSession({
      agentId,
      principal,
      caller: caller || principal,
      sessionId,
      policyDigest: sha256Hex(`local-llm-policy:${model}:${allowedActions.join(',')}:${maxBudgetUgnot}`),
    });
  }

  /**
   * Execute one governed inference turn against a local llama-server / OpenAI endpoint
   * and return `{ content, reasoning, timings, usage, bundle }`.
   */
  async complete({
    prompt,
    systemPrompt = 'You are a concise, precise autonomous assistant.',
    action = 'chat_completion',
    target = `llm:${this.model}`,
    budgetUgnot = 0,
    height = 1,
    maxTokens = 512,
    temperature = 0.2,
    memoryContextDigest = '',
  }) {
    this.turnSeq += 1;
    const frameId = `llm-turn-${this.turnSeq}`;

    // Fail-closed local policy pre-check before touching the model endpoint.
    if (!this.allowedActions.has(action) || budgetUgnot > this.maxBudgetUgnot) {
      const reason = !this.allowedActions.has(action) ? 'ACTION_NOT_ALLOWLISTED' : 'BUDGET_CAP_EXCEEDED';
      const bundle = this.session.recordFrameEvent({
        frameId,
        toolName: action,
        target,
        input: prompt,
        output: '',
        witness: reason,
        verdict: 'DENY',
        reasonCode: reason,
        outcome: 'REFUSED',
        budgetUgnot,
        spentUgnot: 0,
        height,
        extraContext: memoryContextDigest,
      });
      return { refused: true, reason, content: '', reasoning: '', bundle };
    }

    const headers = { 'content-type': 'application/json' };
    if (this.apiKey) headers.authorization = `Bearer ${this.apiKey}`;

    const res = await this.fetchImpl(`${this.baseUrl}/chat/completions`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        model: this.model,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: prompt },
        ],
        max_tokens: maxTokens,
        temperature,
      }),
    });
    if (!res.ok) {
      throw new Error(`local LLM endpoint error: HTTP ${res.status}`);
    }
    const payload = await res.json();
    const msg = payload?.choices?.[0]?.message || {};
    const content = String(msg.content || '');
    const reasoning = String(msg.reasoning_content || '');
    const timings = payload.timings || null;
    const usage = payload.usage || null;

    const witness = JSON.stringify({
      model: payload.model || this.model,
      finish: payload?.choices?.[0]?.finish_reason || 'stop',
      usage,
      tokPerSec: timings?.predicted_per_second ?? null,
    });

    const bundle = this.session.recordFrameEvent({
      frameId,
      toolName: action,
      target,
      input: prompt,
      output: content,
      witness,
      verdict: 'ALLOW',
      reasonCode: 'LOCAL_LLM_GOVERNED_ALLOW',
      outcome: 'EXECUTED',
      budgetUgnot,
      spentUgnot: budgetUgnot,
      height,
      extraContext: memoryContextDigest,
    });

    return { refused: false, content, reasoning, timings, usage, bundle };
  }

  buildAnchorCheckpointTx(anchorFeeUgnot = 1000) {
    return this.session.buildAnchorCheckpointTx(anchorFeeUgnot);
  }
}
