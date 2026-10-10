# 2026-10-10 lifecycle-only framework runs

Framework: seekdb `2b17e74e74f6513caa26c535e436d98964836ca5`, built from a clean tree
(`source_dirty` false, test hooks disabled) for the arm64 iOS Simulator with
`build.iphone.sh release --simulator --deps-prefix <seekdb>/deps/ios/iphonesimulator/devel`.
Its `seekdb.h` declares only `seekdb_open`, `seekdb_close` and
`seekdb_connection_options`, and it exports 10 symbols. Probe: this repository's
`26fc9cc93cac694f3bab11a6af01e8dbec8bbfae`. The probe loads the three lifecycle
functions and five iOS diagnostic functions with `dlopen`/`dlsym` and runs SQL with its
own Connector/C 3.4.8 over the Unix socket that `seekdb_connection_options` returns. Its
reports set `framework_api` to `lifecycle`.

Tools: macOS 27.0, Xcode 27.0 and the iOS 27.0 SDK. All runs used one iPhone 17
Simulator with iOS 27.0, with no debugger attached.

## Basic runs

`simulator-run-1.json` and `simulator-run-2.json` are two independent process launches.
Both passed 51/51 assertions with `complete`, `passed` and `worker_exit` true, and
`previous_runs` advanced from 9 to 10. Compared with the 77 assertions of the earlier
probe, the 22 `dlsym` checks for removed functions, the `value ownership`,
`framework allocation` and two `scalar traversal` checks are gone, and the nine
`free statement result` checks became `statement has no result set`.

## Stability run

`simulator-stability-run-1.json` to `-5.json` come from
`run_framework_stability.py --duration 600 --runs 5`; `summary.json` collects the
results of both runs.

| Platform | Duration (s) | Transaction iterations | Concurrent reads | Connections opened | Warmup memory MiB | Sampled peak MiB | Max iteration time ms | Persisted counter |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| arm64 Simulator / iOS 27.0 | 600.168 | 2927 | 5781 | 181 | 241.581 | 241.581 | 50.303 | 1464 |

The first launch ran for 600 seconds; the next 4 read the committed counter, which
stayed at 1464. Every launch passed 51/51 assertions with `complete`, `passed` and
`worker_exit` true, and the soak's reader thread joined. Transactions alternated commit
and rollback on one fixed row, and every expected-count check passed. The largest of the
60 samples was the one at the end of the 60-second warmup, so the footprint did not grow
after the warmup; the last sample was 219.862 MiB. The raw 10-second samples are in
`simulator-stability-run-1.json`; a sampled peak is not the instantaneous peak.

The 2026-10-07 Simulator run (framework `6f902fdab24c`, SQL through the framework's own
C API) measured 162.175 MiB at warmup, a 215.534 MiB sampled peak and a 12.576 ms slowest
iteration. This run's warmup footprint is about 79.4 MiB higher and its slowest
iteration took longer. The cause was not investigated.

The files contain no certificates, profiles, device identifiers, App container paths or
large logs.

## Scope

- The 19 host tests in `ios/framework_probe` passed, including
  `test_recorded_lifecycle_runs_pass` and `test_recorded_lifecycle_soak_passes`, which
  validate these files.
- No device build or device run was done for this framework.
- As with the 2026-10-07 runs, this proves only a fixed small data set, 10 minutes in the
  foreground, limited concurrency and 5 process launches. It does not prove 24-hour
  operation, background or suspend recovery, high concurrency or large data, and it is
  not a strict proof of no memory leaks. Starting again in the same process after the
  final close is still unsupported.

```sh
python3 ios/framework_probe/validate_framework_probe.py \
  --revision 2b17e74e74f6513caa26c535e436d98964836ca5 \
  ios/framework_probe/framework_evidence/lifecycle-20261010/simulator-run-1.json \
  ios/framework_probe/framework_evidence/lifecycle-20261010/simulator-run-2.json
python3 -B -m unittest discover -s ios/framework_probe
```
