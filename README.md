# Flutter App Updater

Flutter App Updater v3 is a breaking update for modeling application updates as explicit actions.

The package is centered on:

- `AppUpdater`
- `UpdateSource`
- `UpdateCandidate`
- `UpdatePolicy`
- `UpdateAction`

v3 describes what the app should do next: open an official store, open a Chinese Android market, download a self-hosted package, or open a desktop installer.

## Install

```yaml
dependencies:
  flutter_app_updater: ^3.0.0
```

## Quick Start

```dart
final updater = AppUpdater(
  source: UpdateSource.manifest(
    manifestUrl: Uri.parse('https://example.com/app-updates.json'),
  ),
  selector: const UpdateSelector(
    installedVersion: '1.0.0',
    platform: TargetPlatform.android,
    architecture: 'arm64',
    channel: 'stable',
  ),
);
```

`check()` always returns a structured result:

```dart
final result = await updater.check();

switch (result) {
  case UpdateAvailable(:final recommendedAction):
    final actionResult = await updater.perform(recommendedAction);
    if (!actionResult.isSuccess) {
      debugPrint('${actionResult.code}: ${actionResult.message}');
    }
  case UpdateNotAvailable():
    debugPrint('Already current');
  case UpdateCheckFailed(:final code, :final message):
    debugPrint('$code: $message');
}
```

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
        "level": "required",
        "minSupportedVersion": "1.5.0"
      },
      "actions": [
        {
          "type": "downloadPackage",
          "packageUrl": "https://example.com/app.apk",
          "packageType": "apk",
          "packageSizeBytes": 25600000,
          "sha256": "..."
        }
      ]
    }
  ]
}
```

Use direct field names:

- `storeUrl`
- `packageUrl`
- `installerUrl`
- `packageSizeBytes`
- `installerSizeBytes`
- `releaseNotes`
- `releasedAt`
- `sha256`

## Official Store Updates

Use `OpenStoreAction` for App Store, Mac App Store, or Google Play fallback pages.

```json
{
  "type": "openStore",
  "store": "googlePlay",
  "storeUrl": "https://play.google.com/store/apps/details?id=com.example.app"
}
```

Use `PlayInAppUpdateAction` when an Android app is distributed through Google Play:

```json
{
  "type": "playInAppUpdate",
  "mode": "immediate"
}
```

## Chinese Android Markets

Use `OpenAndroidMarketAction` for Huawei AppGallery, Honor App Market, Xiaomi GetApps, OPPO App Market, vivo App Store, Meizu App Store, Tencent MyApp, or generic Android market pages.

```json
{
  "type": "openAndroidMarket",
  "market": "xiaomi",
  "targetPackageName": "com.example.app",
  "fallbackUrl": "https://app.mi.com/details?id=com.example.app"
}
```

This opens a market page or update page. It does not promise automatic installation.

## Direct Package Updates

Use `DownloadPackageAction` for self-hosted package distribution:

```json
{
  "type": "downloadPackage",
  "packageUrl": "https://example.com/app.apk",
  "packageType": "apk",
  "packageSizeBytes": 25600000,
  "sha256": "..."
}
```

Package downloads verify SHA-256 before the file is accepted. Resume metadata stores the package URL, validators, and downloaded byte count in a sidecar file.

## Desktop Installer Updates

Use `OpenInstallerAction` for desktop installer flows:

```json
{
  "type": "openInstaller",
  "installerUrl": "https://example.com/app.msi",
  "installerType": "msi",
  "installerSizeBytes": 82000000,
  "sha256": "..."
}
```

The first v3 desktop path downloads, verifies, and opens the installer. Silent replacement, background daemons, and relaunch orchestration are out of scope.

## Platform Matrix

| Platform | Official store | Chinese markets | Direct package | Desktop installer |
| --- | --- | --- | --- | --- |
| Android | Google Play URL, Play in-app entry point | Supported | APK package flow | Not applicable |
| iOS | App Store URL | Not applicable | File download only | Not applicable |
| macOS | Mac App Store URL | Not applicable | File download only | DMG, ZIP |
| Windows | Store URL through system handler | Not applicable | File download only | MSIX, MSI, EXE |
| Linux | Planned | Not applicable | File download only | Planned |

## Security Model

- Package and installer actions require SHA-256.
- The manifest parser rejects unsupported schema versions and unsupported action types.
- Package resume only uses Range when the saved validator still matches.
- Failures are structured with `UpdateErrorCode`.
- v3 does not collapse failed checks into `null`.

## Migration

v3 is not API-compatible with v2. Replace the old single-update-info flow with candidates, policies, and explicit actions.

## Verification

Maintainers should run:

```bash
flutter analyze
flutter test
flutter analyze example
dart doc --dry-run
flutter pub publish --dry-run
```

## License

Apache-2.0
