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
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
version=${1:?Usage: swift/release.sh VERSION RELEASE_CHECKOUT}
checkout=${2:?Usage: swift/release.sh VERSION RELEASE_CHECKOUT}
repository=${RELEASE_REPOSITORY:-cao1629/seekdb-swift}
framework="$here/build/SeekDBEngine.xcframework"
archive="$here/build/release/$version/SeekDBEngine.xcframework.zip"

for slice in ios-arm64 ios-arm64-simulator; do
  if [[ ! -d "$framework/$slice/SeekDB.framework" ]]; then
    echo "$framework has no $slice slice; package the device and Simulator frameworks with build.sh first" >&2
    exit 1
  fi
done
provenance=$(python3 - "$framework" <<'EOF'
import json
import sys

manifests = [json.load(open("%s/%s/SeekDB.framework/build-manifest.json" % (sys.argv[1], slice)))
             for slice in ("ios-arm64", "ios-arm64-simulator")]
revisions = sorted({manifest["source_revision"] for manifest in manifests})
if len(revisions) != 1:
    sys.exit("The device and Simulator slices come from different seekdb revisions: " + ", ".join(revisions))
print(revisions[0], int(any(manifest["source_dirty"] for manifest in manifests)))
EOF
)
read -r revision dirty <<<"$provenance"
if [[ $dirty == 1 ]]; then
  if [[ ${ALLOW_DIRTY:-0} != 1 ]]; then
    echo "SeekDB.framework was built from seekdb $revision with uncommitted changes; rebuild it from a clean tree, or set ALLOW_DIRTY=1 for a trial run" >&2
    exit 1
  fi
  echo "warning: SeekDB.framework was built from seekdb $revision with uncommitted changes; do not publish this archive" >&2
fi

rm -rf "$(dirname "$archive")"
mkdir -p "$(dirname "$archive")"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$framework" "$archive"
checksum=$(swift package compute-checksum "$archive")

mkdir -p "$checkout"
rm -rf "$checkout/Sources"
mkdir -p "$checkout/Sources/SeekDB" "$checkout/Sources/CSeekDB"
cp "$here"/Sources/SeekDB/*.swift "$checkout/Sources/SeekDB/"
cp "$here/Sources/CSeekDB/module.modulemap" "$here/Sources/CSeekDB/shim.h" "$checkout/Sources/CSeekDB/"
cp "$root/LICENSE" "$checkout/LICENSE"
printf '%s\n' .build/ .swiftpm/ > "$checkout/.gitignore"

fill() {
  sed -e "s|@VERSION@|$version|g" -e "s|@REPOSITORY@|$repository|g" \
    -e "s|@REVISION@|$revision|g" -e "s|@CHECKSUM@|$checksum|g"
}

fill > "$checkout/Package.swift" <<'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "seekdb-swift",
    platforms: [.iOS("18.0")],
    products: [.library(name: "SeekDB", targets: ["SeekDB"])],
    targets: [
        .systemLibrary(name: "CSeekDB"),
        .target(
            name: "SeekDB",
            dependencies: ["CSeekDB", "SeekDBEngine"],
            swiftSettings: [.enableExperimentalFeature("CheckImplementationOnly")]
        ),
        .binaryTarget(
            name: "SeekDBEngine",
            url: "https://github.com/@REPOSITORY@/releases/download/@VERSION@/SeekDBEngine.xcframework.zip",
            checksum: "@CHECKSUM@"
        ),
    ]
)
EOF

fill > "$checkout/README.md" <<'EOF'
# seekdb-swift

Swift package for [seekdb](https://github.com/oceanbase/seekdb) on iOS. It runs the
seekdb engine inside the application through `SeekDB.framework` and hands the
application a Unix socket, which it connects to with its own MySQL-protocol client.

Version @VERSION@ ships the engine built from seekdb `@REVISION@`.

## Add the package

In Xcode, choose File > Add Package Dependencies and enter
`https://github.com/@REPOSITORY@`. In a `Package.swift`:

```swift
.package(url: "https://github.com/@REPOSITORY@.git", from: "@VERSION@")
// in the target's dependencies:
.product(name: "SeekDB", package: "seekdb-swift")
```

## Use

```swift
import SeekDB

// The first open blocks until the engine accepts connections; call it away from the UI thread.
let db = try SeekDB.open("/absolute/path/to/database")
let options = try db.connectionOptions()
// Connect a MySQL client to options.unix_socket as options.user, with an empty password.
try db.close()
```

- iOS 18 or newer.
- The engine keeps running until the process exits; close only releases the handle.
  The same directory can be opened again, another directory is rejected.
- Only the Unix socket is available, not TCP.
- The engine sets the process working directory to its data directory, so use
  absolute paths.

This repository is generated by `swift/release.sh` in
[seekdb-bindings](https://github.com/cao1629/seekdb-bindings); change the sources there.
EOF

cat <<EOF
Prepared $repository $version from seekdb $revision in $checkout
  archive:  $archive
  checksum: $checksum
Review the checkout, then publish:
  git -C $checkout add -A
  git -C $checkout commit -m "seekdb-swift $version"
  git -C $checkout tag $version
  git -C $checkout push origin HEAD $version
  gh release create $version $archive --repo $repository --title $version --notes "Engine built from seekdb $revision."
EOF
