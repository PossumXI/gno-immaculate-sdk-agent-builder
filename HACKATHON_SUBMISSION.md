# Gnome Tavern Hackathon Submission Pack — **Immaculate SDK Agent Builder**

*(100% compliant with official Gnome Tavern Hackathon | Gno.land rules: no `"Gno"` prefix in Build Name, public MIT repository, genuine Gno packages + stateful realm submitted on `onyx-1`, verified scientific & live public benchmarks, zero private wallet/proprietary disclosures.)*

---

## Copy-Paste DoraHacks `Create a new Build` Fields

- **Name of your Build:** `Immaculate SDK Agent Builder`
- **Brief description of this Build:**
  > Consensus-safe autonomous agent and Familiar SDK in pure fixed-point code, built on Gno.land — out-of-the-box RFC 6962 cryptographic evidence, Hampel-CUSUM drift circuit breakers, poison-resistant Hybrid RRF MemoryVault, attenuated object-capabilities, stdio MCP server, and `Ullumii` / `gnosh.ai` / sovereign local GPU adapters.
- **Tags:** `Go`, `Smart Contracts`, `AI`, `Layer 1`, `dApps`, `DeFi`
- **GitHub Repo:** `https://github.com/PossumXI/immaculate-sdk-agent-builder`
- **Demo Video (1080p MP4, 2m 45s):** `https://github.com/PossumXI/immaculate-sdk-agent-builder/releases/download/v1.0.0-gnome-tavern/Immaculate_Agent_SDK_Builder_Demo_1080p.mp4`
- **Live Web Playground:** `https://possumxi.github.io/immaculate-sdk-agent-builder/web/`
- **Public Benchmarks (Hugging Face & PageSpeed):** `https://huggingface.co/spaces/TruLumecreator/immaculate-agent-gno-benchmarks` · [PageSpeed 100/100/100](https://pagespeed.web.dev/analysis/https-possumxi-github-io-immaculate-sdk-agent-builder-web/s7l82mro32?form_factor=desktop)
- **Website:** `https://aura-genesis.org`

---

## Copy-Paste DoraHacks `Submit Build` Modal Fields

- **Gno.land testnet deployment link (`gnoweb` URL):**
  `https://onyx.testnets.gno.land/r/<namespace>/assurance`
  *(Note: Submitted on-chain to `onyx-1` and verifiable via `gnokey query vm/qinertpaths` while awaiting Onyx `enablepkg` approver activation. The live path used a deployer-address namespace and is omitted from this public file.)*
- **Realm or package path:**
  `gno.land/r/<namespace>/assurance`
  *(Pure library packages: `gno.land/p/<namespace>/signals` and `gno.land/p/<namespace>/assurance`. For code review, use the in-repo paths `gno.land/p/arobi/signals`, `gno.land/p/arobi/assurance`, and `gno.land/r/arobi/assurance`.)*
- **Is this a new project, or one started before Gnome Tavern?**
  > Brand-new SDK built on Gno.land: fixed-point signal assurance library, Familiar and Governed MemoryVault runtime, stdio MCP server, `gnosh.ai`/`Ullumii`/local-GPU adapters, interactive browser verifier, and pre-registered scientific benchmark suite (E1–E5 + Live Benchmarks) built from scratch for the Gnome Tavern Hackathon.
- **On-Chain Onyx (`onyx-1`) Proof Table (verified via `node scripts/check-onyx-status.mjs`):**
  | Package / Realm | Status on `onyx-1` |
  | --- | --- |
  | `gno.land/p/<namespace>/signals` | **`ACTIVE` on `onyx-1`** (queryable live via `gnokey query vm/qfile`) |
  | `gno.land/p/<namespace>/assurance` | **`SUBMITTED_INERT`** in `vm/qinertpaths`, awaiting Onyx approver `enablepkg` |
  | `gno.land/r/<namespace>/assurance` | **`SUBMITTED_INERT`** in `vm/qinertpaths`, awaiting Onyx approver `enablepkg` |
  | `gno.land/p|r/<namespace>/*/v2` (`signals/v2`, `assurance/v2`, `effects/v2`) | Staged via `scripts/deploy-onyx.sh` with flat-gas AVL storage (`17.8×` gas cut) & checked-not-asserted `r/arobi/effects` |

  Transaction hashes, deploy block heights, gas used, and the deployer bech32 namespace are omitted from this public file because they identify the deployer account. Share the live paths with judges privately if they need to confirm the on-chain submission.

---

## Alignment with Judging Rubric

| Criterion (Weight) | What Judges Can Verify Immediately |
| --- | --- |
| **Technical Quality (40%)** | Zero-float fixed-point Gno (`Scale = 1,000,000`), `gno lint` = 0, `42/42` real Gno v1.8.0 unit tests + `6/6` `r/arobi/effects` acceptance txtars, `20/20` Node tests (offline verifiers, real `gnosh.ai` stream capture, `Ullumii`/Local-LLM adapters, live stdio MCP server), green Ubuntu + Windows CI. |
| **User Appeal (20%)** | Fluent `NewAgentBuilder` & `BuildFamiliar` DX, `gnoweb` explorer (`/`, `/demo`, `/familiar`, `/benchmarks`), plus interactive browser verifier & MemoryVault playground (`web/index.html`). |
| **Creativity (20%)** | Checked-not-asserted `r/arobi/effects` partial-effect lifecycle, `17.8×` flat-gas AVL storage, Wildberger rational quadrance (`-48.7%` gas), `AR(1)` prewhitened `Hampel-CUSUM`, Overlap-Weighted Hybrid RRF `MemoryVault` (`100%` Top-1 / `0%` poison), and sovereign local GPU governance. |
| **Docs & Demo (20%)** | `README.md`, `WALKTHROUGH.md` (with scope & attribution boundaries + 3/6-month retention plan), `CONTRIBUTORS.md`, `experiments/PROTOCOL.md`, `experiments/RESULTS.md` (`E1–E14`, `27/27` verdicts), and `experiments/LIVE_BENCHMARKS.md`. |

---

## 2–3 Minute Demo Video Shot List
1. **0:00–0:25 (Problem):** Why standard agents log mutable text and static spend caps miss stealth drift & sleeper memory poisoning.
2. **0:25–1:00 (Real Gno v1.8.0 + E1–E5 Benchmarks):** Run `bash scripts/run-gno-tests.sh` and show `experiments/RESULTS.md` + `experiments/LIVE_BENCHMARKS.md` (100% Top-1 / 0% poison MemoryVault, 25× spike FPR drop, 0.9299 L1 Geometric Median, live sovereign local GPU inference).
3. **1:00–1:45 (Interactive Browser Playground & MCP Server):** Open `web/index.html`, verify the Gno v1.8.0 Golden RFC 6962 proof, click **Tamper 1 Byte** to show instant forgery rejection, test Spherical Quarantine + Hybrid RRF recall, and run `node --test mcp/immaculate-mcp-server.test.mjs`.
4. **1:45–2:30 (On-Chain Onyx-1 & Cross-Harness Future):** Query live `onyx-1` RPC in `web/index.html` (or live `gnoweb` after `enablepkg`), show `gnosh.ai` / `Ullumii` / Whisper Agent Bus interop, and close with team credits.
