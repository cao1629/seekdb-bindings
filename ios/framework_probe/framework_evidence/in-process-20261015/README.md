# 2026-10-15 in-process framework runs

Framework: seekdb `e45afec4924e7279e28ad0bb18afc4fdf336d4e0` (branch `feature/ios-swift`), built for the
arm64 iOS Simulator with `./build.sh release --ios --simulator --make`. Its manifest
records `source_dirty` true only because the seekdb worktree held an untracked
`.clangd` editor file. Its `seekdb.h` declares `seekdb_open`, `seekdb_last_open_error`,
`seekdb_close` and `seekdb_connection_options`, and it exports 8 symbols: those four and
`seekdb_in_process_get_state`, `seekdb_in_process_get_cleanup_status`,
`seekdb_in_process_get_cleanup_error` and `seekdb_in_process_get_build_id`. Probe: this
repository's `378ea75b453cd5755d28c3040f359bee860f6bf1`. The probe loads the three lifecycle functions
and the four diagnostic functions with `dlopen`/`dlsym` and runs SQL with its own
Connector/C 3.4.8 over the Unix socket that `seekdb_connection_options` returns. Its
reports set `framework_api` to `in_process`.

Tools: macOS 27.0, Xcode 27.0 and the iOS 27.0 SDK. Both runs used one iPhone 17
Simulator with iOS 27.0, with no debugger attached.

`simulator-run-1.json` and `simulator-run-2.json` are two independent process launches.
Both passed 49/49 assertions with `complete`, `passed` and `worker_exit` true, and
`previous_runs` advanced from 30 to 31. Compared with the 51 assertions of the lifecycle
runs, the `dlsym seekdb_in_process_get_hook_mode` and `production hooks disabled` checks
are gone, because seekdb removed the test-hook query.

```bash
python3 ios/framework_probe/validate_framework_probe.py \
  --revision e45afec4924e7279e28ad0bb18afc4fdf336d4e0 \
  ios/framework_probe/framework_evidence/in-process-20261015/simulator-run-1.json \
  ios/framework_probe/framework_evidence/in-process-20261015/simulator-run-2.json
```
