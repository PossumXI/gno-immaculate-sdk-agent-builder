# Live Public Benchmarks — Immaculate Agent SDK Builder & Arobi Whisper

**Generated:** `2026-11-23T05:31:21.329Z` | **Reproduce:** `node experiments/run_live_benchmarks.mjs`

All measurements below were collected against **real running systems** — live Gno.land Onyx Testnet (`onyx-1`) RPC, real Node.js `node:crypto` X25519+ChaCha20-Poly1305, live stdio MCP JSON-RPC 2.0 server, and a live sovereign local GPU serving `Inkling-2-Mini-Uncensored` (`llama.cpp b12648`).

---

## 1. Live Gno.land Onyx Testnet (`onyx-1`) RPC & Real Deployment Gas

- **RPC:** `https://rpc.onyx.testnets.gno.land:443` | **Chain ID:** `onyx-1` | **Observed Block Height:** `1344098`
- **RPC `/status` Latency:** p50 `54.639 ms`, p95 `250.478 ms` | **`abci_query` (`vm/qinertpaths`):** `43.6 ms`
- **Verified On-Chain Submissions:** `3` pure packages + `2` stateful realms

| Package / Realm Path | Block Height | Measured Gas Used | On-Chain Tx Hash |
| --- | ---: | ---: | --- |
| `gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/signals` | `1343642` | `31,981,544` | `QLBPtPOpBUapHouk+hNHIWjkWarDH383MZhhbmlOOtA=` |
| `gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/assurance` | `1343646` | `123,670,779` | `+k7hjislNZ1B2uC0bnk6MihvsoqaeczUtp8OwVDdkK8=` |
| `gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/assurance` | `1343648` | `48,678,627` | `DzU5Dt7AyZbFb8Glx79GbJ+ZWXs3s+G4n4906FoDqsc=` |
| `gno.land/p/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` | `1343650` | `17,978,068` | `Y8yxq2g2dcj2q3PUrJDzHEk6TeyEq2mEDfXvn6yW0ow=` |
| `gno.land/r/g1jdc6h96he7wf7xfycu6u7wqhv5j762qtxu5k5t/whisper` | `1343652` | `45,410,622` | `/EB7ITw57NRhnrB9rIS5gi6hp73k9yRcHKwH6LWwOcc=` |

---

## 2. Live Whisper Agent Bus Crypto Throughput (X25519 + HKDF-SHA256 + ChaCha20-Poly1305)

200 real ephemeral-key round-trip seal + open + SHA-256 commitment verifications per payload tier:

| Payload Tier | Seal p50 (ms) | Open p50 (ms) | Round-Trip Throughput | Integrity Verified |
| --- | ---: | ---: | ---: | ---: |
| 256 B (Agent Handoff) | `0.371` | `0.442` | **1,209 ops/s** | 100% |
| 4 KiB (Free Tier Cap) | `0.369` | `0.476` | **1,221 ops/s** | 100% |
| 16 KiB (Pro Tier Cap) | `0.397` | `0.5` | **1,104 ops/s** | 100% |

---

## 3. Live MCP Stdio Server Latency (`mcp/immaculate-mcp-server.mjs`, JSON-RPC 2.0)

25 sequential end-to-end JSON-RPC 2.0 tool calls over real OS stdio pipes:

| MCP Tool | p50 Latency (ms) | p95 Latency (ms) | Runs |
| --- | ---: | ---: | ---: |
| `governed_execute` | `1.284` | `2.349` | 25 |
| `familiar_quarantine` | `0.22` | `0.934` | 25 |
| `familiar_recall` | `0.232` | `0.378` | 25 |
| `verify_evidence` | `0.357` | `0.681` | 25 |

---

## 4. Live Sovereign Local GPU Governed Inference (`LocalLLMAssuranceRunner`)

- **Model:** `AtomicChat/Inkling-2-Mini-Uncensored-AD-IQ2_M.gguf (26.4B MoE / 3.4B active, looped core)`
- **Hardware:** Local NVIDIA GeForce MX150 (2 GiB VRAM, CUDA 12.4) + 4-core CPU MoE Hybrid (llama.cpp b12648)
- **Session RFC 6962 Root:** `5e471056783ccec5d25f70c57b5a64e3404649acca907fd9b96ccb8d9222ff61` (`10` leaves, 100% verified offline)

| Task | Governance Verdict | Wall Latency (ms) | Prompt tok/s | Gen tok/s | Tokens | GPU Compute Saved | RFC 6962 Proof |
| --- | --- | ---: | ---: | ---: | ---: | :---: | :---: |
| Arithmetic Reasoning | `ALLOW (EXECUTED)` | `84412.8` | `5.54` | `2.18` | 175 | — | **PASS** |
| Pure Go/Gno Codegen | `ALLOW (EXECUTED)` | `123704.3` | `5.22` | `2.14` | 256 | — | **PASS** |
| RFC 6962 Verification Q&A | `ALLOW (EXECUTED)` | `109142.9` | `5.63` | `2.14` | 224 | — | **PASS** |
| Policy Refusal: Budget Overspend | `DENY (BUDGET_CAP_EXCEEDED)` | `1.2` | `0` | `0` | 0 | **100% (0 ms GPU)** | **PASS** |
| Policy Refusal: Disallowed Action | `DENY (ACTION_NOT_ALLOWLISTED)` | `1.8` | `0` | `0` | 0 | **100% (0 ms GPU)** | **PASS** |

> **Takeaway:** Fail-closed policy & budget refusals complete in **`< 2 ms`** before ever touching the GPU (`100%` inference compute saved) while still emitting a cryptographically verifiable RFC 6962 refusal receipt. Allowed turns add **`< 0.01%`** governance overhead on top of local LLM inference.
