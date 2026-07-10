# Flutter App Updater

[![CI](https://github.com/indie-geeker/flutter_app_updater/actions/workflows/ci.yml/badge.svg)](https://github.com/indie-geeker/flutter_app_updater/actions/workflows/ci.yml)
[![pub package](https://img.shields.io/pub/v/flutter_app_updater.svg)](https://pub.dev/packages/flutter_app_updater)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Flutter App Updater is a UI-free v3 update foundation for commercial Flutter apps. It checks a manifest, selects the right release for the current app, and performs explicit update actions.

Stable v3 scope:

- Android: Google Play URL, Chinese Android markets, APK download, APK install, and download then install.
- iOS: App Store URL.
- macOS: Mac App Store URL, DMG and ZIP installer download then open.
- Windows: MSIX, MSI, and EXE installer download then open.

Planned scope: Play In-App Updates, OHOS, and Linux installer flows.

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
  expectedAppId: 'com.example.app',
  installedVersion: '1.0.0',
  platform: defaultTargetPlatform,
  architecture: 'arm64',
  channel: 'stable',
  downloadDirectory: downloadDirectory,
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

The required `expectedAppId` binds a remote manifest to the consuming app.
Manifests for another application fail with `APP_ID_MISMATCH` before release
selection or action execution.

## Progress and cancellation

Download and installer actions expose started, progress, and one terminal event:

```dart
final cancelToken = UpdateActionCancelToken();

await for (final event in updater.performRecommendedStream(
  result,
  cancelToken: cancelToken,
)) {
  switch (event) {
    case UpdateActionStarted():
      showProgress();
    case UpdateActionProgress(:final fraction):
      updateProgress(fraction);
    case UpdateActionCompleted(:final result):
      handleResult(result);
  }
}

// Call from your UI when the user cancels.
cancelToken.cancel();
```

`perform()` and `performRecommended()` remain available when a single terminal
result is sufficient.

## Network and artifact safety

- Manifest requests accept only absolute HTTP(S) URLs, default to 10-second
  connection and 20-second request timeouts, retry transient failures, and cap
  responses at 1 MiB.
- Self-hosted artifact executors require HTTPS outside localhost.
- Downloads use 30-second request and idle timeouts, retry transient failures,
  preserve validated ETag/Last-Modified resume state, and default to a 1 GiB
  maximum. Concurrent writes to the same target path are rejected.
- Declared artifact sizes must be positive and are enforced before and during
  streaming. Cancellation, size violations, and hash mismatches remove partial
  files.
- `sha256` remains optional for general compatibility. Commercial direct
  downloads should publish both the exact size and SHA-256 value.

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

`sha256` is optional. When it is present, the downloaded file is checked before the action continues. When it is absent, the package still downloads and installs.

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

Self-hosted APK installation is intended for policy-compliant enterprise,
private, or non-Play distribution. Google Play builds should use store actions
and must not request `REQUEST_INSTALL_PACKAGES` solely to update themselves.
The plugin does not add this sensitive permission automatically. Apps that are
eligible to install APKs must opt in from their application manifest:

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

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

| Platform | Official store | Chinese markets | Package download | Package install | Desktop installer | Play In-App Updates |
| --- | --- | --- | --- | --- | --- | --- |
| Android | Stable | Stable | Stable | Stable | Not applicable | Planned |
| iOS | Stable | Not applicable | Unsupported | Unsupported | Not applicable | Not applicable |
| macOS | Stable | Not applicable | Stable | Unsupported | Stable | Not applicable |
| Windows | Unsupported | Not applicable | Stable | Unsupported | Stable | Not applicable |
| OHOS | Planned | Planned | Planned | Planned | Not applicable | Not applicable |
| Linux | Planned | Not applicable | Planned | Planned | Planned | Not applicable |

Unsupported actions return structured failures instead of throwing platform exceptions through the public API.

## Error Handling

`checkAndPrepare()` returns:

- `PreparedUpdateAvailable`
- `PreparedUpdateNotAvailable`
- `PreparedUpdateCheckFailed`

`perform()` and `performRecommended()` return `UpdateActionResult`.

Useful error codes include:

- `MANIFEST_FETCH_FAILED`
- `MANIFEST_INVALID`
- `APP_ID_MISMATCH`
- `NO_SUPPORTED_ACTION`
- `STORE_NOT_AVAILABLE`
- `MARKET_NOT_AVAILABLE`
- `PACKAGE_DOWNLOAD_FAILED`
- `PACKAGE_TOO_LARGE`
- `PACKAGE_HASH_MISMATCH`
- `PACKAGE_INSTALL_PERMISSION_REQUIRED`
- `PACKAGE_FILE_NOT_FOUND`
- `PACKAGE_INSTALL_FAILED`
- `INSTALLER_OPEN_FAILED`
- `PLATFORM_NOT_SUPPORTED`
- `DOWNLOAD_IN_PROGRESS`
- `ACTION_FAILED`
- `ACTION_CANCELED`

## Example

The bundled example starts in a safe preview mode that uses a simulated
executor and never performs network or installer operations. Remote mode
requires an explicit manifest URL and expected application ID. See
[`example/README.md`](example/README.md) for runnable commands and platform
warnings.

## Maintainer Verification

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
dart doc --dry-run
flutter pub publish --dry-run
flutter analyze example
(cd example && flutter test)
(cd example && flutter build apk --debug)
(cd example && flutter build macos --debug)
```

CI also builds the Windows example. Store opening, Android package permission,
APK installation, and desktop installer launch still require targeted device or
host smoke tests before a production release.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development checks and
[SECURITY.md](SECURITY.md) for private vulnerability reporting.

## License

Apache-2.0
