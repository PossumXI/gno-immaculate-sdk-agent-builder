# Agent instructions

Persistent project context for coding agents (Cursor, Codex, Gemini, and Antigravity). Antigravity also loads `.agents/rules/project-context.md`.

## Names and URLs

- The project name is **Immaculate SDK Agent Builder**. It was renamed in November 2026 from **Gno Immaculate SDK Agent Builder**.
- The repository is [PossumXI/immaculate-sdk-agent-builder](https://github.com/PossumXI/immaculate-sdk-agent-builder), renamed from `PossumXI/gno-immaculate-sdk-agent-builder`. Always use the new name and URLs (`https://github.com/PossumXI/immaculate-sdk-agent-builder`, `https://possumxi.github.io/immaculate-sdk-agent-builder/web/`).
- The MCP server name is `immaculate-sdk-agent-mcp`.

## Companion project

- **Arobi Whisper** is the companion project. Its repository is [PossumXI/arobi-whisper](https://github.com/PossumXI/arobi-whisper), formerly `arobi-whisper-gno`.

## Gnome Tavern hackathon

Rules for the DoraHacks Gnome Tavern hackathon: https://dorahacks.io/hackathon/gnome-tavern/detail

- Project names must not use the `Gno` prefix or imply an official connection to Gno.land. A factual "built on Gno.land" is fine.
- The project must be deployed and working on Gno.land testnet at submission.
- The submission needs a public repo, a real realm or package, a README, a demo video, and a short description.
- Submissions close **Dec 17, 2026 8 PM ET** (**Dec 18, 2026 01:00 UTC**).
- There is no code freeze. The BUIDL stays editable until the deadline.
- The retention prize expects monthly releases.

## Do not rename technical identifiers

Keep these unchanged:

- `gno.land/...` package and realm paths
- `.gno` files
- `gno`, `gnokey`, and `gnodev` commands
- On-chain transaction hashes
- Release tag `v1.0.0-gnome-tavern`
- Hugging Face slugs (for example `TruLumecreator/immaculate-agent-gno-benchmarks`)

## Toolchain

- Current `gno` master uses `gnomod.toml` (`gno mod init` writes `module` plus `gno = "0.9"`).
- The root `gnowork.toml` enables `gno test ./...` and `gnodev .` so local packages and the realm resolve together.
