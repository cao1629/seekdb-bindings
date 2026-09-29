# README

Swift bindings for opening a local SeekDB instance, obtaining its connection
information, and releasing the instance. The API follows the Java bindings.
It has no third-party Swift dependencies and does not include a SQL client,
construct connection URLs, execute queries, or decode result sets. Applications
choose and configure their own MySQL-protocol client.

## Package layout

The root `Package.swift` exposes the `SeekDB` library. Implementation, native
adaptation, and tests live under `swift/`; the C declarations come from the
repository's existing `lib/include/seekdb/seekdb.h`.

```swift
// In a consuming package's Package.swift:
dependencies: [
    .package(path: "../seekdb-bindings")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "SeekDB", package: "seekdb-bindings")
    ])
]
```

The root manifest also provides the entry point for Git-URL package consumption
once a revision containing this implementation is published. A native engine is
still required, just as the Java JAR requires its matching native components.
The package does not download engines or change process search paths.

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

## iOS

The iOS adapter runs the engine inside the application on a dedicated 8 MiB-stack
thread. It does not build or spawn the desktop `libseekdb` implementation. Link
the app with matching iOS engine archives exporting `seekdb_ios_run`,
`seekdb_ios_request_stop`, and `seekdb_ios_get_state`.

The private runtime declarations in `Sources/CSeekDB/Runtime/seekdb_ios.h` match
`cao1629/seekdb`, branch `codex/iphone-arm64-port`, revision
`60ab0316de669395cb6ddc3988854087ca26b0f9`. Use the engine's complete static link
dependencies, including its C++ runtime and Apple frameworks; the observer archive
alone is insufficient. The existing engine build's `app/engine-link.rsp` records
that link closure in compiler-driver argument format. Consumers must pass those
arguments to their app's link step; the Swift package contains no engine binaries.
When reusing that probe response file, omit `libseekdb_ios_sql_probe.a`, which
belongs to the engine's test app rather than the lifecycle runtime.

Current runtime constraints are explicit:

- iOS 18 or newer, with matching device or ARM64 Simulator archives. A Simulator
  archive cannot be used for a device build.
- One engine invocation and one owning handle per application process. A second
  open is rejected, including after a successful close. Restart the process to
  reopen the same persistent directory.
- Only an empty parameter list is supported. The linked runtime uses a 1 GiB
  logical memory budget, a 128 MiB vector limit, a 2 GiB log allocation, CPU count
  2, two SQL network threads, and disabled TCP. Unsupported settings are rejected.
- Open waits for the runtime to report Running and create its Unix socket, with
  a 180-second startup deadline. This is not a successful SQL-query check; clients
  must handle their own authentication and database readiness errors.
- The endpoint is the relative path `run/sql.sock`, avoiding the Unix socket
  address limit for long sandbox paths. The runtime changes the process working
  directory to the database directory. The app must not change it while the
  engine or its clients are active. Use absolute paths for other app file work.
- Close requests shutdown and joins the engine thread. It can block without a
  shutdown timeout. Close clients first and perform engine close off the UI thread.
  A failed startup or shutdown may leave process-global engine state; do not retry
  engine startup in that process.

The existing C query functions are not implemented by this iOS lifecycle adapter
and are not part of the Swift public API.

## Verification

`Tests/SeekDBTests` covers public validation, native diagnostics, copied UTF-8
values, closed-handle access, idempotence, failed-close ownership, deinitialization,
and concurrent options/close. The desktop smoke test calls the real C API's
parameter validation without starting an engine.

`Tests/native/test_ios_lifecycle.c` substitutes only the engine runtime to test the
iOS adapter's real thread/socket/lifecycle behavior on the host. It covers startup
failure, timeout, missing socket, shutdown failure, and a real Unix socket whose
absolute path exceeds the platform limit. Run it with:

```sh
mkdir -p build/swift-native-tests
cc -std=c11 -Wall -Wextra -Werror -DSEEKDB_SWIFT_TEST_IOS=1 \
  swift/Sources/CSeekDB/seekdb_ios_adapter.c \
  swift/Tests/native/test_ios_lifecycle.c -pthread \
  -o build/swift-native-tests/test_ios_lifecycle
build/swift-native-tests/test_ios_lifecycle
```

Validated results and platform boundaries are recorded in [verification.md](verification.md).
