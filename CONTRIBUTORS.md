# Team Roles & Contributors — Immaculate SDK Agent Builder

Built for the **Gnome Tavern Hackathon | Gno.land** (submission deadline: **December 18, 2026 at 01:00 UTC**).

| Contributor | GitHub Status | Assigned Role | Primary Ownership |
| --- | --- | --- | --- |
| `@PossumXI` | Active (`admin`) | Project Lead & Core Architect | Core `p/arobi/signals`, `p/arobi/assurance` (Agents, Familiars, `MemoryVault`, RFC 6962), `r/arobi/assurance`, Onyx (`onyx-1`) deployment, scientific benchmarks |
| `@iShowLinux` | Active (`write`) | Systems, Linux & Cross-Harness Integration Engineer | Native Linux/Docker reproduction of Gno v1.8.0 & E1–E5 benchmarks, stdio MCP server (`mcp/immaculate-mcp-server.mjs`) verification, `gnosh.ai` / `Ullumii` / Whisper cross-shell testing |
| `@JonDevOps` | Invited (`write` — pending acceptance) | DevOps, CI/CD & Onyx Testnet Release Engineer | Onyx (`onyx-1`) `enablepkg` approver activation via `#gnome-tavern-hackathon`, post-activation live realm smoke tests, GitHub Actions CI hardening |
| `@canderson777` | Invited (`write` — pending acceptance) | Security QA, Frontend UX & Demo Producer | Interactive web verifier/playground QA, Adena wallet UX testing, recording the required 2–3 minute DoraHacks demo video |
| `@ShadowPlague21` | Invited (`write` — pending acceptance) | Performance, Trading Strategy & Optimization Lead | DeFi treasury & adaptive signal guard stress-testing (`examples/examples.gno`), GnoVM gas & local GPU latency optimization, demo polish (Issue `#7`) |

## How Tasks Are Tracked
Every contributor's active milestone and acceptance checklist is tracked in GitHub Issues on this repository. Once a PR merges and closes its issue, task completion is verified via green Ubuntu CI (`Verify` workflow).
