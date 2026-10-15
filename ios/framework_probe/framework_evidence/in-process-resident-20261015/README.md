# 2026-10-15 in-process runs with the engine kept running

Framework: seekdb `fde2cf4c113efa62b1f12ba5e0475cb7675f6956` (branch `feature/ios-swift`), built for the
arm64 iOS Simulator with `./build.sh release --ios --simulator --make`. Its manifest
records `source_dirty` true only because the seekdb worktree held an untracked
`.clangd` editor file. From this revision the engine keeps running until the process
exits: `seekdb_close` only releases the handle, and the same directory can be opened
again. The framework exports 6 symbols: `seekdb_open`, `seekdb_last_open_error`,
`seekdb_close`, `seekdb_connection_options`, `seekdb_in_process_get_state` and
`seekdb_in_process_get_build_id`. Probe: this repository's
`f26c85cc3115d03264301ed3bd9e437da5be001b`. Its reports set `framework_api` to
`in_process_resident`.

Tools: macOS 27.0, Xcode 27.0 and the iOS 27.0 SDK. Both runs used one iPhone 17
Simulator with iOS 27.0, with no debugger attached.

`simulator-run-1.json` and `simulator-run-2.json` are two independent process launches.
Both passed 49/49 assertions with `complete`, `passed` and `worker_exit` true, and
`previous_runs` advanced from 36 to 37. Compared with the `in_process` runs, the
two `dlsym` checks for the cleanup diagnostics, `capture cwd`, `close and join engine`,
`stopped and cleaned up` and `one startup per process` are gone; after closing its last
handle the probe now checks `engine keeps running after close`, `reopen running engine`,
`SQL after reopen`, `close reopened handle` and `other directory rejected`, after
`close last handle`.

```bash
python3 ios/framework_probe/validate_framework_probe.py \
  --revision fde2cf4c113efa62b1f12ba5e0475cb7675f6956 \
  ios/framework_probe/framework_evidence/in-process-resident-20261015/simulator-run-1.json \
  ios/framework_probe/framework_evidence/in-process-resident-20261015/simulator-run-2.json
```
