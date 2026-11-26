# Team Roles & Contributors — Immaculate SDK Agent Builder

Built for the **Gnome Tavern Hackathon | Gno.land** (submission deadline: **December 18, 2026 at 01:00 UTC**).

| Contributor | GitHub Status | Assigned Role | Primary Ownership |
| --- | --- | --- | --- |
| `@PossumXI` | Active (`admin`) | Project Lead & Core Architect | Core `p/arobi/signals`, `p/arobi/assurance` (Agents, Familiars, `MemoryVault`, RFC 6962), `r/arobi/assurance`, `r/arobi/effects`, Onyx (`onyx-1`) deployment, scientific benchmarks |
| `@iShowLinux` | Active (`write`) | Systems, Linux & Cross-Harness Integration Engineer | One-command Linux/Docker verification (`scripts/reproduce.sh`, `Dockerfile`, PR `#8`), verified Windows+Ubuntu reproduction (`#19`), real `gnosh.ai` capture replay & Windows CI (`#20`), and cross-shell testing (Issue `#1`) |
| `@ShadowPlague21` | Active (`write`) | Performance, Trading Strategy & Optimization Lead | DeFi treasury & adaptive signal guard stress-testing (`examples/examples_test.gno`, `r/arobi/effects`), GnoVM gas & local GPU latency profiling (`bench/gas/`), and demo polish (Issue `#7`) |
| `@canderson777` | Invited (`write`) | Security QA, Frontend UX & Demo Producer | Interactive web verifier/playground QA (`web/index.html`), Adena wallet UX testing, and demo walkthrough production (Issue `#3`) |

## How Tasks Are Tracked
Every contributor's active milestone and acceptance checklist is tracked in GitHub Issues on this repository. Once a PR merges and closes its issue, task completion is verified via green Ubuntu & Windows CI (`Verify` workflow).
