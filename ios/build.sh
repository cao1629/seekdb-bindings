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
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
seekdb=${SEEKDB_DIR:?Set SEEKDB_DIR to an oceanbase/seekdb checkout built with ./build.sh release --ios [--simulator] --make}
out="$root/build/ios"
output="$out/SeekDBEngine.xcframework"

check_header() {
  python3 - "$1" "$root/lib/include/seekdb/seekdb.h" <<'EOF'
import re
import sys


def lifecycle_api(path):
    text = re.sub(r"/\*.*?\*/", "", open(path).read(), flags=re.S)
    parts = [re.search(r"typedef struct \{[^}]*\} SeekdbConnectionOptions;", text)]
    for name in ("seekdb_open", "seekdb_last_open_error", "seekdb_close", "seekdb_connection_options"):
        parts.append(re.search(r"^[^\n;]*\b%s\([^;]*\);" % name, text, re.M))
    return [part and " ".join(part.group(0).split()) for part in parts]


framework, bindings = sys.argv[1:]
if lifecycle_api(framework) != lifecycle_api(bindings):
    sys.exit("%s does not declare the lifecycle API of %s" % (framework, bindings))
EOF
}

frameworks=()
destinations=()
for slice in "build_ios_release:IOS:iOS" "build_ios_simulator_release:IOSSIMULATOR:iOS Simulator"; do
  IFS=: read -r directory expected destination <<<"$slice"
  framework="$seekdb/$directory/framework/SeekDB.framework"
  if [[ ! -d "$framework" ]]; then
    continue
  fi
  platform=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["platform"])' \
    "$framework/build-manifest.json")
  if [[ "$platform" != "$expected" ]]; then
    echo "$framework is built for $platform, expected $expected" >&2
    exit 1
  fi
  check_header "$framework/Headers/seekdb.h"
  frameworks+=(-framework "$framework")
  destinations+=("generic/platform=$destination")
done
if [[ ${#frameworks[@]} -eq 0 ]]; then
  echo "No SeekDB.framework in $seekdb; run ./build.sh release --ios [--simulator] --make there first" >&2
  exit 1
fi
mkdir -p "$out"
rm -rf "$output"
xcodebuild -create-xcframework "${frameworks[@]}" -output "$output"

if [[ ${BUILD_SWIFT_PACKAGE:-0} == 1 ]]; then
  for destination in "${destinations[@]}"; do
    (cd "$root" && xcodebuild -scheme seekdb-bindings -destination "$destination" \
      -derivedDataPath "$out/xcode" CODE_SIGNING_ALLOWED=NO build)
  done
fi

if [[ -n ${TEST_SIMULATOR:-} ]]; then
  (cd "$root" && xcodebuild -scheme seekdb-bindings -destination "platform=iOS Simulator,id=$TEST_SIMULATOR" \
    -derivedDataPath "$out/xcode" test)
fi
