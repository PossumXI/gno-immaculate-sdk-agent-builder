#!/usr/bin/env bash
# Runs real `gno lint` and `gno test -v` across signals, assurance, realm, and examples.
# Supports BOTH current github.com/gnolang/gno master (root gnowork.toml workspace)
# and Gno v1.8.0 source checkouts (GNO_SRC/examples/gno.land resolution).
set -euo pipefail
export GOWORK=off

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GNO_SRC="${GNO_SRC:-/tmp/gno-v1.8.0}"

if [ -n "${GNO_BIN:-}" ]; then
  :
elif [ -x "$GNO_SRC/build/gno" ]; then
  GNO_BIN="$GNO_SRC/build/gno"
elif [ -x "$GNO_SRC/build/gno.exe" ]; then
  GNO_BIN="$GNO_SRC/build/gno.exe"
elif command -v gno >/dev/null 2>&1; then
  GNO_BIN="$(command -v gno)"
else
  echo "ERROR: gno binary not found. Install github.com/gnolang/gno master or set GNO_SRC / GNO_BIN." >&2
  exit 2
fi

if [ -d "$GNO_SRC" ]; then
  if command -v cygpath >/dev/null 2>&1; then
    export GNOROOT="$(cygpath -m "$GNO_SRC")"
  else
    export GNOROOT="$GNO_SRC"
  fi
fi

# Current gno master supports root gnowork.toml directly when no v1.8.0 examples tree is required.
if [ -f "$REPO/gnowork.toml" ] && { [ ! -d "$GNO_SRC/examples/gno.land/p/nt" ] || grep -q "findWorkspaceRootDir" "$GNO_SRC/gnovm/pkg/packages/load.go" 2>/dev/null; }; then
  echo "=== gno test -v (workspace $REPO) ==="
  if ( cd "$REPO" && "$GNO_BIN" test -v ./gno.land/p/arobi/signals ./gno.land/p/arobi/assurance ./gno.land/r/arobi/assurance ./gno.land/r/arobi/effects ./examples ); then
    echo "=== ALL AROBI ASSURANCE GNO TESTS PASSED ==="
    exit 0
  fi
  if [ ! -d "$GNO_SRC/examples/gno.land" ]; then
    exit 1
  fi
  echo "=== falling back to Gno v1.8.0 examples workspace ==="
fi

for pkg in p/arobi/signals p/arobi/assurance r/arobi/assurance r/arobi/effects; do
  rm -rf "$GNO_SRC/examples/gno.land/$pkg"
  mkdir -p "$GNO_SRC/examples/gno.land/$(dirname "$pkg")"
  cp -r "$REPO/gno.land/$pkg" "$GNO_SRC/examples/gno.land/$pkg"
done
rm -rf "$GNO_SRC/examples/gno.land/p/arobi/examples"
mkdir -p "$GNO_SRC/examples/gno.land/p/arobi"
cp -r "$REPO/examples" "$GNO_SRC/examples/gno.land/p/arobi/examples"

for pkg in p/arobi/signals p/arobi/assurance r/arobi/assurance r/arobi/effects p/arobi/examples; do
  echo "=== gno lint + test -v gno.land/$pkg ==="
  ( cd "$GNO_SRC/examples/gno.land/$pkg" && "$GNO_BIN" lint . && "$GNO_BIN" test -v . )
done
echo "=== ALL AROBI ASSURANCE GNO TESTS PASSED ==="
