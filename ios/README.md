# iOS

An iOS app cannot start the separate SeekDB process that libseekdb launches on
desktop systems and Android. On iOS the Swift package links `SeekDB.framework`,
the dynamic framework that oceanbase/seekdb builds with
`./build.sh release --ios [--simulator] --init --make`. It runs the engine inside
the application on a dedicated 8 MiB-stack thread and implements `seekdb_open`,
`seekdb_last_open_error`, `seekdb_close` and `seekdb_connection_options` with the
declarations in `lib/include/seekdb/seekdb.h`. The C query functions are not
available on iOS. The Swift API is platform-neutral and lives in `swift/`; the iOS
packaging, runtime constraints and tests are here.

## Build

Requires macOS with full Xcode and the iOS SDKs. The scripts use
`/Applications/Xcode.app/Contents/Developer` unless `DEVELOPER_DIR` is set. Build
the framework in a seekdb checkout, then package it here:

```sh
cd /path/to/seekdb
./build.sh release --ios --init --make -j8               # device
./build.sh release --ios --simulator --init --make -j8   # Simulator
cd /path/to/seekdb-bindings
SEEKDB_DIR=/path/to/seekdb bash ios/build.sh
```

`ios/build.sh` puts each `SeekDB.framework` it finds in `SEEKDB_DIR` (device,
Simulator or both) into `build/ios/SeekDBEngine.xcframework`. It first checks each
framework's platform and that its `seekdb.h` declares the same
`SeekdbConnectionOptions` and lifecycle functions as `lib/include/seekdb/seekdb.h`.
When that XCFramework exists, the root `Package.swift` adds it as the binary target
`SeekDBEngine` and links it into the `SeekDB` product on iOS only; macOS and Linux
keep linking libseekdb. `BUILD_SWIFT_PACKAGE=1` also builds the package with
`xcodebuild` for each packaged platform, and `TEST_SIMULATOR=<simulator id>` runs
the Swift tests on that Simulator.

## Use

Swift apps depend on the root package's `SeekDB` product, as shown in the
[Swift bindings](../swift/README.md); Xcode embeds and signs `SeekDB.framework`
with the app. Apps that call the C API directly can embed the framework and
include its `Headers/seekdb.h`.

- iOS 18 or newer. Device and Simulator frameworks are separate slices.
- The first open starts the engine, which keeps running until the process exits;
  close only releases the handle. Opening the same directory again reuses the
  running engine, also after every handle has been closed. Another directory is
  rejected, and so is any open after the engine failed to start;
  `seekdb_last_open_error` says why.
- A new database defaults to `memory_budget=1G`, `vector_memory_limit=128M`,
  `log_disk_size=2G` and `datafile_maxsize=20G`; parameters override them when the
  database is created. TCP is not available: a non-zero `port`, or a
  `mysql_port_mode` other than `disabled`, is rejected.
- Open returns once the engine runs and its Unix socket sends a MySQL handshake.
  The connection options carry `transport` `unix_socket`, the socket path in
  `unix_socket` (a short alias under the App's tmp directory, or under `/tmp` on
  the Simulator, when the real path is too long) and `user` `root`, with an empty
  password.
- The engine sets the process working directory to its data directory and leaves
  it there, so use absolute paths. The first open blocks until the engine accepts
  connections; call it away from the UI thread.

## Tests

`swift/Tests/SeekDBTests` runs on a Simulator through `TEST_SIMULATOR`. On iOS,
`testInProcessEngineKeepsServingAfterClose` starts the engine, checks the
connection options, reads the MySQL handshake from the socket, closes the handle,
opens the same directory again and reads the handshake once more, and checks that
another directory is refused with its diagnostic. The example App below runs
`SELECT 1` through the package in a real App.

Validated on 2026-10-15 with macOS 27.0, Xcode 27.0, Swift 6.4 and the iOS 27.0
SDK, against Device and Simulator frameworks built from seekdb `9786f15d9` (branch
`feature/ios-swift`, 4 exports): `ios/build.sh` packaged both, and the 14 Swift tests
passed on an iPhone 17 Simulator with iOS 27.0, the in-process engine test in 1.0
second (about 14 seconds before, when close still stopped the engine). On the same
Simulator, a separate Swift package that depends on this one by local path opened the
engine through the `SeekDB` product, read its connection options and closed it, and
neither test process crashed when it exited with the engine still running. The
example App below returned `{"select_1":1}` on a fresh database and again in a new
process on the existing one. `ios/build.sh` rejected the framework header from before
seekdb `e49e515fe`, whose `SeekdbConnectionOptions` had four fields. The Device
framework was built and verified but not run on a device.

## Example App

`example/` is a SwiftUI App that uses this package the way an application would. On
launch it opens a database in its `Documents/seekdb` directory with `SeekDB.open`,
connects to the Unix socket from `connectionOptions()` with
[MySQLNIO](https://github.com/vapor/mysql-nio), a pure-Swift MySQL client, runs
`SELECT 1`, closes the handle and writes `{"select_1":1}` to `Documents/select1.json`,
or `{"error": ...}` when a step fails. MySQLNIO always assumes the
`CLIENT_DEPRECATE_EOF` capability, which seekdb does not announce, so its own
`simpleQuery` returns no rows from seekdb; `example/Sources/TextQuery.swift` is a
`MySQLCommand` that reads a text result set either way.

The Xcode project is generated from `example/project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). It depends on this repository by
local path and on MySQLNIO and SwiftNIO from GitHub, and it signs ad hoc for the
Simulator; to run on a device, open the generated `example/SeekDBExample.xcodeproj`
in Xcode and choose a team. `example/run.sh` generates the project, builds the App for
a Simulator into `build/ios/example`, installs and launches it, and waits up to 300
seconds for `select1.json`; it fails unless the result is 1. Package the framework
with `ios/build.sh` first.

```sh
brew install xcodegen
bash ios/example/run.sh SIMULATOR_UDID
```

The example replaces `framework_probe/`, an Objective-C++ App that loaded the
framework's C functions with `dlopen` and ran SQL through MariaDB Connector/C, with
its validators, stability runner and recorded runs; git history keeps it.
