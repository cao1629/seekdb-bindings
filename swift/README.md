# SeekDB Swift bindings

`Sources/SeekDB` contains the API (`SeekDB`, `ConnectionOptions`, `SeekDBError`).
It runs seekdb in process: `NativeAPI.swift` calls the lifecycle functions of
oceanbase/seekdb's `SeekDB.framework` through the `CSeekDB` module. The API follows
the Java bindings. It has no third-party Swift dependencies and does not include a
SQL client, construct connection URLs, execute queries, or decode result sets.
Applications choose and configure their own MySQL-protocol client.

## Package layout

This directory is a SwiftPM package: `Package.swift` exposes the `SeekDB` library
from `Sources/SeekDB`, with tests in `Tests/SeekDBTests`. The engine is seekdb's
`SeekDB.framework`, which `ios/build.sh` packages as the repository's
`build/ios/SeekDBEngine.xcframework`; when that exists, the package adds it as the
binary target `SeekDBEngine`. It holds iOS slices only for now; packaging, runtime
constraints and tests are in the [iOS instructions](../ios/README.md).

`CSeekDB` is a module map whose `shim.h` includes the framework's own
`<SeekDB/seekdb.h>`. That header comes from seekdb's
`src/observer/in_process/seekdb.h` and declares `seekdb_open`,
`seekdb_last_open_error`, `seekdb_close` and `seekdb_connection_options`. The
repository's `lib/include/seekdb/seekdb.h` belongs to the out-of-process `libseekdb`
and is not used here.

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
passes alternating key/value strings to `seekdb_open`. The wrapper rejects
odd-length lists, empty names, and embedded NUL bytes. Other values are validated
by the native implementation. Native open errors retain their return code and
same-thread diagnostic in `SeekDBError`.

Options and close operations on a handle are serialized. A successful close is
idempotent, and options requested afterward throw `SeekDBError.closed`. Failed
close retains the handle. `deinit` attempts best-effort cleanup, but explicit close
is required to observe failures.

## Tests

`Tests/SeekDBTests` covers public validation, native diagnostics, copied UTF-8
values, closed-handle access, idempotence, failed-close ownership, deinitialization
and concurrent options/close, and one test starts the in-process engine. They run
on an iOS Simulator through `TEST_SIMULATOR`; see the
[iOS instructions](../ios/README.md).
