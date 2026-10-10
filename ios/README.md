# iOS in-process engine for Swift

An iOS app cannot start the separate SeekDB process that libseekdb launches on
desktop systems and Android. On iOS, libseekdb is instead
`lib/src/ios/seekdb_ios_adapter.c`: `seekdb_open` runs the engine inside the
application on a dedicated 8 MiB-stack thread, and `seekdb_last_open_error`,
`seekdb_connection_options` and `seekdb_close` keep the C API in
`lib/include/seekdb/seekdb.h`. The C query functions are not implemented on iOS.
The adapter reaches the engine through the private runtime declarations in
`lib/src/ios/seekdb_ios.h`, which match `cao1629/seekdb`, branch
`codex/iphone-arm64-port`, revision `60ab0316de669395cb6ddc3988854087ca26b0f9`.
The Swift API is platform-neutral and lives in `swift/`; only the iOS build,
packaging, runtime constraints and tests are here.

## Build

Requires macOS with full Xcode and the iOS SDKs. The script uses
`/Applications/Xcode.app/Contents/Developer` unless `DEVELOPER_DIR` is set, so the
global `xcode-select` setting does not need to change. The engine archives are not
built or downloaded by the script; build them from the seekdb branch above with its
`build.iphone.sh`.

```sh
bash ios/build.sh
RUN_HOST_TEST=1 BUILD_SWIFT_PACKAGE=1 bash ios/build.sh
```

Outputs are in `build/ios`. `package/libseekdb.xcframework` holds static libseekdb
archives for ARM64 devices and the ARM64 Simulator, each with the `lib/include`
headers. Every adapter object is checked with `vtool` for the IOS or IOSSIMULATOR
platform before it is archived. The minimum system version defaults to 18.0; set
`IOS_DEPLOYMENT_TARGET` to change it and `IOS_BUILD_DIR` to move the output.
`RUN_HOST_TEST=1` builds and runs the host lifecycle test described below.
`BUILD_SWIFT_PACKAGE=1` builds the root Swift package for generic iOS devices and
Simulators with `xcodebuild`, without code signing.

## Use

Swift apps depend on the root package's `SeekDB` product, as shown in the
[Swift bindings](../swift/README.md). On iOS, SwiftPM compiles `lib/src/ios` into
the `CSeekDB` module, so the desktop `libseekdb` is neither built nor linked. Apps
that call the C API directly can link `libseekdb.xcframework` instead.

Either way the app must also link the engine: its archives, their complete static
link dependencies, the C++ runtime and Apple frameworks. The observer archive alone
is insufficient. The engine build's `app/engine-link.rsp` records that link closure
in compiler-driver argument format; pass those arguments to the app's link step.
When reusing that probe response file, omit `libseekdb_ios_sql_probe.a`, which
belongs to the engine's test app rather than the lifecycle runtime. Neither the
Swift package nor the XCFramework contains engine binaries.

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
- Open and close block, so call them away from the UI thread. Close requests
  shutdown and joins the engine thread, with no shutdown timeout; disconnect all
  SQL clients first. On a close error the handle is retained. A failed startup or
  shutdown may leave process-global engine state; do not retry engine startup in
  that process, and expect that an engine failure may require terminating the
  application.

## Tests and limitations

`test/test_ios_lifecycle.c` substitutes only the engine runtime, so the adapter's
real thread, socket and lifecycle code runs on the macOS host without engine
archives. Each case runs in a separate process because the engine is single-use.
It covers invalid arguments and thread-local diagnostics, startup failure, startup
timeout, a missing socket, shutdown failure, and a real Unix socket whose absolute
path exceeds the platform limit. `RUN_HOST_TEST=1 bash ios/build.sh` compiles it
with `SEEKDB_IOS_HOST_TEST` and runs it from the repository root; its fixtures are
created under `build/ios-host-test-fixtures`.

Validated on 2026-09-29 with Apple Silicon macOS 15.5, Xcode 16.4, Swift 6.1.2 and
the iPhoneSimulator 18.5 SDK:

- The six host lifecycle tests passed normally and under AddressSanitizer and
  UndefinedBehaviorSanitizer. ARM64 iOS Simulator C compilation passed
  `-Wall -Wextra -Werror`.
- A Swift UIKit consumer linked the package and existing ARM64 Simulator engine
  archives, installed, and ran on an iPhone 16 Pro / iOS 18.6 Simulator. Opening a
  new persistent directory, returning Unix socket connection options, closing the
  engine, repeated close, and rejecting connection-options access after close all
  passed. The app recorded `Stopped` after engine shutdown.
- The consumer passed ten SQL checks through the returned socket: text
  expressions, schema creation, prepared insert/read/update/delete, text typed
  reads, rollback, commit, and a persistent run counter. Values included Unicode,
  binary bytes, NULL, and the maximum unsigned 64-bit integer.
- After clean shutdown and application-process restart, the same directory's
  counter advanced from 0 to 1 and then from 1 to 2. The final consumer binary
  (iOS Simulator, minimum iOS 18.0, SDK 18.5) passed the same checks again and
  advanced the counter to 3.
- The external SQL client required a local compatibility patch for legacy MySQL
  metadata EOF packets and capability negotiation; its ten packet regression tests
  passed. The client, its patch and the consumer source remain outside this
  repository, so this does not establish compatibility with an unmodified
  third-party Swift SQL driver.

Rechecked on 2026-10-08 with macOS 27.0, Xcode 27.0 and the iOS 27.0 SDKs after the
adapter moved to `lib/src/ios` and the tests to `ios/`:
`RUN_HOST_TEST=1 BUILD_SWIFT_PACKAGE=1 bash ios/build.sh` built and checked both
static libraries and the XCFramework, passed the six host lifecycle tests, and built
the Swift package for generic iOS devices and Simulators. No engine was linked or
run in this recheck.

Physical iPhones and long-running stability are not verified. Repeated lifecycle
cycles within one process are unsupported by the current iOS runtime.

## SeekDB.framework probe

`framework_probe/` tests the dynamic `SeekDB.framework` that oceanbase/seekdb builds
with `build.iphone.sh release [--simulator] --target seekdb_ios_framework`, not the
adapter in `lib/src/ios`. That framework packages the engine with the desktop C API
in `seekdb.h` and exports seven iOS lifecycle functions. The probe App links only
UIKit, loads the embedded framework with `dlopen`/`dlsym`, and runs SQL through the
framework's Connector/C driver over the engine's Unix socket. The framework ships no
header for the iOS functions, so `framework_probe/app/seekdb_ios.h` declares the
five the probe loads, matching `src/observer/ios/seekdb_ios.h` in seekdb. These tests
moved here from seekdb's `unittest/ios_build` on 2026-10-10.

The framework directory must contain the `build-manifest.json` that seekdb's
`verify_framework.py` writes during the framework build, with the matching platform
and test hooks disabled. It can live anywhere, but the probe build directory and the
stability output must be inside this repository. The probe records this repository's
`HEAD` as `SeekDBProbeSourceRevision`.

```sh
python3 ios/framework_probe/build_framework_probe.py --simulator \
  --framework /path/to/seekdb/build_ios_sim_arm64/framework/SeekDB.framework \
  --build build/ios/framework-probe
python3 ios/framework_probe/build_framework_probe.py \
  --framework /path/to/seekdb/build_ios_arm64/framework/SeekDB.framework \
  --build build/ios/framework-probe-device \
  --profile /path/to/existing.mobileprovision --identity "SIGNING IDENTITY"
```

Simulator builds are signed ad hoc. Device builds sign offline with an existing
explicit App profile and its identity; the script does not use an Xcode account.
Install and launch the App and keep it in the foreground. It writes
`Documents/framework-probe.json`; a passing report has `complete`, `passed` and
`worker_exit` true, `hook_mode` disabled, and `build_id` equal to the first 12
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
  --framework /path/to/seekdb/build_ios_sim_arm64/framework/SeekDB.framework \
  --output build/ios/stability/UNIQUE_RUN --duration 600 --runs 5
```

The validators have host tests that run against the recorded evidence:

```sh
python3 -B -m unittest discover -s ios/framework_probe
```

`framework_probe/framework_evidence` holds the 2026-10-07 runs recorded in seekdb:
two process runs and a 600-second stability run each on an iPhone 17 Pro with
iOS 27.0.1 and on an arm64 iOS 27.0 Simulator, for framework revision
`6f902fdab24c`.

Checked on 2026-10-10 with macOS 27.0, Xcode 27.0 and the iOS 27.0 SDK after the
move: the probe built here for the Simulator against a seekdb framework from
revision `72338ea757ca` (built with an uncommitted change, so its manifest records
`source_dirty` true), ran twice on an iPhone 17 Simulator with iOS 27.0, passed
77/77 assertions with `worker_exit` in both runs, advanced `previous_runs` from 3
to 4, and `validate_framework_probe.py` accepted the pair. The 14 host tests passed.
The stability runner and a device build were not run after the move.

## Parked device test suite

`device_tests/` stores the engine-internal iOS device test suite that seekdb removed on
2026-10-10. It is a copy laid out like the seekdb repository and does not run from
here; [device_tests/README.md](device_tests/README.md) explains what it contains and how
to restore it in seekdb.
