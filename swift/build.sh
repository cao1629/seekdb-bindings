#!/usr/bin/env bash
# Copyright (c) 2025 OceanBase.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
native=${SEEKDB_NATIVE_DIR:-"$root/build"}
action=${1:-build}
if [[ "$action" != build && "$action" != test ]]; then
    echo "Usage: SEEKDB_NATIVE_DIR=/directory/containing/libseekdb bash swift/build.sh [build|test]" >&2
    exit 2
fi
if [[ $# -gt 0 ]]; then shift; fi
case $(uname -s) in
    Darwin) library=libseekdb.dylib ;;
    Linux) library=libseekdb.so ;;
    *) echo "This build helper supports macOS and Linux hosts." >&2; exit 2 ;;
esac
if [[ ! -f "$native/$library" ]]; then
    echo "Missing $native/$library; build libseekdb first or set SEEKDB_NATIVE_DIR." >&2
    exit 2
fi
native=$(cd "$native" && pwd)
exec swift "$action" --package-path "$root" \
    -Xlinker -L -Xlinker "$native" \
    -Xlinker -rpath -Xlinker "$native" "$@"
