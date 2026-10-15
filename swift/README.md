# SeekDB Swift bindings

`Sources/SeekDB` contains the platform-neutral API (`SeekDB`, `ConnectionOptions`,
`SeekDBError`). `NativeAPI.swift` is the common bridge to the C API in
`lib/include/seekdb/seekdb.h`, which `Package.swift` exposes to Swift as
the `CSeekDB` module; it has no iOS-specific code. The API follows the Java
bindings. It has no third-party Swift dependencies and does not include a SQL
client, construct connection URLs, execute queries, or decode result sets.
Applications choose and configure their own MySQL-protocol client.

## Package layout

This directory is a SwiftPM package: `Package.swift` exposes the `SeekDB` library
from `Sources/SeekDB`, with tests in `Tests/SeekDBTests`. `CSeekDB` is a module map
over the repository's `lib/include/seekdb/seekdb.h`. On macOS and Linux the
`SeekDB` target links the existing `libseekdb` shared library; on iOS it links
oceanbase/seekdb's `SeekDB.framework` through the repository's
`build/ios/SeekDBEngine.xcframework`, which `ios/build.sh` creates.

`NativeAPI.swift` imports `CSeekDB` with `@_implementationOnly`. With a plain or
`internal import`, every module that imports `SeekDB` must also find the `CSeekDB`
module map, because clients of a module built without library evolution load its
imports, and compiling without it fails with "missing required module 'CSeekDB'".
The `SeekDB` target enables the experimental feature `CheckImplementationOnly`, which
makes storing a `CSeekDB` type in a property a compile error rather than a warning:
clients would compute such a type's layout without seeing `CSeekDB`.

```swift
// In a consuming package's Package.swift:
dependencies: [
    .package(path: "../seekdb-bindings/swift")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "SeekDB", package: "swift")
    ])
]
```

SwiftPM names a package added by path after its directory, hence `package: "swift"`.
It reads a Git-URL dependency's `Package.swift` only from the repository root, so
this package is used by path; Git-URL consumption will need a separate repository
with its own root manifest. A native engine is still required, just as the Java
JAR requires its matching native components. The package does not download
engines or change process search paths.

## API

```swift
import SeekDB

// Run this work away from the UI thread: open and close are synchronous.
let db = try SeekDB.open("/absolute/writable/persistent/database")
defer { try? db.close() }

let options = try db.connectionOptions()
// Configure your chosen client using options.transport and its endpoint fields.
// Execute SQL and close all client connections before closing db.

try db.close()
```

`ConnectionOptions` is a copied, immutable, `Sendable` value with fields matching
the C and Java APIs: `transport`, `port`, `host`, `unix_socket`, `named_pipe`, and
`user`. Unused strings remain `nil`; local endpoints have port zero. The snapshot
does not extend the native handle's lifetime. Do not open client connections from
saved options after the owning instance closes.

`SeekDB.open(path, parameters: ["memory_budget", "2G", "log_disk_size", "4G"])`
passes alternating key/value strings to the desktop native API. The wrapper
rejects odd-length lists, empty names, and embedded NUL bytes. Other values are
validated by the native implementation. Native open errors retain their return
code and same-thread diagnostic in `SeekDBError`.

Options and close operations on a handle are serialized. A successful close is
idempotent, and options requested afterward throw `SeekDBError.closed`. Failed
close retains the handle. `deinit` attempts best-effort cleanup, but explicit close
is required to observe failures and control which thread performs shutdown.

## macOS and Linux

The wrapper links the existing `libseekdb` shared library. The library manages a
separate server process and discovers the `seekdb` executable beside itself.
Closing the instance releases its handle; it does not promise immediate server
termination. Existing native configuration and multi-client semantics apply.

Build the native library first; building only the Swift wrapper does not require
a running server. For example, on macOS with CMake and OpenSSL available:

```sh
git submodule update --init deps/mariadb-connector-c
cmake -S . -B build/swift-native \
  -DSEEKDB_BUILD_PYTHON=OFF -DBUILD_TESTING=OFF \
  -DWITH_EXTERNAL_ZLIB=YES -DSEEKDB_BIN=/absolute/path/to/seekdb
cmake --build build/swift-native --target seekdb --parallel 3
SEEKDB_NATIVE_DIR="$PWD/build/swift-native" bash swift/build.sh build
SEEKDB_NATIVE_DIR="$PWD/build/swift-native" bash swift/build.sh test
```

`SEEKDB_NATIVE_DIR` belongs to this build helper; it supplies linker search and
runtime search paths. Other build systems must configure those paths themselves
and deploy the matching native library and engine. To run wrapper unit tests
without an engine binary, configure CMake with `-DSEEKDB_BIN=` instead. Linux uses
the same native library interface but has not been runtime-validated in this work.

With Swift 6.4 (Xcode 27), the default build system does not pass this helper's
`-Xlinker` search and runtime paths to the test bundle, so the test link cannot
find libseekdb. Append `--build-system native`, for example
`SEEKDB_NATIVE_DIR="$PWD/build/swift-native" bash swift/build.sh test --build-system native`.

## Tests

`Tests/SeekDBTests` covers public validation, native diagnostics, copied UTF-8
values, closed-handle access, idempotence, failed-close ownership, deinitialization,
and concurrent options/close. The desktop smoke test calls the real C API's
parameter validation without starting an engine. On iOS one test starts the
in-process engine; see the [iOS instructions](../ios/README.md).

Validated on 2026-09-29 with Apple Silicon macOS 15.5, Xcode 16.4 and Swift 6.1.2:
the fourteen Swift tests passed against a macOS `libseekdb.dylib` built from this
repository with CMake, with Python and C++ test targets disabled, external zlib and
no engine binary, including a real C error-path call with Unicode parameter values;
no test server was required. Rechecked on 2026-10-08 with Xcode 27.0 and Swift 6.4:
the same fourteen tests passed with `--build-system native` before and after the iOS
files moved out of `swift/`. Rechecked on 2026-10-14 after `CSeekDB` became a module map
over the public header: the fourteen tests passed again on macOS 27.0 with Xcode 27.0's
Swift 6.4 and `--build-system native`. Rechecked on 2026-10-15 after `Package.swift`
moved into `swift/`: the fourteen tests passed again the same way.

## iOS

On iOS the same API runs the engine inside the application instead of a separate
process, through seekdb's `SeekDB.framework`. Its packaging, runtime constraints
and tests are in `ios/`. See [iOS instructions](../ios/README.md).
