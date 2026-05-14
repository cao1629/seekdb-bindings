#!/usr/bin/env bash
#
# Full pipeline: build libseekdb_client + seekdb_cli, build the pylibseekdb
# extension into python/build/, then drive cibuildwheel to produce a manylinux
# wheel in wheelhouse/.
#
# Requires:
#   - SEEKDB_BIN pointing at the seekdb server binary (the top-level cmake
#     copies it into build/).
#   - Docker daemon running (cibuildwheel uses it). If the current shell
#     isn't yet in the docker group, `sg docker` is used to fork one that is.
#   - cibuildwheel installed for python3.11:
#       python3.11 -m pip install --user cibuildwheel
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

: "${SEEKDB_BIN:?SEEKDB_BIN must point at the seekdb server binary}"
[[ -x "$SEEKDB_BIN" ]] || { echo "SEEKDB_BIN not executable: $SEEKDB_BIN" >&2; exit 1; }

# 1-3: top-level build — produces libseekdb_client.so + seekdb_cli, copies
# the seekdb binary from SEEKDB_BIN into build/.
mkdir -p "$REPO/build"
cd "$REPO/build"
cmake -DSEEKDB_BIN="$SEEKDB_BIN" ..
cmake --build . -j

# 4-6: python/ build — runs python/CMakeLists.txt, which copies
# libseekdb_client.so and seekdb into python/build/ so they sit next to
# pylibseekdb.so for in-tree (PYTHONPATH=python/build) testing.
mkdir -p "$REPO/python/build"
cd "$REPO/python/build"
cmake ..
cmake --build . -j

# 7-8: cibuildwheel — builds the wheel inside the manylinux_2_28 container,
# bundling libseekdb_client.so, the seekdb binary, and libaio.so.1.
cd "$REPO"
sg docker -c "python3.11 -m cibuildwheel --platform linux --output-dir wheelhouse ./python"
