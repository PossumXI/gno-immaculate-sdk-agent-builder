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
  `https://onyx.testnets.gno.land/r/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/assurance/v2`
  *(Live on `onyx-1` since 2026-11-27, enabled by Onyx's package approver. The effect-lifecycle realm is
  `https://onyx.testnets.gno.land/r/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/effects/v2`.)*
- **Realm or package path:**
  `gno.land/r/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/assurance/v2`
  *(Also live: the realm `gno.land/r/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/effects/v2`, and the library packages `gno.land/p/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/signals/v2` and
  `gno.land/p/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/assurance/v2`.)*
- **Is this a new project, or one started before Gnome Tavern?**
  > Brand-new SDK built on Gno.land: fixed-point signal assurance library, Familiar and Governed MemoryVault runtime, stdio MCP server, `gnosh.ai`/`Ullumii`/local-GPU adapters, interactive browser verifier, and pre-registered scientific benchmark suite (E1–E5 + Live Benchmarks) built from scratch for the Gnome Tavern Hackathon.
- **On-chain proof on `onyx-1`.** Check it with `node scripts/check-onyx-status.mjs --namespace g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak`:
  | Path | Kind | Deployed at height | Open |
  | --- | --- | --- | --- |
  | `gno.land/p/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/signals/v2` | package | 1,450,918 | [gnoweb](https://onyx.testnets.gno.land/p/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/signals/v2) |
  | `gno.land/p/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/assurance/v2` | package | 1,450,922 | [gnoweb](https://onyx.testnets.gno.land/p/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/assurance/v2) |
  | `gno.land/r/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/assurance/v2` | realm | 1,450,924 | [gnoweb](https://onyx.testnets.gno.land/r/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/assurance/v2) |
  | `gno.land/r/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/effects/v2` | realm | 1,450,926 | [gnoweb](https://onyx.testnets.gno.land/r/g1jkstuy23a8e44jvdjajc5gjjry9vwevmkvmdak/effects/v2) |

  All four are `ACTIVE`: their files are queryable (`vm/qfile`) and gnoweb renders the realms.

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
