# Flutter App Updater v3 Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a v3 breaking update framework centered on update sources, candidates, policies, and explicit update actions for official stores, Chinese Android markets, direct package updates, and desktop installers.

**Architecture:** Replace the v2 `FlutterAppUpdater` / `UpdateInfo` / `downloadUrl` model with `AppUpdater`, `UpdateSource`, `UpdateCandidate`, `UpdatePolicy`, and sealed `UpdateAction` types. Manifest v3 parsing chooses the best `UpdateCandidate` and exposes direct action semantics such as `openStore`, `openAndroidMarket`, `downloadPackage`, and `openInstaller`.

**Tech Stack:** Dart 3 sealed classes, Flutter plugin method channels, Android Kotlin intents, Swift StoreKit / URL opening, C++ Windows plugin hooks, `crypto` for SHA-256, existing `flutter_test` and `test`.

---

## Preconditions

- Work from `/Users/wen/Desktop/Personal/Projects/flutter_app_updater`.
- Preserve unrelated dirty files unless the task explicitly edits them.
- v3 is intentionally breaking. Do not keep compatibility wrappers for v2 APIs.
- Run `flutter analyze` and `flutter test` after each phase that changes Dart code.
- Use exact staged commits per task. Do not stage unrelated files.

## Task 1: Define v3 Core Model

**Files:**
- Create: `lib/src/core/app_updater.dart`
- Create: `lib/src/core/update_source.dart`
- Create: `lib/src/models/update_candidate.dart`
- Create: `lib/src/models/update_policy.dart`
- Create: `lib/src/actions/update_action.dart`
- Modify: `lib/flutter_app_updater.dart`
- Test: `test/unit/v3/update_candidate_test.dart`
- Test: `test/unit/v3/update_action_test.dart`

**Step 1: Write failing model tests**

Add tests that construct:

- `UpdateCandidate`
- `UpdatePolicy`
- `OpenStoreAction`
- `OpenAndroidMarketAction`
- `DownloadPackageAction`
- `OpenInstallerAction`

Expected initial failure: imports or classes do not exist.

**Step 2: Run tests to verify failure**

Run:

```bash
flutter test test/unit/v3/update_candidate_test.dart test/unit/v3/update_action_test.dart
```

Expected: FAIL because v3 model files do not exist.

**Step 3: Implement minimal model types**

Create sealed action types with direct field names:

```dart
sealed class UpdateAction {
  const UpdateAction();
}

class OpenStoreAction extends UpdateAction {
  final StoreKind store;
  final Uri storeUrl;

  const OpenStoreAction({
    required this.store,
    required this.storeUrl,
  });
}

class DownloadPackageAction extends UpdateAction {
  final Uri packageUrl;
  final PackageType packageType;
  final int? packageSizeBytes;
  final String sha256;
  final String? signature;

  const DownloadPackageAction({
    required this.packageUrl,
    required this.packageType,
    this.packageSizeBytes,
    required this.sha256,
    this.signature,
  });
}
```

Add equivalent `OpenAndroidMarketAction`, `PlayInAppUpdateAction`, and `OpenInstallerAction`.

**Step 4: Replace public exports**

Modify `lib/flutter_app_updater.dart` to export only v3 public types. Remove v2 exports from the public API.

**Step 5: Run verification**

Run:

```bash
flutter analyze
flutter test test/unit/v3/update_candidate_test.dart test/unit/v3/update_action_test.dart
```

Expected: PASS.

**Step 6: Commit**

```bash
git add lib/flutter_app_updater.dart lib/src/core lib/src/models/update_candidate.dart lib/src/models/update_policy.dart lib/src/actions test/unit/v3
git commit -m "feat: define v3 updater core model"
```

## Task 2: Implement Manifest v3 Parser

**Files:**
- Create: `lib/src/manifest/update_manifest.dart`
- Create: `lib/src/manifest/manifest_parser.dart`
- Create: `lib/src/manifest/manifest_validator.dart`
- Create: `lib/src/models/update_error_code.dart`
- Test: `test/unit/v3/manifest_parser_test.dart`
- Test: `test/unit/v3/manifest_validator_test.dart`

**Step 1: Write failing parser tests**

Cover:

- parses `schemaVersion: 3`
- parses `version`, `buildNumber`, `platform`, `architecture`, `releaseNotes`, `releasedAt`
- parses `policy.level`
- parses action-specific fields: `storeUrl`, `packageUrl`, `installerUrl`
- rejects `downloadUrl`
- rejects `md5`
- rejects missing `sha256` for package and installer actions

Expected initial failure: parser does not exist.

**Step 2: Run tests to verify failure**

```bash
flutter test test/unit/v3/manifest_parser_test.dart test/unit/v3/manifest_validator_test.dart
```

Expected: FAIL.

**Step 3: Implement parser**

Implement a parser that accepts this schema:

```json
{
  "schemaVersion": 3,
  "appId": "com.example.app",
  "channel": "stable",
  "releases": []
}
```

Each release maps to `UpdateCandidate`. Each action maps to a concrete `UpdateAction`.

**Step 4: Implement validation errors**

Use structured codes:

- `MANIFEST_INVALID`
- `UNSUPPORTED_SCHEMA_VERSION`
- `UNSUPPORTED_ACTION_TYPE`
- `MISSING_REQUIRED_FIELD`
- `LEGACY_FIELD_NOT_SUPPORTED`

**Step 5: Run verification**

```bash
flutter analyze
flutter test test/unit/v3/manifest_parser_test.dart test/unit/v3/manifest_validator_test.dart
```

Expected: PASS.

**Step 6: Commit**

```bash
git add lib/src/manifest lib/src/models/update_error_code.dart test/unit/v3/manifest_parser_test.dart test/unit/v3/manifest_validator_test.dart
git commit -m "feat: parse v3 update manifests"
```

## Task 3: Implement Release Selection

**Files:**
- Create: `lib/src/core/update_selector.dart`
- Modify: `lib/src/core/update_source.dart`
- Modify: `lib/src/core/app_updater.dart`
- Test: `test/unit/v3/update_selector_test.dart`

**Step 1: Write failing selection tests**

Cover:

- ignores releases for other platforms
- ignores releases for other architectures
- respects configured channel
- selects the highest version greater than installed version
- returns no update when installed version is current
- treats `policy.level == required` as recommended action priority

Expected initial failure: selector does not exist.

**Step 2: Run tests**

```bash
flutter test test/unit/v3/update_selector_test.dart
```

Expected: FAIL.

**Step 3: Implement selector**

Create `UpdateSelector` with inputs:

- `installedVersion`
- `installedBuildNumber`
- `platform`
- `architecture`
- `channel`

Return a structured check result:

```dart
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class UpdateAvailable extends UpdateCheckResult {
  final UpdateCandidate candidate;
  final UpdateAction recommendedAction;
}

class UpdateNotAvailable extends UpdateCheckResult {}

class UpdateCheckFailed extends UpdateCheckResult {
  final UpdateErrorCode code;
  final String message;
}
```

**Step 4: Replace ambiguous null returns**

Ensure `AppUpdater.check()` never returns `null`.

**Step 5: Run verification**

```bash
flutter analyze
flutter test test/unit/v3/update_selector_test.dart
```

Expected: PASS.

**Step 6: Commit**

```bash
git add lib/src/core/update_selector.dart lib/src/core/update_source.dart lib/src/core/app_updater.dart test/unit/v3/update_selector_test.dart
git commit -m "feat: select v3 update candidates"
```

## Task 4: Add Official Store Actions

**Files:**
- Create: `lib/src/platform/store_update_executor.dart`
- Modify: `lib/src/channel/flutter_app_updater_platform_interface.dart`
- Modify: `lib/src/channel/flutter_app_updater_method_channel.dart`
- Modify: `android/src/main/kotlin/com/indiegeeker/flutter_app_updater/FlutterAppUpdaterPlugin.kt`
- Modify: `ios/Classes/FlutterAppUpdaterPlugin.swift`
- Modify: `macos/Classes/FlutterAppUpdaterPlugin.swift`
- Test: `test/unit/v3/store_action_test.dart`

**Step 1: Write failing tests**

Cover:

- `OpenStoreAction` delegates to platform executor
- invalid store URL returns structured failure
- non-store action is rejected by store executor

Expected initial failure: executor does not exist.

**Step 2: Implement Dart executor**

Add:

```dart
abstract class UpdateActionExecutor {
  bool supports(UpdateAction action);
  Future<UpdateActionResult> perform(UpdateAction action);
}
```

Implement store executor using method channel methods:

- `openStore`
- `startPlayInAppUpdate`

**Step 3: Implement Android store opening**

Kotlin should:

- parse `storeUrl`
- create `Intent(Intent.ACTION_VIEW, uri)`
- add `FLAG_ACTIVITY_NEW_TASK`
- optionally set Play package for Google Play fallback
- return structured method-channel errors

**Step 4: Implement iOS/macOS store opening**

Swift should:

- open external App Store URLs
- leave StoreKit product-page integration as an optional later enhancement unless required

**Step 5: Run verification**

```bash
flutter analyze
flutter test test/unit/v3/store_action_test.dart
```

Expected: PASS.

**Step 6: Commit**

```bash
git add lib/src/platform/store_update_executor.dart lib/src/channel android/src/main/kotlin/com/indiegeeker/flutter_app_updater/FlutterAppUpdaterPlugin.kt ios/Classes/FlutterAppUpdaterPlugin.swift macos/Classes/FlutterAppUpdaterPlugin.swift test/unit/v3/store_action_test.dart
git commit -m "feat: add official store update actions"
```

## Task 5: Add Chinese Android Market Actions

**Files:**
- Create: `lib/src/platform/android_market.dart`
- Create: `lib/src/platform/android_market_registry.dart`
- Modify: `android/src/main/AndroidManifest.xml`
- Modify: `android/src/main/kotlin/com/indiegeeker/flutter_app_updater/FlutterAppUpdaterPlugin.kt`
- Test: `test/unit/v3/android_market_test.dart`

**Step 1: Write failing tests**

Cover:

- Huawei registry entry
- Honor registry entry
- Xiaomi registry entry
- OPPO registry entry
- vivo registry entry
- Meizu registry entry
- Tencent MyApp registry entry
- fallback URL behavior

Expected initial failure: registry does not exist.

**Step 2: Implement registry**

Use clear public names:

```dart
class AndroidMarketDescriptor {
  final AndroidMarketKind market;
  final String marketPackageName;
  final String uriTemplate;
  final Uri? fallbackUrl;
}
```

Do not promise automatic install. This only opens the market page/update page.

**Step 3: Add Android package visibility**

Modify `android/src/main/AndroidManifest.xml` with `<queries>` entries for known market package names.

**Step 4: Implement native market opening**

Kotlin method:

- `openAndroidMarket`

Behavior:

1. Try configured market package.
2. Try generic `market://details?id=<targetPackageName>`.
3. Try `fallbackUrl`.
4. Return `MARKET_NOT_AVAILABLE` if all fail.

**Step 5: Run verification**

```bash
flutter analyze
flutter test test/unit/v3/android_market_test.dart
```

Expected: PASS.

**Step 6: Commit**

```bash
git add lib/src/platform/android_market.dart lib/src/platform/android_market_registry.dart android/src/main/AndroidManifest.xml android/src/main/kotlin/com/indiegeeker/flutter_app_updater/FlutterAppUpdaterPlugin.kt test/unit/v3/android_market_test.dart
git commit -m "feat: add Chinese Android market actions"
```

## Task 6: Rebuild Direct Package Downloads

**Files:**
- Create: `lib/src/download/package_downloader.dart`
- Create: `lib/src/download/package_download_result.dart`
- Modify: `lib/src/network/update_downloader.dart`
- Modify: `lib/src/utils/retry_strategy.dart`
- Test: `test/unit/v3/package_downloader_test.dart`

**Step 1: Write failing tests**

Cover:

- uses `packageUrl`
- verifies SHA-256
- rejects missing SHA-256
- rejects hash mismatch
- resumes only when ETag or Last-Modified still matches
- falls back to clean download when Range is unsupported

Expected initial failure: v3 downloader does not exist.

**Step 2: Implement v3 downloader wrapper**

Create `PackageDownloader` that accepts `DownloadPackageAction`.

Do not expose `downloadUrl` or `md5`.

**Step 3: Upgrade hashing**

Use SHA-256 through `crypto`.

**Step 4: Add resume safety metadata**

Persist sidecar metadata for partial files:

```json
{
  "packageUrl": "...",
  "etag": "...",
  "lastModified": "...",
  "downloadedBytes": 123
}
```

**Step 5: Run verification**

```bash
flutter analyze
flutter test test/unit/v3/package_downloader_test.dart
```

Expected: PASS.

**Step 6: Commit**

```bash
git add lib/src/download lib/src/network/update_downloader.dart lib/src/utils/retry_strategy.dart test/unit/v3/package_downloader_test.dart
git commit -m "feat: rebuild package downloads for v3"
```

## Task 7: Add Desktop Installer Actions

**Files:**
- Create: `lib/src/platform/desktop_installer_executor.dart`
- Modify: `windows/flutter_app_updater_plugin.cpp`
- Modify: `macos/Classes/FlutterAppUpdaterPlugin.swift`
- Test: `test/unit/v3/desktop_installer_test.dart`

**Step 1: Write failing tests**

Cover:

- accepts supported installer types by platform
- rejects unsupported installer types
- requires SHA-256 before opening installer
- returns structured failure for unsupported platform

Expected initial failure: executor does not exist.

**Step 2: Implement Dart executor**

`OpenInstallerAction` should download and verify the installer, then call the platform opener.

**Step 3: Implement macOS opener**

Open verified `.dmg` or `.zip` with the system default handler.

**Step 4: Implement Windows opener**

Open verified `.msix`, `.msi`, or `.exe` with ShellExecute or equivalent.

**Step 5: Defer Linux implementation if plugin platform support is absent**

If Linux is not currently in `pubspec.yaml`, keep Linux documented as planned support and do not claim it in the runtime matrix until implemented.

**Step 6: Run verification**

```bash
flutter analyze
flutter test test/unit/v3/desktop_installer_test.dart
```

Expected: PASS.

**Step 7: Commit**

```bash
git add lib/src/platform/desktop_installer_executor.dart windows/flutter_app_updater_plugin.cpp macos/Classes/FlutterAppUpdaterPlugin.swift test/unit/v3/desktop_installer_test.dart
git commit -m "feat: add desktop installer actions"
```

## Task 8: Rewrite README and Example

**Files:**
- Modify: `README.md`
- Modify: `example/lib/main.dart`
- Modify: `CHANGELOG.md`
- Test: `test/unit/v3/public_api_test.dart`

**Step 1: Write public API test**

Ensure public exports include:

- `AppUpdater`
- `UpdateSource`
- `UpdateCandidate`
- `UpdatePolicy`
- `UpdateAction`
- `OpenStoreAction`
- `OpenAndroidMarketAction`
- `DownloadPackageAction`
- `OpenInstallerAction`

Ensure v2 symbols are not exported:

- `FlutterAppUpdater`
- `UpdateInfo`

**Step 2: Rewrite README**

Document:

- v3 is breaking
- official store updates
- Chinese Android market jumps
- direct package updates
- desktop installer updates
- manifest v3
- security model
- platform matrix

**Step 3: Update example**

Use one example each for:

- manifest source
- App Store or Play Store action
- Chinese market action
- direct package action

**Step 4: Run verification**

```bash
flutter analyze
flutter test test/unit/v3/public_api_test.dart
flutter analyze example
```

Expected: PASS.

**Step 5: Commit**

```bash
git add README.md CHANGELOG.md example/lib/main.dart test/unit/v3/public_api_test.dart
git commit -m "docs: document v3 updater API"
```

## Task 9: Add Manifest CLI

**Files:**
- Create: `bin/flutter_app_updater.dart`
- Create: `lib/src/cli/manifest_command.dart`
- Create: `lib/src/cli/hash_command.dart`
- Test: `test/unit/v3/cli_manifest_test.dart`

**Step 1: Write failing CLI tests**

Cover:

- generates manifest skeleton
- computes SHA-256
- verifies manifest schema
- rejects legacy fields

Expected initial failure: CLI does not exist.

**Step 2: Implement CLI commands**

Supported commands:

```bash
dart run flutter_app_updater manifest generate
dart run flutter_app_updater manifest verify path/to/manifest.json
dart run flutter_app_updater hash path/to/package.apk
```

**Step 3: Run verification**

```bash
flutter analyze
flutter test test/unit/v3/cli_manifest_test.dart
dart run flutter_app_updater manifest verify docs/examples/update-manifest-v3.json
```

Expected: PASS.

**Step 4: Commit**

```bash
git add bin/flutter_app_updater.dart lib/src/cli test/unit/v3/cli_manifest_test.dart
git commit -m "feat: add v3 manifest tooling"
```

## Task 10: Final Validation

**Files:**
- No required source edits unless validation finds issues.

**Step 1: Run full checks**

```bash
flutter analyze
flutter test
flutter analyze example
flutter pub publish --dry-run
```

Expected:

- `flutter analyze`: PASS
- `flutter test`: PASS
- `flutter analyze example`: PASS
- `flutter pub publish --dry-run`: PASS or only documented non-code publishing warnings

**Step 2: Inspect public package surface**

Run:

```bash
dart doc --dry-run
```

Expected: no broken public documentation.

**Step 3: Commit fixes if needed**

If validation requires fixes:

```bash
git add <changed-files>
git commit -m "chore: validate v3 updater redesign"
```

## Execution Options

Plan complete and saved to `docs/plans/2026-07-03-v3-updater-redesign-implementation.md`.

Two execution options:

1. **Subagent-Driven (this session)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Parallel Session (separate)** - open a new session with `superpowers:executing-plans`, batch execution with checkpoints.

