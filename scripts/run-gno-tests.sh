#!/usr/bin/env bash
# Runs real `gno lint` and `gno test -v` across signals, assurance, realm, and examples
# against a Gno v1.8.0 source tree (set GNO_SRC to your gnolang/gno checkout).
set -euo pipefail
export GOWORK=off

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GNO_SRC="${GNO_SRC:-/tmp/gno-v1.8.0}"
GNO_BIN="$GNO_SRC/build/gno"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) GNO_BIN="$GNO_BIN.exe" ;; esac

if [ ! -x "$GNO_BIN" ]; then
  echo "ERROR: gno binary not found at $GNO_BIN. Set GNO_SRC to your gnolang/gno checkout." >&2
  exit 2
fi

if command -v cygpath >/dev/null 2>&1; then
  export GNOROOT="$(cygpath -m "$GNO_SRC")"
else
  export GNOROOT="$GNO_SRC"
fi

for pkg in p/arobi/signals p/arobi/assurance r/arobi/assurance; do
  rm -rf "$GNO_SRC/examples/gno.land/$pkg"
  mkdir -p "$GNO_SRC/examples/gno.land/$(dirname "$pkg")"
  cp -r "$REPO/gno.land/$pkg" "$GNO_SRC/examples/gno.land/$pkg"
done
rm -rf "$GNO_SRC/examples/gno.land/p/arobi/examples"
mkdir -p "$GNO_SRC/examples/gno.land/p/arobi"
cp -r "$REPO/examples" "$GNO_SRC/examples/gno.land/p/arobi/examples"

for pkg in p/arobi/signals p/arobi/assurance r/arobi/assurance p/arobi/examples; do
  echo "=== gno lint + test -v gno.land/$pkg ==="
  ( cd "$GNO_SRC/examples/gno.land/$pkg" && "$GNO_BIN" lint . && "$GNO_BIN" test -v . )
done
echo "=== ALL AROBI ASSURANCE GNO TESTS PASSED ==="
