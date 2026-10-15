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
- One engine start per process. Opening the same directory again shares the
  running engine; another directory is rejected. After the last close, reopening
  requires a new process, and `seekdb_last_open_error` says so.
- A new database defaults to `memory_budget=1G`, `vector_memory_limit=128M`,
  `log_disk_size=2G` and `datafile_maxsize=20G`; parameters override them when the
  database is created. TCP is not available: a non-zero `port`, or a
  `mysql_port_mode` other than `disabled`, is rejected.
- Open returns once the engine runs and its Unix socket sends a MySQL handshake.
  The connection options carry `transport` `unix_socket`, the socket path in
  `unix_socket` (a short alias under the App's tmp directory, or under `/tmp` on
  the Simulator, when the real path is too long) and `user` `root`, with an empty
  password.
- The engine changes the process working directory, so use absolute paths. Open
  and close block; call them away from the UI thread. Close SQL clients before the
  last close, which stops the engine and joins its thread without a timeout.

## Tests

`swift/Tests/SeekDBTests` runs on a Simulator through `TEST_SIMULATOR`. On iOS,
`testInProcessEngineServesMySQLUntilItsOnlyClose` starts the engine, checks the
connection options, reads the MySQL handshake from the socket, closes the engine
and checks that a second start in the same process is refused with its
diagnostic. The framework itself is also tested by the probe below.

Validated on 2026-10-14 with macOS 27.0, Xcode 27.0, Swift 6.4 and the iOS 27.0
SDK, against Device and Simulator frameworks built from seekdb `e45afec49` (branch
`feature/ios-swift`, 8 exports): `ios/build.sh` packaged both, and the 14 Swift tests
passed on an iPhone 17 Simulator with iOS 27.0, the in-process engine test in 14.8
seconds. On the same Simulator, a separate Swift package that depends on this one by
local path opened the engine through the `SeekDB` product, read its connection
options and closed it. `ios/build.sh` rejected the framework header from before seekdb
`e49e515fe`, whose `SeekdbConnectionOptions` had four fields. The probe below, at
`378ea75`, passed two process runs against the Simulator framework (49/49 each,
`previous_runs` 30 to 31), recorded in `framework_evidence/in-process-20261015/`. The Device framework was built and verified but not run on a device.

## SeekDB.framework probe

`framework_probe/` tests the dynamic `SeekDB.framework` that oceanbase/seekdb builds
with `./build.sh release --ios [--simulator] --init --make` (before seekdb `9a35937b0`,
`build.iphone.sh release [--simulator] --target seekdb_ios_framework`). Since seekdb
`2b17e74e7` that framework only runs the engine, and since seekdb `e49e515fe` its
`seekdb.h` declares `seekdb_open`, `seekdb_last_open_error`, `seekdb_close` and
`seekdb_connection_options` as `lib/include/seekdb/seekdb.h` does; since seekdb
`e45afec49` it also exports four diagnostic functions of seekdb's in-process runtime,
`seekdb_in_process_get_state`, `seekdb_in_process_get_cleanup_status`,
`seekdb_in_process_get_cleanup_error` and `seekdb_in_process_get_build_id` (earlier
builds exported more runtime functions, named `seekdb_ios_*` before seekdb
`7242c9e6c`). Running SQL is the App's job, with
a MySQL-protocol client of its choice. The probe App links UIKit and its own
Connector/C, loads the three lifecycle functions and four runtime diagnostic functions
from the embedded framework with `dlopen`/`dlsym`, and runs SQL with Connector/C over the
Unix socket that `seekdb_connection_options` returns. The framework ships no header for
the runtime functions, so `framework_probe/app/seekdb_in_process.h` declares the four the
probe loads, matching `src/observer/in_process/seekdb_in_process.h` in seekdb. These
tests moved here from seekdb's `unittest/ios_build` on 2026-10-10.

`framework_probe/mariadb-connector-c/` is MariaDB Connector/C 3.4.8 (upstream revision
`46880b003653a000e9588bd73c8b1dd65088c686`), unmodified and licensed under
LGPL-2.1-or-later (`COPYING.LIB`). It moved here from seekdb's `deps/ios-driver` when the
framework stopped running SQL. `build_framework_probe.py` builds it as a static library
for the selected SDK with OpenSSL and zlib from `--deps-prefix`, the
`deps/ios/<sdk>/devel` directory that seekdb's iOS dependency build produces, and links
the probe against it.

The framework directory must contain the `build-manifest.json` that seekdb's
`verify_framework.py` writes during the framework build, with the matching platform.
It can live anywhere, but the probe build directory and the
stability output must be inside this repository. The probe records this repository's
`HEAD` as `SeekDBProbeSourceRevision`, and its reports set `framework_api` to
`in_process`. The validators also accept the earlier `lifecycle` reports, from before
seekdb `e45afec49` removed the test-hook query, and the reports without that field,
whose probe ran SQL through the framework's own C API.

```sh
python3 ios/framework_probe/build_framework_probe.py --simulator \
  --framework /path/to/seekdb/build_ios_simulator_release/framework/SeekDB.framework \
  --deps-prefix /path/to/seekdb/deps/ios/iphonesimulator/devel \
  --build build/ios/framework-probe
python3 ios/framework_probe/build_framework_probe.py \
  --framework /path/to/seekdb/build_ios_release/framework/SeekDB.framework \
  --deps-prefix /path/to/seekdb/deps/ios/iphoneos/devel \
  --build build/ios/framework-probe-device \
  --profile /path/to/existing.mobileprovision --identity "SIGNING IDENTITY"
```

Simulator builds are signed ad hoc. Device builds sign offline with an existing
explicit App profile and its identity; the script does not use an Xcode account.
Install and launch the App and keep it in the foreground. It writes
`Documents/framework-probe.json`; a passing report has `complete`, `passed` and
`worker_exit` true and `build_id` equal to the first 12
characters of the framework's source revision. Delete the report, launch the probe
again in a new process, and check that `previous_runs` grew by one. Then validate
the two reports:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl install SIMULATOR_UDID \
  build/ios/framework-probe/Release-iphonesimulator/SeekDBFrameworkProbe.app
xcrun simctl launch --terminate-running-process SIMULATOR_UDID org.seekdb.frameworkprobe
python3 ios/framework_probe/validate_framework_probe.py \
  --revision FULL_FRAMEWORK_REVISION run-1.json run-2.json
```

On a device, use `xcrun devicectl device install app` and
`xcrun devicectl device process launch` instead, and copy the report out of the
App data container.

`run_framework_stability.py` runs one foreground soak followed by fresh process
launches that check the committed counter survived. It needs a framework built from
a clean seekdb tree (`source_dirty` false). It fails on a sampling gap longer than
30 seconds or on more than 256 MiB of footprint growth after the warmup. On a device,
pass `--device UDID` with the device framework and App, and keep the phone unlocked.

```sh
python3 ios/framework_probe/run_framework_stability.py --simulator SIMULATOR_UDID \
  --app build/ios/framework-probe/Release-iphonesimulator/SeekDBFrameworkProbe.app \
  --framework /path/to/seekdb/build_ios_simulator_release/framework/SeekDB.framework \
  --output build/ios/stability/UNIQUE_RUN --duration 600 --runs 5
```

The validators have host tests that run against the recorded evidence:

```sh
python3 -B -m unittest discover -s ios/framework_probe
```

`framework_probe/framework_evidence` holds the 2026-10-07 runs recorded in seekdb:
two process runs and a 600-second stability run each on an iPhone 17 Pro with
iOS 27.0.1 and on an arm64 iOS 27.0 Simulator, for framework revision
`6f902fdab24c`. Those runs predate the lifecycle-only framework; the probe then ran
SQL through the framework's own C API. `framework_evidence/lifecycle-20261010/` holds
the Simulator runs of the lifecycle-only framework, and
`framework_evidence/in-process-20261015/` the Simulator runs after seekdb removed the
test-hook query.

Checked on 2026-10-10 with macOS 27.0, Xcode 27.0 and the iOS 27.0 SDK after the
move: the probe built here for the Simulator against a seekdb framework from
revision `72338ea757ca` (built with an uncommitted change, so its manifest records
`source_dirty` true), ran twice on an iPhone 17 Simulator with iOS 27.0, passed
77/77 assertions with `worker_exit` in both runs, advanced `previous_runs` from 3
to 4, and `validate_framework_probe.py` accepted the pair. The 14 host tests passed.
The stability runner and a device build were not run in that check.

Checked again the same day for the lifecycle-only framework, with the same tools and
Simulator: seekdb `2b17e74e7` built from a clean tree, and the probe from this
repository's `26fc9cc`. Two process runs passed 51/51 assertions with `worker_exit`,
`previous_runs` went from 9 to 10, and `validate_framework_probe.py` accepted the pair.
`run_framework_stability.py --duration 600 --runs 5` passed: 2927 transaction
iterations and 5781 concurrent reads over 181 connections in 600 seconds, no footprint
growth after the 60-second warmup, and the committed counter 1464 survived four more
launches. The warmup footprint, 241.6 MiB, is about 79 MiB higher than in the
2026-10-07 Simulator run; the cause was not investigated. The 19 host tests passed. No
device build or device run was done. Details are in
`framework_probe/framework_evidence/lifecycle-20261010/README.md`.

## Parked device test suite

`device_tests/` stores the engine-internal iOS device test suite that seekdb removed on
2026-10-10. It is a copy laid out like the seekdb repository and does not run from
here; [device_tests/README.md](device_tests/README.md) explains what it contains and how
to restore it in seekdb.
