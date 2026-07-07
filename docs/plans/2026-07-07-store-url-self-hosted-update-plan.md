# Store URL and Self-Hosted Updates Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Align `flutter_app_updater` around store URL updates for app-store distribution and self-hosted package/installer updates for non-store channels, while removing Google Play In-App Updates from the product surface.

**Architecture:** Keep the v3 model explicit and small: store-distributed apps use `openStore`, self-hosted Android apps use APK download plus system installer, and desktop apps use installer download plus open. Remove Play In-App Updates instead of preserving compatibility shims or adding deprecation layers; this is a breaking v3 cleanup, not a compatibility release.

**Tech Stack:** Dart 3 sealed classes, Flutter plugin method channels, Android Kotlin install intents, `dart:io` streaming downloads, Flutter unit tests, CLI/runtime manifest validation, and the existing package publish gates.

---

## Product Decisions

- Google Play distribution uses `OpenStoreAction(store: StoreKind.googlePlay, storeUrl: ...)`.
- iOS distribution uses `OpenStoreAction(store: StoreKind.appStore, storeUrl: ...)`.
- If an Android release manifest includes both `openStore` and `downloadAndInstallPackage`, the recommended action must be `openStore`. The APK action remains an explicit self-hosted option, not the default recommendation.
- Google Play In-App Updates are out of scope and should be removed from code, tests, docs, examples, and platform channels.
- Do not keep `PlayInAppUpdateAction`, `PlayUpdateMode`, `startPlayInAppUpdate`, or `PLAY_IN_APP_UPDATE_UNAVAILABLE` only for compatibility.
- Do not add compatibility wrappers, deprecated aliases, or extra adapter code for removed Play In-App Updates APIs.
- Self-hosted updates are supported for Android APK and desktop installers only.
- iOS self-hosted app package updates are not supported. iOS stays App Store URL based for normal distribution.
- Mac App Store distribution stays store URL based. Self-hosted macOS installer flows apply only to non-store macOS distribution.
- `REQUEST_INSTALL_PACKAGES` must be host-app opt-in. The plugin must not merge the permission into every consumer app by default.
- The example app keeps an APK install demo, so the example Android app must explicitly opt in to `REQUEST_INSTALL_PACKAGES`.
- AAB is not a local install format. Do not claim local AAB install support.
- Preserve unrelated dirty or untracked files. As of this plan, `doc/plans/2026-07-03-v3-quality-hardening-implementation.md` is untracked and should not be staged unless explicitly requested.

## Not In Scope

- Google Play In-App Updates, Play Core app-update dependencies, or compatibility aliases for removed Play APIs.
- iOS self-hosted package installation.
- Play-distributed APK self-update as the recommended path.
- Mac App Store apps installing third-party packages.
- Local AAB install.
- Silent install or unverified native background install completion.

## Release Slices

- `3.1.0`: Remove Play In-App Updates surface and clean documentation.
- `3.1.0`: Prefer Android `openStore` when a manifest contains both store and direct APK install actions.
- `3.1.0`: Make Android APK install permission opt-in and reject local AAB install flows.
- `3.1.x`: Add self-hosted artifact safety checks before expanding download UX.
- `3.2.0`: Add download progress, cancellation, and safer resume metadata for self-hosted downloads.
- `3.2.x`: Add Android install-permission guidance and installer-launched result semantics.
- `3.3.0`: Add Android `DownloadManager` backend only if real app feedback shows the normal streaming downloader is insufficient.

## Verification Gate

Run before claiming a slice is complete:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
dart doc --dry-run
flutter pub publish --dry-run
flutter analyze example
(cd example && flutter test)
(cd example && flutter build apk --debug)
```

If a task changes manifest parsing, action validation, or platform matrix claims, also run CLI/runtime schema parity checks:

```bash
dart run flutter_app_updater manifest verify test/fixtures/v3/valid_manifest.json
dart run flutter_app_updater manifest verify test/fixtures/v3/invalid_aab_install_manifest.json
```

For Android-native tasks, add a manual smoke checklist and record the tested device/API level in the commit or handoff notes.

---

### Task 1: Remove Play In-App Updates From Public API

**Files:**
- Modify: `lib/src/actions/update_action.dart`
- Modify: `lib/src/manifest/manifest_parser.dart`
- Modify: `lib/src/manifest/manifest_schema.dart`
- Modify: `lib/src/models/update_error_code.dart`
- Modify: `lib/src/platform/store_update_executor.dart`
- Modify: `lib/src/channel/flutter_app_updater_platform_interface.dart`
- Modify: `lib/src/channel/flutter_app_updater_method_channel.dart`
- Modify: `lib/flutter_app_updater.dart`
- Test: `test/unit/v3/update_action_test.dart`
- Test: `test/unit/v3/manifest_parser_test.dart`
- Test: `test/unit/v3/manifest_validator_test.dart`
- Test: `test/unit/v3/store_action_test.dart`

**Step 1: Write failing removal tests**

Update tests so they assert the removed surface is gone:

```dart
test('manifest rejects Play in-app update actions', () {
  expect(
    () => const ManifestParser().parse(_manifestWithAction({
      'type': 'playInAppUpdate',
      'mode': 'immediate',
    })),
    throwsA(
      isA<ManifestParseException>().having(
        (error) => error.code,
        'code',
        UpdateErrorCode.unsupportedActionType,
      ),
    ),
  );
});
```

Use the existing `_manifestWithAction(...)` helper in `test/unit/v3/manifest_validator_test.dart`, or create the equivalent local helper if the test moves.

Remove tests that construct `PlayInAppUpdateAction` or expect `startPlayInAppUpdate` delegation. Do not replace them with deprecation tests.

**Step 2: Run tests to verify red**

```bash
flutter test test/unit/v3/update_action_test.dart test/unit/v3/manifest_parser_test.dart test/unit/v3/manifest_validator_test.dart test/unit/v3/store_action_test.dart
```

Expected: FAIL until the Play API, parser branch, schema branch, executor branch, platform methods, and error code are removed.

**Step 3: Remove the Play action model**

In `lib/src/actions/update_action.dart`, delete:

```dart
enum PlayUpdateMode {
  immediate,
  flexible,
}

class PlayInAppUpdateAction extends UpdateAction {
  final PlayUpdateMode mode;

  const PlayInAppUpdateAction({
    required this.mode,
  });
}
```

Do not add replacement classes.

**Step 4: Remove parser/schema support**

In `ManifestSchema._validateAction`, remove the `playInAppUpdate` case.

In `ManifestParser._parseAction`, remove the `playInAppUpdate` branch.

Delete `_parsePlayUpdateMode`.

**Step 5: Remove platform channel support**

Delete `startPlayInAppUpdate` from:

- `FlutterAppUpdaterPlatform`
- `MethodChannelFlutterAppUpdater`
- fake platform implementations in tests

Do not leave an unavailable method just for compatibility.

**Step 6: Remove executor support and error code**

In `StoreUpdateExecutor`, support only `OpenStoreAction`.

Delete `UpdateErrorCode.playInAppUpdateUnavailable`.

Update `RetryStrategy` or other exhaustive checks that referenced the deleted error code.

**Step 7: Verify**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/unit/v3/update_action_test.dart test/unit/v3/manifest_parser_test.dart test/unit/v3/manifest_validator_test.dart test/unit/v3/store_action_test.dart
```

Expected: PASS.

**Step 8: Commit**

```bash
git add lib test
git commit -m "refactor: remove Play in-app update surface"
```

### Task 2: Remove Native Play In-App Update Methods

**Files:**
- Modify: `android/src/main/kotlin/com/indiegeeker/flutter_app_updater/FlutterAppUpdaterPlugin.kt`
- Modify: `ios/Classes/FlutterAppUpdaterPlugin.swift`
- Modify: `macos/Classes/FlutterAppUpdaterPlugin.swift`
- Test: `android/src/test/kotlin/com/indiegeeker/flutter_app_updater/FlutterAppUpdaterPluginTest.kt`

**Step 1: Write or update native tests**

If Android native tests cover method dispatch, update them so `startPlayInAppUpdate` is not part of the plugin contract. If no native method-dispatch test exists, keep this task focused on source cleanup and rely on Flutter tests plus Android build.

**Step 2: Remove Android method handling**

In `FlutterAppUpdaterPlugin.kt`, delete:

```kotlin
"startPlayInAppUpdate" -> startPlayInAppUpdate(result)
```

Delete the `startPlayInAppUpdate` function.

**Step 3: Remove iOS/macOS method handling**

In iOS and macOS Swift plugins, delete the `startPlayInAppUpdate` cases and associated `FlutterError` branches.

**Step 4: Verify**

```bash
flutter analyze
(cd example && flutter build apk --debug)
```

Expected: PASS.

**Step 5: Commit**

```bash
git add android ios macos
git commit -m "refactor: remove native Play update hooks"
```

### Task 3: Update Documentation and Examples Around Store URL First

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `example/README.md`
- Modify: `example/lib/main.dart`
- Modify: `doc/examples/update-manifest-v3.json`
- Test: `test/unit/v3/public_api_test.dart`
- Test: `test/unit/public_api_test.dart`

**Step 1: Write failing docs tests**

Update public API/docs tests to assert:

```dart
expect(readme, contains('Google Play uses storeUrl'));
expect(readme, contains('App Store uses storeUrl'));
expect(readme, isNot(contains('Play In-App Updates')));
expect(readme, isNot(contains('playInAppUpdate')));
```

Also assert examples do not construct `PlayInAppUpdateAction`.

**Step 2: Run tests to verify red**

```bash
flutter test test/unit/v3/public_api_test.dart test/unit/public_api_test.dart
```

Expected: FAIL until docs/examples are cleaned.

**Step 3: Rewrite README scope**

README must state:

- Android store distribution: Google Play URL or Chinese market URL.
- iOS distribution: App Store URL.
- Self-hosted Android: APK download and system installer.
- Desktop non-store distribution: installer download and open.
- iOS self-hosted package install: unsupported.
- If Android manifest actions contain both `openStore` and `downloadAndInstallPackage`, `openStore` is recommended.

README must not mention Play In-App Updates at all. Put the breaking removal note in `CHANGELOG.md` instead of keeping Play wording in the README.

Remove the `Play In-App Updates` column from the platform matrix.
Remove `Planned scope: Play In-App Updates`.

**Step 4: Clean examples**

Remove Play update action examples from `example/lib/main.dart` and manifest examples.

Keep Google Play store URL examples.

Keep one Android APK self-hosted install demo in the example. Because Task 4 makes store actions recommended when both store and APK install actions exist, the example may show APK install as an explicit self-hosted action while the recommended action remains store URL.

**Step 5: Verify**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/unit/v3/public_api_test.dart test/unit/public_api_test.dart
flutter analyze example
```

Expected: PASS.

**Step 6: Commit**

```bash
git add README.md CHANGELOG.md example/README.md example/lib/main.dart doc/examples/update-manifest-v3.json test/unit/v3/public_api_test.dart test/unit/public_api_test.dart
git commit -m "docs: prefer store URLs and self-hosted updates"
```

### Task 4: Prefer Android Store Action When Store and APK Are Both Present

**Files:**
- Modify: `lib/src/core/update_selector.dart`
- Test: `test/unit/v3/update_selector_test.dart`
- Test: `test/unit/v3/app_updater_flow_test.dart`
- Test: `example/integration_test/plugin_integration_test.dart`

**Step 1: Replace the old direct-action priority test**

In `test/unit/v3/update_selector_test.dart`, replace the current required-update expectation that prefers `DownloadAndInstallPackageAction` over `OpenStoreAction` with:

```dart
test('prefers openStore over APK install on Android', () {
  final storeAction = OpenStoreAction(
    store: StoreKind.googlePlay,
    storeUrl: Uri.parse(
      'https://play.google.com/store/apps/details?id=com.example.app',
    ),
  );
  final packageAction = DownloadAndInstallPackageAction(
    packageUrl: Uri.parse('https://example.com/app.apk'),
    packageType: PackageType.apk,
  );

  final result = _selector(platform: TargetPlatform.android).select([
    _candidate(
      version: '2.0.0',
      policyLevel: UpdatePolicyLevel.required,
      actions: [
        packageAction,
        storeAction,
      ],
    ),
  ]);

  expect(result, isA<UpdateAvailable>());
  expect((result as UpdateAvailable).recommendedAction, same(storeAction));
  expect(result.isRequired, isTrue);
});
```

Add a second assertion or test with the action order reversed so this behavior is not an accidental first-action result.

**Step 2: Run tests to verify red**

```bash
flutter test test/unit/v3/update_selector_test.dart
```

Expected: FAIL while required Android updates still prefer direct package actions.

**Step 3: Implement minimal selector change**

In `UpdateSelector._recommendedAction`, check Android store actions before direct package actions:

```dart
if (platform == TargetPlatform.android) {
  for (final action in candidate.actions) {
    if (action is OpenStoreAction) {
      return action;
    }
  }
}
```

Keep the existing direct-action fallback so self-hosted manifests with only APK actions still work.

**Step 4: Update flow/integration expectations only where manifests contain both actions**

If a test manifest contains both `openStore` and `downloadAndInstallPackage`, update the expected recommended action to `OpenStoreAction`.

Do not change tests where the candidate only contains a package action; self-hosted-only candidates should still recommend the package action.

**Step 5: Verify**

```bash
dart format --output=none --set-exit-if-changed lib/src/core/update_selector.dart test/unit/v3/update_selector_test.dart
flutter test test/unit/v3/update_selector_test.dart test/unit/v3/app_updater_flow_test.dart
(cd example && flutter test integration_test/plugin_integration_test.dart)
```

Expected: PASS.

**Step 6: Commit**

```bash
git add lib/src/core/update_selector.dart test/unit/v3/update_selector_test.dart test/unit/v3/app_updater_flow_test.dart example/integration_test/plugin_integration_test.dart
git commit -m "fix: prefer Android store updates before APK install"
```

### Task 5: Make Android APK Install Permission Host Opt-In

**Files:**
- Modify: `android/src/main/AndroidManifest.xml`
- Modify: `example/android/app/src/main/AndroidManifest.xml`
- Modify: `README.md`
- Test: `test/unit/v3/public_api_test.dart`

**Step 1: Write failing docs/package tests**

Add tests that read plugin and README text:

```dart
test('plugin manifest does not force APK install permission', () {
  final manifest = File('android/src/main/AndroidManifest.xml').readAsStringSync();
  expect(manifest, isNot(contains('REQUEST_INSTALL_PACKAGES')));
});

test('README documents host opt-in install permission', () {
  final readme = File('README.md').readAsStringSync();
  expect(readme, contains('REQUEST_INSTALL_PACKAGES'));
  expect(readme, contains('host app'));
  expect(readme, contains('APK self-hosted updates'));
});

test('example opts in because it demonstrates APK install', () {
  final manifest = File('example/android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();
  expect(manifest, contains('REQUEST_INSTALL_PACKAGES'));
});
```

**Step 2: Run tests to verify red**

```bash
flutter test test/unit/v3/public_api_test.dart
```

Expected: FAIL while the plugin manifest still declares the permission and README lacks the opt-in guidance.

**Step 3: Remove default permission from plugin manifest**

Delete from `android/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

Keep `INTERNET` if package downloads remain supported.

**Step 4: Add opt-in permission to the example app**

The example keeps an APK self-hosted install demo, so add to `example/android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

Do not add this permission to the plugin manifest.

**Step 5: Document host responsibilities**

README must explain:

- Store URL updates do not need `REQUEST_INSTALL_PACKAGES`.
- Self-hosted APK install requires host opt-in permission.
- Google Play apps should avoid APK self-update unless their app category and Play policy allow it.
- The install must be user initiated.

**Step 6: Verify**

```bash
flutter test test/unit/v3/public_api_test.dart
(cd example && flutter build apk --debug)
flutter pub publish --dry-run
```

Expected: PASS and dry-run does not include internal plan docs.

**Step 7: Commit**

```bash
git add android/src/main/AndroidManifest.xml example/android/app/src/main/AndroidManifest.xml README.md test/unit/v3/public_api_test.dart
git commit -m "fix: make APK install permission opt in"
```

### Task 6: Reject Local AAB Install Flows and Tighten Manifest Actions

**Files:**
- Modify: `lib/src/manifest/manifest_validator.dart`
- Modify: `lib/src/manifest/manifest_schema.dart`
- Modify: `lib/src/platform/install_package_executor.dart`
- Modify: `lib/src/platform/download_and_install_package_executor.dart`
- Modify: `README.md`
- Create: `test/fixtures/v3/valid_manifest.json`
- Create: `test/fixtures/v3/invalid_aab_install_manifest.json`
- Test: `test/unit/v3/manifest_validator_test.dart`
- Test: `test/unit/v3/package_install_executor_test.dart`
- Test: `test/unit/v3/download_and_install_package_executor_test.dart`

**Step 1: Write failing validation tests**

Add tests:

```dart
test('rejects installPackage AAB actions', () {
  expect(
    () => const ManifestParser().parse(_manifestWithAction({
      'type': 'installPackage',
      'packagePath': '/tmp/app.aab',
      'packageType': 'aab',
    })),
    throwsA(isA<ManifestParseException>()),
  );
});

test('rejects downloadAndInstallPackage AAB actions', () {
  expect(
    () => const ManifestParser().parse(_manifestWithAction({
      'type': 'downloadAndInstallPackage',
      'packageUrl': 'https://example.com/app.aab',
      'packageType': 'aab',
    })),
    throwsA(isA<ManifestParseException>()),
  );
});
```

Use the existing `_manifestWithAction(...)` helper in `test/unit/v3/manifest_validator_test.dart`.

If the product decision is to remove AAB entirely, also reject `downloadPackage` with `packageType: aab`.

**Step 2: Run tests to verify red**

```bash
flutter test test/unit/v3/manifest_validator_test.dart test/unit/v3/package_install_executor_test.dart test/unit/v3/download_and_install_package_executor_test.dart
```

Expected: FAIL until validation and executors reject AAB install paths.

**Step 3: Implement validation**

In schema or validator action checks:

- `installPackage` allows only `packageType: apk`.
- `downloadAndInstallPackage` allows only `packageType: apk`.
- `downloadPackage` may allow `aab` only if README says it is download-only and cannot be installed.

**Step 4: Harden executors**

`InstallPackageExecutor.perform()` returns structured failure for non-APK package types.

`DownloadAndInstallPackageExecutor.perform()` returns structured failure before downloading non-APK packages.

**Step 5: Add CLI fixtures**

Create:

- `test/fixtures/v3/valid_manifest.json`
- `test/fixtures/v3/invalid_aab_install_manifest.json`

**Step 6: Verify CLI/runtime parity**

```bash
flutter test test/unit/v3/manifest_validator_test.dart test/unit/v3/package_install_executor_test.dart test/unit/v3/download_and_install_package_executor_test.dart
dart run flutter_app_updater manifest verify test/fixtures/v3/valid_manifest.json
dart run flutter_app_updater manifest verify test/fixtures/v3/invalid_aab_install_manifest.json
```

Expected: valid manifest passes; invalid AAB install manifest fails with the expected structured validation error.

**Step 7: Commit**

```bash
git add lib README.md test
git commit -m "fix: reject local AAB install flows"
```

### Task 7: Harden Self-Hosted Artifact Safety

**Files:**
- Modify: `lib/src/core/app_updater.dart`
- Modify: `lib/src/core/update_selector.dart`
- Modify: `lib/src/manifest/manifest_schema.dart`
- Modify: `lib/src/manifest/manifest_validator.dart`
- Modify: `lib/src/download/package_downloader.dart`
- Modify: `lib/src/platform/download_package_executor.dart`
- Modify: `lib/src/platform/download_and_install_package_executor.dart`
- Modify: `lib/src/platform/desktop_installer_executor.dart`
- Modify: `README.md`
- Test: `test/unit/v3/app_updater_manifest_source_test.dart`
- Test: `test/unit/v3/manifest_validator_test.dart`
- Test: `test/unit/v3/package_downloader_test.dart`
- Test: `test/unit/v3/download_package_executor_test.dart`
- Test: `test/unit/v3/download_and_install_package_executor_test.dart`
- Test: `test/unit/v3/desktop_installer_test.dart`

**Step 1: Write failing app identity tests**

Add tests that configure an expected app id and reject a manifest whose `appId` is different from the host app's expected id.

Keep the check explicit. Do not infer app identity from package names unless the app passes the expected id into the updater.

**Step 2: Write failing URL and size safety tests**

Add validation/executor tests for self-hosted artifacts:

- `packageUrl` and `installerUrl` must be HTTPS for production URLs.
- `http://localhost`, `http://127.0.0.1`, and test fixtures may remain allowed for tests and local development.
- `packageSizeBytes` and `installerSizeBytes`, when provided, must be positive.
- Downloaded byte count must match the declared size when a size is provided.
- `sha256`, when provided, remains verified after download.

**Step 3: Run tests to verify red**

```bash
flutter test test/unit/v3/app_updater_manifest_source_test.dart test/unit/v3/manifest_validator_test.dart test/unit/v3/package_downloader_test.dart test/unit/v3/download_package_executor_test.dart test/unit/v3/download_and_install_package_executor_test.dart test/unit/v3/desktop_installer_test.dart
```

Expected: FAIL until app id, HTTPS, and size checks are implemented.

**Step 4: Implement app id guard**

Add an optional expected app id to the selection/check path, then compare it with `UpdateManifest.appId` before selecting a candidate.

Return a structured manifest failure for mismatches. Do not silently ignore a manifest for another app.

**Step 5: Implement URL and size checks**

Validate self-hosted artifact URLs in schema/validator logic, and verify the final downloaded byte count in the downloader or executors.

Keep `sha256` strongly recommended in docs. If making it mandatory for self-hosted production URLs would break too much current API surface, document the residual risk and defer mandatory hash enforcement to the next breaking manifest version.

**Step 6: Verify**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/unit/v3/app_updater_manifest_source_test.dart test/unit/v3/manifest_validator_test.dart test/unit/v3/package_downloader_test.dart test/unit/v3/download_package_executor_test.dart test/unit/v3/download_and_install_package_executor_test.dart test/unit/v3/desktop_installer_test.dart
```

Expected: PASS.

**Step 7: Commit**

```bash
git add lib README.md test
git commit -m "fix: harden self-hosted update artifacts"
```

### Task 8: Add Self-Hosted Download Progress and Cancellation

**Files:**
- Create: `lib/src/platform/update_action_event.dart`
- Create: `lib/src/platform/update_action_cancel_token.dart`
- Create: `lib/src/platform/streaming_update_action_executor.dart`
- Modify: `lib/src/download/package_downloader.dart`
- Modify: `lib/src/download/package_download_result.dart`
- Modify: `lib/src/models/update_error_code.dart`
- Modify: `lib/src/utils/retry_strategy.dart`
- Modify: `lib/src/core/app_updater.dart`
- Modify: `lib/src/platform/download_package_executor.dart`
- Modify: `lib/src/platform/download_and_install_package_executor.dart`
- Modify: `lib/src/platform/desktop_installer_executor.dart`
- Modify: `lib/flutter_app_updater.dart`
- Test: `test/unit/v3/update_action_event_test.dart`
- Test: `test/unit/v3/app_updater_perform_stream_test.dart`
- Test: `test/unit/v3/package_downloader_test.dart`
- Test: `test/unit/v3/download_package_executor_test.dart`
- Test: `test/unit/v3/download_and_install_package_executor_test.dart`
- Test: `test/unit/v3/desktop_installer_test.dart`
- Test: `test/unit/retry_strategy_test.dart`

**Step 1: Write failing event tests**

Test progress, unknown totals, cancellation token behavior, and fallback from non-streaming executors.

**Step 2: Run tests to verify red**

```bash
flutter test test/unit/v3/update_action_event_test.dart test/unit/v3/app_updater_perform_stream_test.dart
```

Expected: FAIL because stream APIs do not exist.

**Step 3: Add compatible stream API without changing `UpdateActionExecutor`**

Create a separate `StreamingUpdateActionExecutor` interface. Do not add abstract members to `UpdateActionExecutor`.

Add `AppUpdater.performStream(UpdateAction action)`.

**Step 4: Add downloader progress and cancellation**

Change `PackageDownloader.download()` to accept optional:

- `void Function(PackageDownloadProgress progress)? onProgress`
- `UpdateActionCancelToken? cancelToken`

Write chunks manually so progress and resume metadata reflect bytes flushed to disk.

Map cancellation to a new structured error code such as `ACTION_CANCELED`.

Update `RetryStrategy._shouldRetryUpdateErrorCode` so cancellation is not retried.

**Step 5: Wire stream events through executors**

Make package and installer executors implement `StreamingUpdateActionExecutor` where they can emit real download progress.

Do not add Play-specific events.

**Step 6: Verify**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/unit/v3/update_action_event_test.dart test/unit/v3/app_updater_perform_stream_test.dart test/unit/v3/package_downloader_test.dart test/unit/v3/download_package_executor_test.dart test/unit/v3/download_and_install_package_executor_test.dart test/unit/v3/desktop_installer_test.dart test/unit/retry_strategy_test.dart
```

Expected: PASS.

**Step 7: Commit**

```bash
git add lib test
git commit -m "feat: stream self-hosted download progress"
```

### Task 9: Guide Android Install Permission and Clarify Install Result Semantics

**Files:**
- Modify: `lib/src/platform/update_action_event.dart`
- Modify: `lib/src/platform/install_package_executor.dart`
- Modify: `lib/src/channel/flutter_app_updater_platform_interface.dart`
- Modify: `lib/src/channel/flutter_app_updater_method_channel.dart`
- Modify: `android/src/main/kotlin/com/indiegeeker/flutter_app_updater/FlutterAppUpdaterPlugin.kt`
- Modify: `README.md`
- Test: `test/unit/v3/package_install_executor_test.dart`

**Step 1: Write failing tests**

Add tests that map missing Android install permission to a structured state and that install success means installer launch, not confirmed installation.

**Step 2: Add permission settings method**

Expose a platform method such as `openInstallPermissionSettings()` for Android. This is not a Play update flow.

**Step 3: Implement Android settings intent**

Use `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` with `package:${applicationContext.packageName}` where supported, and return structured failure if unavailable.

**Step 4: Rename or document success semantics**

Do not claim `installApp()` confirms installed version. It starts the system installer. README must instruct apps to verify installed version after restart if they need a closed loop.

**Step 5: Verify**

```bash
flutter analyze
flutter test test/unit/v3/package_install_executor_test.dart
(cd example && flutter build apk --debug)
```

Expected: PASS.

**Step 6: Commit**

```bash
git add lib android README.md test
git commit -m "feat: guide Android APK install permission"
```

### Task 10: Final Documentation, Examples, and Release Gate

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `example/lib/main.dart`
- Modify: `example/android/app/src/main/AndroidManifest.xml`
- Modify: `doc/examples/update-manifest-v3.json`

**Step 1: Final docs pass**

README must lead with:

- Store URL update for Google Play and App Store.
- Self-hosted Android APK update.
- Self-hosted desktop installer update.
- Mac App Store builds using Mac App Store URL, not third-party installers.
- Android manifests with both `openStore` and `downloadAndInstallPackage` recommending `openStore`.

README must not mention:

- `PlayInAppUpdateAction`
- `playInAppUpdate`
- the phrase `Play In-App Updates`
- Google Play app-update dependency

**Step 2: Final example pass**

Example should demonstrate store URL and self-hosted update actions only.

Because the example keeps the APK install demo, `example/android/app/src/main/AndroidManifest.xml` must include `REQUEST_INSTALL_PACKAGES`.

**Step 3: Run full gate**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
dart doc --dry-run
flutter pub publish --dry-run
flutter analyze example
(cd example && flutter test)
(cd example && flutter build apk --debug)
```

Expected: all pass.

**Step 4: Manual smoke checklist**

Record whether these were tested:

- Android store URL opens Google Play page.
- iOS store URL opens App Store page.
- Manifest `appId` mismatch is rejected.
- Self-hosted artifact URLs use HTTPS outside localhost/test fixtures.
- Android self-hosted APK downloads and verifies SHA-256.
- Android self-hosted APK size mismatch returns structured failure when `packageSizeBytes` is declared.
- Android missing unknown-source permission returns structured result.
- Android system installer is launched after permission is granted.
- Android installed version is verified after app restart or reinstall.
- Non-store macOS/Windows installer downloads and opens.
- Mac App Store build opens store URL only.

Do not claim real device install closure unless it was performed.

**Step 5: Commit**

```bash
git add README.md CHANGELOG.md example/lib/main.dart example/android/app/src/main/AndroidManifest.xml doc/examples/update-manifest-v3.json
git commit -m "docs: finalize store URL and self-hosted update scope"
```

## Execution Order

Execute Tasks 1-3 first. They remove the outdated Play In-App Updates direction and prevent future work from adding compatibility code.

Execute Tasks 4-6 next. They reduce Play policy and manifest-runtime mismatch risk while preserving the example APK demo with explicit opt-in.

Execute Task 7 before download UX work. It closes the highest-risk self-hosted safety gaps around app identity, HTTPS, declared size, and hashes.

Execute Tasks 8-9 after the public scope and self-hosted safety checks are clean. They improve self-hosted update UX without expanding platform scope.

Execute Task 10 last as the release/readiness gate.
