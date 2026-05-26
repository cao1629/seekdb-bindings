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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

rm -rf build
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DSEEKDB_BUILD_PYTHON=OFF
cmake --build build --target seekdb_driver seekdb_driver_static

find build -name "libseekdb_driver.*" -type f -exec ls -lh {} +
