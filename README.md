# Flutter App Updater

Flutter App Updater is a UI-free v3 update foundation for commercial Flutter apps. It checks a manifest, selects the right release for the current app, and performs explicit update actions.

Stable v3 scope:

- Android: Google Play uses storeUrl, Chinese Android markets, APK download, APK install, and download then install.
- iOS: App Store uses storeUrl.
- macOS: Mac App Store uses storeUrl; non-store macOS apps can download and open DMG or ZIP installers.
- Windows: MSIX, MSI, and EXE installer download then open.

Future platform work: OHOS and Linux installer flows.

## Install

```yaml
dependencies:
  flutter_app_updater: ^3.0.0
```

## Quick Start

Use `AppUpdater.manifest` for the default integration path:

```dart
final updater = AppUpdater.manifest(
  manifestUrl: Uri.parse('https://example.com/app-updates.json'),
  installedVersion: '1.0.0',
  platform: defaultTargetPlatform,
  architecture: 'arm64',
  channel: 'stable',
  downloadDirectory: downloadDirectory,
  expectedAppId: 'com.example.app',
);

final result = await updater.checkAndPrepare();

switch (result) {
  case PreparedUpdateAvailable():
    final actionResult = await updater.performRecommended(result);
    if (!actionResult.isSuccess) {
      debugPrint('${actionResult.code}: ${actionResult.message}');
    }
  case PreparedUpdateNotAvailable():
    debugPrint('Already current');
  case PreparedUpdateCheckFailed(:final code, :final message):
    debugPrint('$code: $message');
}
```

The package does not show UI. Use the prepared result to drive your own dialog, sheet, page, or silent policy.

## Manifest v3

```json
{
  "schemaVersion": 3,
  "appId": "com.example.app",
  "channel": "stable",
  "releases": [
    {
      "version": "2.0.0",
      "buildNumber": "42",
      "platform": "android",
      "architecture": "arm64",
      "releaseNotes": "Bug fixes",
      "releasedAt": "2026-07-03T10:00:00Z",
      "policy": {
        "level": "recommended",
        "minSupportedVersion": "1.5.0"
      },
      "actions": [
        {
          "type": "openStore",
          "store": "googlePlay",
          "storeUrl": "https://play.google.com/store/apps/details?id=com.example.app"
        },
        {
          "type": "downloadAndInstallPackage",
          "packageUrl": "https://example.com/app.apk",
          "packageType": "apk",
          "packageSizeBytes": 25600000
        }
      ]
    }
  ]
}
```

Direct field names:

- `storeUrl`
- `packageUrl`
- `installerUrl`
- `packageSizeBytes`
- `installerSizeBytes`
- `releaseNotes`
- `releasedAt`
- `sha256`

Pass `expectedAppId` when checking manifests so a server or channel mix-up cannot offer updates for another app. The manifest `appId` must match the expected value when it is configured.

`sha256` is optional but strongly recommended for self-hosted packages and installers. When it is present, the downloaded file is checked before the action continues. `packageSizeBytes` and `installerSizeBytes`, when present, must be positive and must match the downloaded byte count.

## Recipes

### Official Store

```json
{
  "type": "openStore",
  "store": "googlePlay",
  "storeUrl": "https://play.google.com/store/apps/details?id=com.example.app"
}
```

Use `appStore` for iOS and `macAppStore` for macOS.

If an Android manifest contains both `openStore` and `downloadAndInstallPackage`, `openStore` is the recommended action. Keep APK installation as an explicit self-hosted option.

### Chinese Android Markets

```json
{
  "type": "openAndroidMarket",
  "market": "xiaomi",
  "targetPackageName": "com.example.app",
  "fallbackUrl": "https://app.mi.com/details?id=com.example.app"
}
```

Supported market names: `huawei`, `honor`, `xiaomi`, `oppo`, `vivo`, `meizu`, `tencentMyApp`, and `generic`.

### Self-Hosted Android APK

Use one action when you want the package to download and then start Android installation:

```json
{
  "type": "downloadAndInstallPackage",
  "packageUrl": "https://example.com/app.apk",
  "packageType": "apk",
  "packageSizeBytes": 25600000,
  "sha256": "optional-file-hash"
}
```

APK self-hosted updates are host app opt-in on Android. Store URL updates do not need `REQUEST_INSTALL_PACKAGES`. If your host app offers APK installation, declare `android.permission.REQUEST_INSTALL_PACKAGES` in the host app manifest, keep the flow user initiated, and verify your distribution policy allows APK self-updates.

When Android returns `PACKAGE_INSTALL_PERMISSION_REQUIRED`, call `openInstallPermissionSettings()` from your UI flow after explaining why the permission is needed. The plugin opens the current app's unknown-source install permission page on Android 8+.

Android App Bundle (`aab`) files are store upload artifacts, not local install packages. `installPackage` and `downloadAndInstallPackage` accept only `apk`.

Self-hosted `packageUrl` values must use HTTPS outside localhost or `127.0.0.1` development URLs.

Use separate actions when your app wants to download now and install later:

```json
{
  "type": "downloadPackage",
  "packageUrl": "https://example.com/app.apk",
  "packageType": "apk"
}
```

```json
{
  "type": "installPackage",
  "packagePath": "/local/path/app.apk",
  "packageType": "apk"
}
```

### iOS App Store

```json
{
  "type": "openStore",
  "store": "appStore",
  "storeUrl": "https://apps.apple.com/app/id123456789"
}
```

### macOS and Windows Installers

Mac App Store builds should use `openStore` with `macAppStore`. Direct installer actions are for non-store macOS and Windows distribution.

Self-hosted `installerUrl` values must use HTTPS outside localhost or `127.0.0.1` development URLs.

```json
{
  "type": "openInstaller",
  "installerUrl": "https://example.com/app.msi",
  "installerType": "msi",
  "installerSizeBytes": 82000000
}
```

Supported stable installer types:

- Windows: `msix`, `msi`, `exe`
- macOS: `dmg`, `zip`

## Platform Matrix

| Platform | Official store | Chinese markets | Package download | Package install | Desktop installer |
| --- | --- | --- | --- | --- | --- |
| Android | Stable | Stable | Stable | Stable | Not applicable |
| iOS | Stable | Not applicable | Unsupported | Unsupported | Not applicable |
| macOS | Stable | Not applicable | Stable | Unsupported | Stable for non-store apps |
| Windows | URL handler support | Not applicable | Stable | Unsupported | Stable |
| OHOS | Planned | Planned | Planned | Planned | Not applicable |
| Linux | Planned | Not applicable | Planned | Planned | Planned |

Unsupported actions return structured failures instead of throwing platform exceptions through the public API.

## Error Handling

`checkAndPrepare()` returns:

- `PreparedUpdateAvailable`
- `PreparedUpdateNotAvailable`
- `PreparedUpdateCheckFailed`

`perform()` and `performRecommended()` return `UpdateActionResult`.

Use `performStream()` for self-hosted downloads when the UI needs progress or cancellation:

```dart
final cancelToken = UpdateActionCancelToken();

await for (final event in updater.performStream(
  update.recommendedAction,
  cancelToken: cancelToken,
)) {
  switch (event) {
    case UpdateActionStarted():
      break;
    case UpdateActionProgress(:final fraction):
      debugPrint('download progress: $fraction');
    case UpdateActionCompleted(:final result):
      debugPrint('${result.isSuccess}');
  }
}
```

Useful error codes include:

- `MANIFEST_FETCH_FAILED`
- `MANIFEST_INVALID`
- `NO_SUPPORTED_ACTION`
- `STORE_NOT_AVAILABLE`
- `MARKET_NOT_AVAILABLE`
- `PACKAGE_DOWNLOAD_FAILED`
- `PACKAGE_HASH_MISMATCH`
- `PACKAGE_INSTALL_PERMISSION_REQUIRED`
- `PACKAGE_FILE_NOT_FOUND`
- `PACKAGE_INSTALL_FAILED`
- `INSTALLER_OPEN_FAILED`
- `ACTION_CANCELED`
- `PLATFORM_NOT_SUPPORTED`

## Maintainer Verification

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

## License

Apache-2.0
