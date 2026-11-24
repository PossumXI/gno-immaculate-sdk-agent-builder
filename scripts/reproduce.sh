#!/usr/bin/env bash
# Reproduce every check CI runs, in one command.
#
#   bash scripts/reproduce.sh
#
# Stage 1  node --test          verifier, adapters, MCP stdio server
# Stage 2  gno lint + tests     signals, assurance, realm, examples
# Stage 3  experiments E1-E14   plus a verdict check against results.json
#
# Environment:
#   GNO_SRC     path to a Gno v1.8.0 source checkout (default: ./.gno-src)
#   GNO_BIN     explicit path to an already-built gno binary
#   GNO_VERSION tag to build when no binary is found (default: v1.8.0)
#   SKIP_BUILD  set to 1 to fail instead of cloning/building gno
#
# Exits non-zero if any stage fails.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

GNO_VERSION="${GNO_VERSION:-v1.8.0}"
GNO_SRC="${GNO_SRC:-${TMPDIR:-/tmp}/gno-v1.8.0}"
RESULTS=()

log() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok()  { RESULTS+=("PASS  $1"); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad() { RESULTS+=("FAIL  $1"); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }

# Native (C:/...) form of a path, for binaries that do not understand MSYS paths.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}

# git, go and gno are native binaries: hand them a C:/... path, never an MSYS
# one. Downstream scripts (run-gno-tests.sh, run_experiments.mjs) forward
# GNO_SRC/GNOROOT to gno, so it has to be native everywhere.
GNO_SRC="$(native_path "$GNO_SRC")"

find_gno() {
  if [ -n "${GNO_BIN:-}" ] && [ -x "${GNO_BIN}" ]; then
    printf '%s' "${GNO_BIN}"
    return 0
  fi
  local cand probe
  for cand in "$GNO_SRC/build/gno.exe" "$GNO_SRC/build/gno" "$(command -v gno 2>/dev/null || true)"; do
    [ -n "$cand" ] || continue
    probe="$cand"
    if command -v cygpath >/dev/null 2>&1; then
      probe="$(cygpath -u "$cand" 2>/dev/null || printf '%s' "$cand")"
    fi
    if [ -x "$probe" ]; then
      printf '%s' "$cand"
      return 0
    fi
  done
  return 1
}

build_gno() {
  if [ "${SKIP_BUILD:-0}" = "1" ]; then
    echo "no gno binary found and SKIP_BUILD=1" >&2
    return 1
  fi
  command -v git >/dev/null 2>&1 || { echo "git is required to fetch Gno ${GNO_VERSION}" >&2; return 1; }
  command -v go  >/dev/null 2>&1 || { echo "go is required to build Gno ${GNO_VERSION}" >&2; return 1; }

  local exe=gno
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*) exe=gno.exe ;;
  esac

  # git and go are native binaries: hand them a C:/... path, never an MSYS one.
  local src_native
  src_native="$(native_path "$GNO_SRC")"

  echo "Building Gno ${GNO_VERSION} into ${GNO_SRC} ..."
  rm -rf "$GNO_SRC"
  git clone --depth 1 --branch "$GNO_VERSION" https://github.com/gnolang/gno.git "$src_native" || return 1
  mkdir -p "$GNO_SRC/build"
  ( cd "$GNO_SRC" && GOWORK=off go build -o "build/${exe}" ./gnovm/cmd/gno ) || return 1
}

printf 'Immaculate SDK Agent Builder — full reproduction\n'
printf 'repo: %s\n' "$REPO"

GNO_FOUND="$(find_gno || true)"
if [ -z "$GNO_FOUND" ]; then
  build_gno || true
  GNO_FOUND="$(find_gno || true)"
fi
if [ -z "$GNO_FOUND" ]; then
  bad "locate or build gno ${GNO_VERSION}"
else
  export GNO_BIN="$GNO_FOUND"
  export GNO_SRC
  if [ -d "$GNO_SRC" ]; then
    export GNOROOT="$(native_path "$GNO_SRC")"
  fi
  ok "gno ${GNO_VERSION} at ${GNO_FOUND}"
fi

log "Stage 1/3  Node module tests"
if node --test verifier/verify-evidence.test.mjs \
             adapters/adapters.test.mjs \
             mcp/immaculate-mcp-server.test.mjs; then
  ok "node --test (verifier, adapters, MCP server)"
else
  bad "node --test (verifier, adapters, MCP server)"
fi

log "Stage 2/3  Gno lint + unit tests"
if bash scripts/run-gno-tests.sh; then
  ok "gno lint + tests (signals, assurance, realm, examples)"
else
  bad "gno lint + tests (signals, assurance, realm, examples)"
fi

log "Stage 3/3  Pre-registered experiments E1-E14"
if node experiments/run_experiments.mjs && node experiments/check-verdicts.mjs; then
  ok "experiments E1-E14 + verdict check"
else
  bad "experiments E1-E14 + verdict check"
fi

log "Summary"
for r in "${RESULTS[@]}"; do printf '  %s\n' "$r"; done

FAILS=0
for r in "${RESULTS[@]}"; do
  case "$r" in FAIL*) FAILS=$((FAILS + 1)) ;; esac
done

if [ "$FAILS" -gt 0 ]; then
  printf '\n%s stage(s) FAILED\n' "$FAILS"
  exit 1
fi
printf '\nAll stages passed.\n'
