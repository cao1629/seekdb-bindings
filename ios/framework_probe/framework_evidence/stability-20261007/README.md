# 2026-10-07 dynamic framework stability runs

These files moved here on 2026-10-10 from
`unittest/ios_build/framework_evidence/stability-20261007` in oceanbase/seekdb,
branch `ios/iphone13-17-iphoneOS2627-macOS27`. The original notes were in Chinese;
this is a translation, and the JSON reports are unchanged.

Engine source: `6f902fdab24ccefdde97c991b50faf551928b604`; test source:
`9d149628cd45c839b4ed2d8c822c75c440bc21ce` (both seekdb revisions). The previously
accepted framework was used and the production engine was not changed. SQL went
through Connector/C over the actual Unix socket, test hooks were disabled, and no
debugger was attached.

| Platform | Duration (s) | Transaction iterations | Concurrent reads | Connections opened | Warmup memory MiB | Sampled peak MiB | Max iteration time ms | Persisted counter |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| iPhone 17 Pro / iOS 27.0.1 | 600.250 | 2933 | 5822 | 182 | 163.283 | 213.768 | 4.258 | 1467 |
| arm64 Simulator / iOS 27.0 | 600.051 | 2901 | 5721 | 179 | 162.175 | 215.534 | 12.576 | 1451 |

Each platform ran 5 process launches: the first ran for 600 seconds, and the next 4
read the committed counter, which stayed at 1467 and 1451 respectively. Every run
passed the 77 basic API and lifecycle assertions with complete, passed and
worker_exit all true, and the soak's reader thread joined. Transactions alternated
commit and rollback on one fixed row, and every expected-count check passed. The
peak rose about 50.5 / 53.4 MiB above the 60-second warmup baseline, below the
256 MiB limit for this run. The raw 10-second samples are kept in run-1.json; a
sampled peak is not the instantaneous peak. The runner terminated only its own
probe process. The record contains all 10 raw small JSON reports and the summary,
and no certificates, profiles, device identifiers, App container paths or large
logs.

## Scope verified and failures

- 14 framework host gates passed (8 new stability gates and the 6 earlier
  dynamic-evidence gates).
- Extended seekdb iOS host suite (`unittest/ios_build`): 347 tests, 338 passed,
  1 skipped, 3 failed, 5 errors, so the full suite cannot be claimed as passing.
  The 5 errors and 1 failure are in test_device_registry, where the simulated
  device launch diagnostic is `device launch failed: iPhone remained locked`; they
  cover the lock-screen retry, durable SQL round recovery and the unknown launch
  error text check. These are host simulation results, not evidence of a real
  device lock or crash in this run. The other 2 failures are test_mysqltest_parser's
  FIFO / symlink / oversized JSON rejection check and test_product_neutrality's
  product-name check over upstream source records and integration audits. These
  separate issues were not fixed in this run.
- This run proves only a fixed small data set, 10 minutes in the foreground,
  limited concurrency and 5 process launches. It does not prove 24-hour operation,
  background or suspend recovery, high concurrency, large data or the stability of
  the whole QuickLang App, and it is not a strict proof of no memory leaks.
  Starting again in the same process after the final close is still unsupported.

Rerun commands and thresholds are in the framework probe section of `ios/README.md`.
