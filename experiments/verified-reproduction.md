## 6. Verified Reproduction — `scripts/reproduce.sh`

Independent re-run of every CI stage on **Windows 11** (MSYS/git-bash, Go
1.27.3, Node 24.18.0) against **Gno v1.8.0 built from source**, plus a container
run (`Dockerfile`, Linux containers) and the project's Ubuntu CI jobs.

| Stage | Command | Result |
| --- | --- | --- |
| Node modules | `node --test verifier adapters mcp` | **9/9 pass** |
| Gno lint + unit tests | `bash scripts/run-gno-tests.sh` | **42/42 pass**, lint clean, 4/4 packages `ok` |
| Experiments E1–E14 | `node experiments/run_experiments.mjs` | exit `0`, **27/27 verdicts expected** |
| Golden root | `GOLDEN_ROOT` | `0063b523…` **matches bit-for-bit** |
| Container | `docker build` + `docker run` | **all four stages pass** |

Spot checks behind those totals: E1 fixed-point fidelity within `1e-5`; E12 RFC
6962 consistency proofs `2080/2080` valid and `2080/2080` tampered rejected; E14
Gno↔Node golden digest parity with `500/500` adversarial receipt mutations
rejected.

### Cross-platform defects surfaced by this run

- The `gno` installer rejects MSYS (`unsupported OS: MSYS_NT-10.0-…`), so
  git-bash users must build gno by hand.
- `git` and `go` reject MSYS `/c/...` paths; `GNO_SRC` must be normalized to
  `C:/…`.
- `run_experiments.mjs` forwards `GNO_SRC` to gno as `GNOROOT`; an MSYS path makes
  gno fall back to `%APPDATA%\gno` and every package fails `[setup failed]`.
- A Windows checkout carries CRLF, which bash on Linux rejects
  (`set -euo pipefail\r`); the container normalizes `scripts/*.sh`.

> **Scope note:** these are the project's own tests and benchmarks, so a green run
> demonstrates reproducibility and internal consistency on the host above — not
> independent validation of the scientific claims. Measured gas counters drift by
> ~`480` units between runs; treat gas figures as indicative rather than exact.
