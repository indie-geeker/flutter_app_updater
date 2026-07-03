# Flutter App Updater v3 Commercial Quality Design

## Goal

Raise `flutter_app_updater` to a stable, simple, open-source-quality foundation for independent commercial Flutter apps.

The target is a 9/10 or better score across functionality, architecture, integration experience, platform execution, reliability, testing, open-source release hygiene, and documentation.

## Confirmed Scope

The first stable scope is intentionally practical:

- Android: Google Play URL, Chinese Android markets, APK download, APK install, and download-then-install.
- iOS: App Store URL.
- macOS: Mac App Store URL and DMG/ZIP download-then-open.
- Windows: MSIX/MSI/EXE download-then-open.
- OHOS: not part of the first stable promise; document as planned or experimental.
- Linux: not part of the first stable promise; document as planned.
- Google Play In-App Updates: not part of the first stable promise; document as planned.

The core package remains UI-free. It should provide optional convenience flow APIs and examples, but not a bundled visual update dialog as the required integration path.

Breaking API adjustments are allowed while v3 is being hardened. Prefer a coherent long-term v3 API over preserving current draft shapes.

No HTTPS requirement, mandatory SHA-256 rule, manifest signing rule, or package signing rule is part of this round. The package may verify a hash when one is provided, but must not require it.

## Architecture

Keep the v3 model centered on:

- `AppUpdater`
- `UpdateSource`
- `UpdateSelector`
- `UpdateCandidate`
- `UpdatePolicy`
- `UpdateAction`
- `UpdateActionExecutor`

Expose two public API layers.

### Low-Level API

The low-level API keeps explicit control:

- Callers construct an `AppUpdater`.
- Callers choose the `UpdateSource`.
- Callers provide or override an `UpdateSelector`.
- Callers can inject custom `UpdateActionExecutor` instances.
- Callers call `check()` and `perform(action)`.

This layer is for advanced apps that want their own orchestration.

### Convenience Flow API

Add a simple default path for independent developers. It should build the selector and default executors for the stable platform promise without forcing callers to assemble the graph manually.

The final naming can change during implementation, but the shape should stay close to:

```dart
final updater = AppUpdater.manifest(
  manifestUrl: Uri.parse('https://example.com/app-updates.json'),
  installedVersion: '1.0.0',
  platform: defaultTargetPlatform,
  channel: 'stable',
  downloadDirectory: appDownloadDirectory,
);

final result = await updater.checkAndPrepare();
```

The convenience result must be UI-neutral and easy to drive from an app dialog:

- no update
- check failed
- update available
- candidate metadata
- recommended action
- all candidate actions
- optional prepared execution metadata

The package may also expose `performRecommended()` when a checked update is available, but it should not hide failures or user-choice requirements.

## Action Model

Keep actions explicit. Do not overload one action with unrelated meanings.

Stable actions:

- `OpenStoreAction`: open App Store, Mac App Store, Google Play, or a store URL.
- `OpenAndroidMarketAction`: open a known Chinese Android market or fallback URL.
- `DownloadPackageAction`: download a package file only.
- `InstallPackageAction`: install an existing local package file.
- `DownloadAndInstallPackageAction`: download a package and then launch platform install.
- `OpenInstallerAction`: download and open a desktop installer.

Planned or unsupported actions should return structured failures instead of pretending to work.

Default `AppUpdater` executors must match the stable promise:

- store executor
- Android market executor
- download package executor
- install package executor
- download-and-install package executor
- desktop installer executor

## Manifest Design

Keep direct field names:

- `storeUrl`
- `packageUrl`
- `installerUrl`
- `packageSizeBytes`
- `installerSizeBytes`
- `releaseNotes`
- `releasedAt`
- `sha256`

For package and installer actions, `sha256` is optional. If present, verify it. If absent, continue without hash verification.

Example self-hosted APK action:

```json
{
  "type": "downloadAndInstallPackage",
  "packageUrl": "https://example.com/app.apk",
  "packageType": "apk",
  "packageSizeBytes": 25600000,
  "sha256": "optional"
}
```

Remove or avoid public `signature` fields unless automatic signature verification is implemented. Do not leave fields that imply security guarantees the package does not provide.

The runtime parser and CLI verifier must share the same schema behavior. A manifest that passes CLI verification must not fail at runtime for stricter schema reasons.

## Policy Semantics

`UpdatePolicy.minSupportedVersion` must have real behavior or be removed from the public promise.

Preferred behavior:

- `policy.level == required` marks the update as required.
- `minSupportedVersion` makes the update required when the installed version is below the minimum supported version.
- The result should expose whether the update is required so callers can adjust their UI.

## Platform Behavior

### Android

Android is the strongest first platform.

Required stable behavior:

- open Google Play/store URLs
- open known Chinese Android markets
- download APK files
- install local APK files using the existing native `installApp` capability
- provide a combined download-then-install action
- return structured failures for missing install permission, missing file, install start failure, unsupported platform, download failure, and hash mismatch when a hash is provided

The package does not need to implement Google Play In-App Updates in this round.

### iOS

Required stable behavior:

- open App Store URLs
- return structured unsupported errors for package install or installer actions

### macOS

Required stable behavior:

- open Mac App Store URLs
- download DMG/ZIP installers
- open verified or unverified installers depending on whether `sha256` was provided

### Windows

Required stable behavior:

- download MSIX/MSI/EXE installers
- open installers through the system shell
- return structured failure on shell launch errors

### OHOS and Linux

Do not claim stable support in this round. Mark as planned or experimental in docs and platform matrix.

## Error Handling

Errors should tell the caller what happened and what they can do next.

Result types:

- `UpdateNotAvailable`
- `UpdateCheckFailed`
- `UpdateAvailable`
- `UpdateActionResult.success`
- `UpdateActionResult.failure`

Add or normalize error codes for:

- manifest fetch failure
- manifest invalid
- unsupported schema version
- unsupported action type
- no matching release
- no supported action
- store not available
- market not available
- package download failed
- package hash mismatch
- package install permission missing
- package file missing
- package install failed
- installer open failed
- platform not supported

Do not collapse failures into `null`, booleans, or thrown platform exceptions at the public API boundary.

## Documentation

Rewrite documentation around copyable integration paths.

README order:

1. What the package does and does not promise.
2. Install.
3. Quick start using the convenience API.
4. Handle update result in app UI.
5. Manifest examples.
6. Recipes:
   - official store update
   - Chinese Android market update
   - self-hosted Android APK download and install
   - iOS App Store update
   - macOS/Windows installer update
7. Platform matrix with actual stable/planned status.
8. Error handling.
9. Maintainer verification commands.

`example/README.md` must explain how to run the example and which v3 flows it demonstrates. It should not keep Flutter template text.

## Example App

The example app should demonstrate the stable v3 flow:

- check a manifest
- show update availability
- show candidate metadata
- show recommended action
- perform a fake or safe action in tests
- list all actions for inspection

The example widget test must assert the current v3 UI instead of the original template platform-version text.

## Release Hygiene

The publish archive must not contain internal planning documents. Add `.pubignore` entries for internal plan directories such as:

```text
doc/plans/
docs/plans/
```

The package should keep public docs and examples, but not implementation plans.

## CI and Verification

CI should enforce the same gates maintainers run locally:

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

Publish workflow should use the same Flutter setup strategy as CI, and should not rely on stale hard-coded SDK versions.

## Acceptance Criteria

The work is complete only when:

- All stable platform promises have matching public API, implementation, docs, and tests.
- Default `AppUpdater` execution can handle every stable action without requiring callers to manually assemble executors.
- Android self-hosted APK can use an explicit download-then-install action.
- `sha256` is optional, and hash mismatch is only possible when a hash is provided.
- Runtime parser and CLI manifest verifier accept and reject the same manifest shapes.
- README quick start uses only public API.
- `example/README.md` is specific to this package.
- Example widget tests pass.
- CI includes the full verification gate.
- `flutter pub publish --dry-run` reports 0 warnings.
- The publish archive excludes `doc/plans/` and `docs/plans/`.
- Fresh local verification passes all required commands.
