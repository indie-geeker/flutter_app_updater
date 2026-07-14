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

Future work, not registered or exposed by the stable runtime: Play In-App
Updates, OHOS, and Linux installer flows.

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

Existing v2 integrations should follow the
[v2-to-v3 migration guide](doc/migration-v2-to-v3.md). The complete transport,
signature, artifact, and platform trust boundaries are documented in the
[security model](doc/security-model.md).

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

## Advanced Android-only background downloads

`AndroidBackgroundDownloadManager` is an opt-in API for one durable,
user-visible APK transfer at a time. It is separate from the default
`AppUpdater` action flow and is available only on Android. A start request must
come from a visible, user-initiated host flow and must include an HTTPS URL, the
exact content length, and a lowercase or uppercase SHA-256 digest:

```dart
final downloads = AndroidBackgroundDownloadManager();
final task = await downloads.start(
  DownloadPackageAction(
    packageUrl: Uri.parse('https://downloads.example.com/app.apk'),
    packageType: PackageType.apk,
    packageSizeBytes: 25600000,
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ),
);

await for (final snapshot in downloads.watch(task.id)) {
  updateBackgroundDownloadUi(snapshot);
}
```

Use `list()`, `listUnfinished()`, and `get()` after startup to reconcile your
UI with durable native state. Call `resume()` only in response to a user action
when a task is waiting or paused. `cancel()` is terminal. Call `remove()` only
after cancel or another terminal result; it then deletes the durable task and
its private artifact.

### Required host manifest

The plugin manifest deliberately does not opt applications into background
execution. Merge all of the following declarations into the host app's
`android/app/src/main/AndroidManifest.xml`, keeping the app's existing
activities, providers, metadata, and other components:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
    <uses-permission android:name="android.permission.RUN_USER_INITIATED_JOBS" />

    <application>
        <!-- Keep the host's existing activity and application declarations. -->
        <service
            android:name="com.indiegeeker.flutter_app_updater.background.UserInitiatedDownloadJobService"
            android:permission="android.permission.BIND_JOB_SERVICE"
            android:exported="false" />
        <service
            android:name="com.indiegeeker.flutter_app_updater.background.BackgroundDownloadForegroundService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />
        <receiver
            android:name="com.indiegeeker.flutter_app_updater.background.BackgroundDownloadActionReceiver"
            android:exported="false" />
    </application>
</manifest>
```

The host application owns notification permission: it decides when and how to
request `POST_NOTIFICATIONS` at runtime on Android 13+, explains the visible
transfer to the user, and handles denial. The package declares neither this
runtime request nor a battery-exemption prompt. A manifest declaration alone
does not grant notification permission.

On API 21-25 the package enters the visible foreground-service lifecycle after
`startService`; on API 26-33 it does so after `startForegroundService`. The
`dataSync` foreground-service type has platform meaning on API 29+. A process
stop or network loss can leave durable state that the host shows after reopen;
recovery is explicit through `resume()` or the user-visible notification
action. There is no unattended API 21-33 network recovery guarantee.
On API 34+ the package submits a user-initiated data transfer job with an internet
requirement. Android still controls admission, stop reasons, and execution
time, so the host must handle scheduling rejection and expose retry.

Google Play distribution does not make self-hosted APK updates or foreground
services policy-compliant. Play apps should normally use store delivery, and
the publisher remains responsible for current foreground-service and
user-initiated-transfer declarations, eligibility, and review requirements.
Do not add `REQUEST_INSTALL_PACKAGES` solely to self-update a Play build.

### Server and installation contracts

Production artifacts must use HTTPS and immutable bytes. Supply the exact
content length and SHA-256 to `start()`. Safe and efficient resume requires the
server to support `Range: bytes=N-`, return a precise `206 Content-Range`, and
keep a strong ETag stable for those bytes so `If-Range` cannot append a changed
artifact. A server that ignores Range may cause a clean restart; weak or
changing validators are not resume evidence.

Download completion and installation are deliberately separate:

```dart
final installAction = await downloads.createInstallAction(task.id);
// createInstallAction revalidates the private APK but does not install the APK.
final installResult = await updater.perform(installAction);
```

`createInstallAction()` rechecks the private file, expected size, SHA-256,
package name, and signing lineage, then returns an `InstallPackageAction`.
Only the later explicit `AppUpdater.perform()` call can open Android's package
installer, which remains the final installation authority. The plugin does not
provide silent installation.

### Recovery limits

Native records and partial bytes survive Flutter engine detach and ordinary
process recreation. They do not make Android continue work after force-stop,
and jobs are not persisted across reboot. Reopen the app, call `listUnfinished()`,
and let the user choose `resume()` where the state permits it. Recents swipe,
Task Manager Stop, battery restriction, background-start limits, storage
pressure, and OEM process management can stop or reject execution.

The implementation does not use or promise WorkManager or DownloadManager,
does not request battery exemptions, and does not promise uninterrupted
background execution on any OEM family. Record exact model, API level,
ROM/build, battery mode, and notification state during device qualification.
See [the verification matrix](tool/verification/android_background_download.md)
for reproducible protocol and device checks.

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

The bundled example opens on a configurable update simulator with no external
side effects.
It also includes a separately labeled production integration tab that is
disabled by default. When explicitly configured, that tab exercises the real
signed-manifest fetch, verification, identity binding, selection, preparation,
and user-confirmed action path. See
[`example/README.md`](example/README.md) for the safety boundary, configuration,
and runnable commands.

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

The Android-native reliability gate runs from `example/android`:

```bash
../../android/gradlew :flutter_app_updater:testDebugUnitTest :flutter_app_updater:lintDebug :app:processDebugMainManifest
```

CI also builds the Windows example. Store opening, Android package permission,
APK installation, and desktop installer launch still require targeted device or
host smoke tests before a production release.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development checks and
[SECURITY.md](SECURITY.md) for private vulnerability reporting.

## License

Apache-2.0
