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
out=${IOS_BUILD_DIR:-"$root/build/ios"}
deployment_target=${IOS_DEPLOYMENT_TARGET:-18.0}
cflags=(-std=c11 -Wall -Wextra -Werror -O2 -g -I"$root/lib/include")

build_static_library() {
  local sdk=$1 target=$2 platform=$3
  local dir="$out/native/$sdk"
  local actual
  mkdir -p "$dir"
  xcrun --sdk "$sdk" clang "${cflags[@]}" -target "$target" \
    -c "$root/lib/src/ios/seekdb_ios_adapter.c" -o "$dir/seekdb_ios_adapter.o"
  actual=$(xcrun vtool -show-build "$dir/seekdb_ios_adapter.o" | awk '$1 == "platform" { print $2 }')
  if [[ "$actual" != "$platform" ]]; then
    echo "$dir/seekdb_ios_adapter.o targets platform '$actual', expected $platform" >&2
    return 1
  fi
  rm -f "$dir/libseekdb.a"
  xcrun --sdk "$sdk" libtool -static -o "$dir/libseekdb.a" "$dir/seekdb_ios_adapter.o"
}

build_static_library iphoneos "arm64-apple-ios$deployment_target" IOS
build_static_library iphonesimulator "arm64-apple-ios$deployment_target-simulator" IOSSIMULATOR
mkdir -p "$out/package"
rm -rf "$out/package/libseekdb.xcframework"
xcodebuild -create-xcframework \
  -library "$out/native/iphoneos/libseekdb.a" -headers "$root/lib/include" \
  -library "$out/native/iphonesimulator/libseekdb.a" -headers "$root/lib/include" \
  -output "$out/package/libseekdb.xcframework"

if [[ ${RUN_HOST_TEST:-0} == 1 ]]; then
  mkdir -p "$out/test"
  cc -std=c11 -Wall -Wextra -Werror -DSEEKDB_IOS_HOST_TEST=1 \
    -I"$root/lib/include" -I"$root/lib/src/ios" \
    "$root/lib/src/ios/seekdb_ios_adapter.c" "$root/ios/test/test_ios_lifecycle.c" \
    -pthread -o "$out/test/test_ios_lifecycle"
  (cd "$root" && "$out/test/test_ios_lifecycle")
fi

if [[ ${BUILD_SWIFT_PACKAGE:-0} == 1 ]]; then
  for destination in "generic/platform=iOS" "generic/platform=iOS Simulator"; do
    (cd "$root" && xcodebuild -scheme seekdb-bindings -destination "$destination" \
      -derivedDataPath "$out/xcode" CODE_SIGNING_ALLOWED=NO build)
  done
fi
