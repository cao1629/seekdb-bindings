# Parked iOS device test suite

This directory stores, unchanged, the iOS device test suite that was removed from
oceanbase/seekdb on 2026-10-10 (branch `ios/iphone13-17-iphoneOS2627-macOS27`,
removal commit `03f38fcfc`). The files are a copy of seekdb revision `14a930a80` and
keep their seekdb paths, so this directory mirrors the seekdb repository root. They
are kept here for now only; this repository does not build, run or test them.

## Contents

- `unittest/ios_build/`: the engine probe App (`app/`); engine-internal device cases
  (allocator and error mapping, vector, memory, the `empty_table` mysqltest replay, the
  adapter for the Rust cases); the device test registry and JSONL evidence writer; the
  host runner that builds, signs and installs the App and runs its phases
  (`run_all_iphone_tests.py`, `iphone_test_phases.py` and their helpers); the mysqltest
  device classification and macOS host gate; the layered test inventory; host Python
  tests for all of these and for seekdb build scripts; and manual dependency probes.
- `run.iphone.test.sh`: the runner entry point.
- `deps/ios-build/build_app.py`: builds, signs and installs the engine probe App from an
  engine build with test hooks enabled.
- `rust/sql-nio/src/device_tests.rs`: the Rust device cases, exported over FFI behind the
  `ios-device-tests` feature.
- `docs/`: the runner design, the inventory schema, the layered test strategy and the two
  2026-09-24 plans.

## Why it does not run here

The scripts find the repository root from their own location and expect seekdb's
`build.iphone.sh`, CMake targets, engine sources, CI mysqltest scripts and
`tools/deploy` test corpus. The engine side they relied on was removed from seekdb in the
same commit: the `SEEKDB_IOS_TEST_HOOKS` option and the
`SEEKDB_IOS_TEST_FAIL_DURING_INIT` injection in `ob_server.cpp`, the
`seekdb_ios_sql_probe` and `seekdb_ios_link_check` targets (the link check was the
default `build.iphone.sh` target), the `ios-device-test` Cargo profile, and the
`ios-device-tests` feature with its cbindgen defines and `nio.h` declarations.

Three files stayed in seekdb at new paths: `verify_framework.py` in
`src/observer/ios/driver/`, `rustc_lldb_wrapper.py` in `cmake/` and
`macos_lldb_launcher.py` in `.github/script/seekdb/`. The copies under
`unittest/ios_build/` here are the versions from `14a930a80`.

## Using it again

Revert seekdb commit `03f38fcfc`, which restores these files and the engine-side hooks
together, or check out seekdb revision `14a930a80`. The last complete device run is
recorded in seekdb's `docs/developer-guide/zh/ios-build.md`: revision `6deac1205`,
2026-10-04, iPhone 17 Pro, all 8 stages and 24/24 checks passed.

The public-API framework probe in `../framework_probe` is separate and does run from this
repository.
