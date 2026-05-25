#!/usr/bin/env bash
set -euo pipefail

if [ -z "${SEEKDB_BIN:-}" ]; then
    echo "error: SEEKDB_BIN must be set to the seekdb binary path" >&2
    exit 1
fi
if [ ! -x "$SEEKDB_BIN" ]; then
    echo "error: SEEKDB_BIN ($SEEKDB_BIN) is not executable" >&2
    exit 1
fi

case "$(uname -s)" in
    Linux)  PLATFORM=linux ;;
    Darwin) PLATFORM=macos ;;
    *) echo "error: unsupported OS $(uname -s)" >&2; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

rm -rf build python/build wheelhouse

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

python -m cibuildwheel --platform "$PLATFORM" --output-dir wheelhouse ./python

ls -lh wheelhouse/
