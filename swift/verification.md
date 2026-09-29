# verification

Validation of the Swift lifecycle and connection-options binding, 2026-09-29.

- Source base: `cao1629/seekdb-bindings` main at `cdb303f`; work branch `swift-bindings`.
- Host: Apple Silicon macOS 15.5; Xcode 16.4; Swift 6.1.2; iPhoneSimulator SDK 18.5.
- macOS native `libseekdb.dylib` built from this worktree using CMake with Python
  and C++ test targets disabled, external zlib, and no engine binary requirement.
- Fourteen Swift tests passed against that native library, including a real C
  error-path call with Unicode parameter values; no test server was required.
- Six native iOS-adapter lifecycle tests passed normally and under AddressSanitizer
  and UndefinedBehaviorSanitizer. ARM64 iOS Simulator C compilation passed
  `-Wall -Wextra -Werror`.
- The Swift package declares no third-party Swift dependencies. Protocol-level
  integration validation uses an independent consumer project outside this repository.
- An actual Swift UIKit consumer linked the package and existing ARM64 Simulator
  engine archives, installed, and ran on iPhone 16 Pro / iOS 18.6 Simulator.
  Opening a new persistent directory, returning Unix socket connection options,
  closing the engine, repeated close, and rejecting connection-options access
  after close all passed. The app recorded `Stopped` after engine shutdown.
- The external Swift consumer passed ten SQL checks through the returned socket:
  text expressions, schema creation, prepared insert/read/update/delete, text
  typed reads, rollback, commit, and a persistent run counter. Values included
  Unicode, binary bytes, NULL, and the maximum unsigned 64-bit integer.
- After clean shutdown and application-process restart, the same directory's
  counter advanced from 0 to 1 and then from 1 to 2. Both runs recorded clean
  shutdown and all five lifecycle checks passing.
- The final consumer binary declares iOS Simulator, minimum iOS 18.0, SDK 18.5.
  It passed the same SQL and lifecycle checks again, advancing the counter to 3.
- The external SQL client required a local compatibility patch for legacy MySQL
  metadata EOF packets and capability negotiation. Its ten packet regression
  tests passed. The client, dependency declarations, patch, and consumer source
  remain outside this repository; this does not establish compatibility with an
  unmodified third-party Swift SQL driver.

Linux, physical iPhone, and long-running stability remain unverified. Repeated
lifecycle cycles within one process are unsupported by the current iOS runtime.
