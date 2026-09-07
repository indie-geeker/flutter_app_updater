# Reliability implementation verification

This is local evidence for the reliability changes, not release approval.
No update package was installed and no changes were pushed or published.

## Changes and regression evidence

| Plan | Change | Evidence |
| --- | --- | --- |
| T1 | Unix descriptor ownership plus legacy cross-process lock | Competing isolate rejection, failed-contender legacy probe, process exit, separate targets, parent aliases, symlink rejection; Android API 36 arm64 device test |
| T2 | Pre-cancellation preserves another owner's partial state | Held-lock fixture checks unchanged partial bytes and checkpoint; existing cancellation/failure release tests |
| T3 | Exact size and required SHA-256 for every network artifact | Empty/whitespace/nonhex/short hash rejected without requests; desktop does not open unverified files |
| T4 | Android foreground directory matches FileProvider | Runtime-loader tests; actual provider URI readable inside root and rejected outside root |
| T5 | Debug/Release macOS network entitlement, deployment target 10.15 | Debug sandbox HTTPS fails with errno 1 before fix and passes after; Release builds and contains network.client entitlement |
| T6 | Platform-aware executors, selector consistency and dispatch cancellation | Signed iOS APK manifest returns noSupportedAction; incompatible selector rejected; pre-cancel and cancel-on-Started prevent executor calls |
| T7 | Opt-in latestExecutable | Older optional executable release selected; latestRelease unchanged; required and minimum-supported barriers block fallback |
| T8 | Expanded native/SDK CI | Minimum/stable Android matrix, desktop Release builds and native tests, macOS/Windows ownership tests, manual device workflow |
| T9 | Immutable parser and prepared snapshots | Input mutation cannot change prepared candidates/actions; writes to returned lists fail |
| T10 | Artifact metadata, checkpoint store, file committer | Existing resume/recovery vectors retained; injected commit rename failure restores old artifact; pure-Dart CLI and API docs checks |

## Validation commands

Run root `flutter analyze --no-pub`, `flutter test --coverage --no-pub`,
`dart run tool/ci/verify_cli_executable.dart`, and `dart doc --dry-run` after
resolving dependencies for the selected SDK. The critical coverage gate covers
15 files, including all extracted storage/ownership implementations.

Run example `flutter analyze --no-pub`, `flutter test --no-pub`, and
`flutter build apk --debug --no-pub`. Native Android checks run from
`example/android`:

```sh
../../android/gradlew :flutter_app_updater:testDebugUnitTest :flutter_app_updater:lintDebug :app:processDebugMainManifest --console=plain
```

Device checks run from `example`:

```sh
flutter test integration_test/foreground_install_handoff_test.dart -d emulator-5554
flutter test integration_test/production_network_test.dart -d macos --dart-define=UPDATER_NETWORK_TEST_URL=https://example.com/
```

The HTTPS test proves bounded sandbox transport, not signature verification or
an authenticated production end-to-end update. Signature checks use separate
cryptographically signed fixtures. The Android probe verifies FFI ownership and
provider access without opening an installer or requesting install permission.

## Platform evidence and limits

- Flutter 3.29.0 and local stable Flutter 3.44.8: root analysis and 444 tests,
  example analysis and 54 tests, formatting, CLI and API-doc checks passed. Final stable
  line coverage is 2164/2396 (90.32%); all 15 critical files exceed 80%.
  Android Debug APK builds passed with both toolchains. Dependencies resolve independently;
  example lockfiles are not shared across SDK verification copies.
- Android native unit tests: 154 passed in seven suites; lint and merged manifest
  tasks passed under both SDK verification environments. Existing lint warnings remain, including platform/API hygiene
  that was not part of these behavior fixes.
- Android API 36 arm64 emulator: two integration tests passed. This does not
  establish API 21 or physical-device behavior.
- macOS 26.6 arm64: Debug and Release builds passed. Debug HTTPS runtime test
  passed; Release embedded entitlement inspected. Release network runtime,
  signed distribution, installer handoff and real installation remain unverified.
- iOS simulator Debug build passed with the local stable toolchain; iOS runtime
  store handoff and signed-device behavior remain unverified.
- Windows Debug/Release, native tests and ownership cases are configured in CI;
  no Windows runner was executed locally. Linux is not a supported executor target.
- CI files are configured locally, not evidence of a successful hosted CI run.
  Flutter-generated Apple project migrations are excluded from the implementation;
  the tool applies its own migrations during builds. Swift Package Manager plugin
  adoption remains follow-up work; current Apple builds use the CocoaPods fallback.

## Compatibility and follow-up

The selection default and public const model constructors remain source compatible.
Callers relying on empty hashes, credential-bearing artifact URLs, iOS APK
capabilities, or mutable prepared lists must migrate. Every remote artifact
continues through whole-manifest trust validation. Trusted local install actions
retain their optional paired size/hash fields.

Keep both persistent lock files and upgrade all isolate entry points together;
mixed legacy/new implementations in the same process are not protected by the
new ownership layer. Do not unlink locks during a transfer. Crash recovery of
final `.previous` files and desktop file identity between Dart verification and
native path opening require separate hardening. Further decomposition of the
Android durable engine is intentionally outside this implementation.
