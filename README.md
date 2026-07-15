# Flutter App Updater

English | [简体中文](README.zh-CN.md)

[![CI](https://github.com/indie-geeker/flutter_app_updater/actions/workflows/ci.yml/badge.svg)](https://github.com/indie-geeker/flutter_app_updater/actions/workflows/ci.yml)
[![pub package](https://img.shields.io/pub/v/flutter_app_updater.svg)](https://pub.dev/packages/flutter_app_updater)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Flutter App Updater is a UI-free v3 update foundation for commercial Flutter apps. It checks a manifest, selects the right release for the current app, and performs explicit update actions.

Stable v3 scope:

- Android: Google Play URL, Chinese Android markets, APK download, APK install, and download then install.
- iOS: App Store URL.
- macOS: Mac App Store URL, DMG and ZIP installer download then open.
- Windows: MSIX, MSI, and EXE installer download then open.

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
  distributionPolicy: UpdateDistributionPolicy.any,
  signaturePolicy: ManifestSignaturePolicy.required(
    trustedPublicKeys: trustedManifestPublicKeys,
  ),
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

- Remote manifests and artifacts require absolute HTTPS URLs. Plain HTTP is an
  opt-in loopback-only development exception. Redirects are limited to five,
  every target is revalidated, HTTPS cannot downgrade to HTTP, and sensitive
  request headers cross only a same-origin redirect.
- Remote self-hosted actions require exact byte size and a required SHA-256
  digest, plus an authenticated Ed25519 envelope before payload parsing. The
  declared size must be positive.
- Downloads use 30-second request and idle timeouts, retry transient failures,
  preserve validated ETag/Last-Modified resume state, and default to a 1 GiB
  maximum. A URL fingerprint protects checkpoint privacy, and a process guard
  plus persistent operating-system lock reject competing writers.
- Declared artifact sizes must be positive and are enforced before and during
  streaming. Cancellation, size violations, and hash mismatches remove partial
  files.
- The manifest `appId`, platform, channel, and architecture are checked before
  action selection. Unknown runtime architecture fails closed for an
  architecture-specific release; only a genuinely universal release matches.
- Actions remain in publisher order. Host `UpdateDistributionPolicy` and
  executor capability filtering remove disallowed actions without reordering;
  the first remaining action is recommended. Use
  `UpdateDistributionPolicy.storeOnly` or
  `UpdateDistributionPolicy.selfHostedOnly` to make the host boundary explicit.

## Getting update information

`AppUpdater.manifest` uses an HTTPS `GET` request for both a static JSON file and
a RESTful API. The two delivery styles use the same manifest v3 response schema.

### Static JSON file

Publish the manifest payload, or its signed envelope, as an immutable file on a
CDN, object store, or web server. The repository includes a complete payload at
[`doc/examples/update-manifest-v3.json`](doc/examples/update-manifest-v3.json).
Here, static JSON means a document hosted over HTTPS. `AppUpdater.manifest`
does not read local `file://` URLs or Flutter asset paths. A trusted adapter can
instead construct an `UpdateManifest` and use `UpdateSource.staticManifest`.

```dart
final updater = AppUpdater.manifest(
  manifestUrl: Uri.parse(
    'https://cdn.example.com/releases/app-updates.json',
  ),
  expectedAppId: 'com.example.app',
  installedVersion: '1.0.0',
  platform: defaultTargetPlatform,
  architecture: 'arm64',
  channel: 'stable',
  downloadDirectory: downloadDirectory,
  signaturePolicy: ManifestSignaturePolicy.required(
    trustedPublicKeys: trustedManifestPublicKeys,
  ),
);

final result = await updater.checkAndPrepare();
```

### RESTful API

A REST endpoint can select releases dynamically from request parameters. The
default fetcher sends a `GET`, so put selection inputs in the URL and optional
credentials in `headers`:

```http
GET /v1/apps/com.example.app/updates?platform=android&architecture=arm64&channel=stable&installedVersion=1.0.0 HTTP/1.1
Host: updates.example.com
Accept: application/json
Authorization: Bearer <short-lived-token>
```

```dart
final endpoint = Uri.https(
  'updates.example.com',
  '/v1/apps/com.example.app/updates',
  {
    'platform': 'android',
    'architecture': 'arm64',
    'channel': 'stable',
    'installedVersion': '1.0.0',
  },
);

final updater = AppUpdater.manifest(
  manifestUrl: endpoint,
  expectedAppId: 'com.example.app',
  headers: {
    'Accept': 'application/json',
    'Authorization': 'Bearer $accessToken',
  },
  installedVersion: '1.0.0',
  platform: defaultTargetPlatform,
  architecture: 'arm64',
  channel: 'stable',
  downloadDirectory: downloadDirectory,
  signaturePolicy: ManifestSignaturePolicy.required(
    trustedPublicKeys: trustedManifestPublicKeys,
  ),
);

final result = await updater.checkAndPrepare();
```

The default transport requires HTTP 200, accepts at most 1 MiB, and parses the
response body directly as either a manifest v3 object or a signed envelope. Do
not wrap it in `{ "data": ... }`, `{ "result": ... }`, or another business
response object. If an existing API cannot return that shape, provide a custom
`ManifestFetcher`. Caller headers are removed after a cross-origin redirect.

For either delivery style, a bare response is accepted only for official-store
and Android-market actions when `ManifestSignaturePolicy.optional` is used.
Self-hosted package or installer actions require a valid Ed25519 envelope.
Signing every production response is the recommended policy.

## Manifest v3 response schema

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
          "packageSizeBytes": 25600000,
          "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        }
      ]
    }
  ]
}
```

### Manifest fields: required and optional

Root object:

| Field | Required | Type and constraints | Meaning |
| --- | --- | --- | --- |
| `schemaVersion` | Yes | Integer, exactly `3` | Selects the manifest contract. |
| `appId` | Yes | Non-empty string | Must equal the client's `expectedAppId`. |
| `channel` | Yes | Non-empty string | Default channel inherited by releases that omit `channel`. |
| `releases` | Yes | Array | Ordered release candidates; it may be empty when no release exists. |

Each item in `releases`:

| Field | Required | Type and constraints | Meaning |
| --- | --- | --- | --- |
| `version` | Yes | Semantic-version string | Used as the primary update ordering key. |
| `platform` | Yes | `android`, `ios`, `macos`, or `windows` for the stable package | Must exactly match the client platform. |
| `releaseNotes` | Yes | Non-empty string | Publisher text shown by the host application. |
| `actions` | Yes | Non-empty array | Delivery choices in publisher order; the first allowed supported action is recommended. |
| `buildNumber` | No | Non-negative ASCII decimal integer string | Breaks ties when semantic versions are equal; leading zeroes are allowed and the value is parsed as an integer. |
| `channel` | No | Non-empty string | Overrides the root `channel` for this release. |
| `architecture` | No | Non-empty string | Exact runtime architecture; omit it for a universal release. |
| `releasedAt` | No | ISO-8601 string | Publisher release timestamp. |
| `policy` | No | Object | Update recommendation and minimum supported version. |

Optional `policy` fields:

| Field | Required | Type and constraints | Meaning |
| --- | --- | --- | --- |
| `level` | No | `optional`, `recommended`, or `required`; defaults to `optional` | How strongly the host should present the update. |
| `minSupportedVersion` | No | Semantic-version string no greater than this release's `version` | Makes the update required when the installed version is older. |

Action-specific fields:

Every action object requires a non-empty `type` discriminator. The value selects
one row below; the remaining required and optional fields are exact for that
action type.

| `type` | Required fields | Optional fields | Notes |
| --- | --- | --- | --- |
| `openStore` | `store`, `storeUrl` | None | `store` is `googlePlay`, `appStore`, or `macAppStore`; the remote URL must use the matching official host. |
| `openAndroidMarket` | `market`, `targetPackageName` | `fallbackUrl` | `targetPackageName` must equal the manifest `appId`. |
| `downloadPackage` | `packageUrl`, `packageType`, `packageSizeBytes`, `sha256` | None | Exact positive size and a 64-hex-character SHA-256 are mandatory. |
| `downloadAndInstallPackage` | `packageUrl`, `packageType`, `packageSizeBytes`, `sha256` | None | Runtime installation supports Android APKs only. |
| `openInstaller` | `installerUrl`, `installerType`, `installerSizeBytes`, `sha256` | None | Stable types are Windows `msix`/`msi`/`exe` and macOS `dmg`/`zip`. |
| `installPackage` | `packagePath` | `packageType` (defaults to `apk`) | Trusted local typed code only; remote manifests reject this action. |

`buildNumber` is optional. When present it must be a non-negative ASCII decimal
integer string (`0`, `42`, and `00042` are valid). Leading zeroes are allowed
and the value is parsed as an integer. Any other value rejects the entire
response. `minSupportedVersion`, when present, must be less than or equal to
that release's `version`.

Manifest v3 is an exact allowlist at every object boundary: the root, each
release, policy, and action object reject unknown fields. There is no
`extensions` escape hatch. The signed envelope also rejects extra fields.
Adding a field requires a new schema version. A v3 response with any unknown,
mis-typed, or invalid field rejects the entire response rather than ignoring
the field.

All remote URLs must be absolute. Remote policy further requires HTTPS, exact
positive artifact sizes, and a 64-character hexadecimal `sha256` for every
self-hosted artifact. Removed earlier-schema field names are rejected anywhere
in the document; use only the v3 fields listed above.

The parser also recognizes `linux`/`fuchsia` platform values and
`appImage`/`deb`/`rpm` installer values for typed model compatibility. They are
not stable default executor or plugin-registration support in v3 and can end in
`NO_SUPPORTED_ACTION`; the platform matrix below is the executable contract.

This JSON is the signed payload, not the network response. For self-hosted
actions, encode the exact payload bytes in a versioned Ed25519 envelope with
`keyId`, `issuedAt`, `expiresAt`, `payload`, and `signature`. Rotate keys by
shipping an overlap period in which the host trusts both key IDs. Bare remote
manifests are accepted only for official-store-only actions when the host uses
the optional signature policy.

Signed network response fields are all required. The envelope is also an exact
allowlist; any extra field rejects the response:

```json
{
  "format": "flutter_app_updater.ed25519.v1",
  "keyId": "release-2026-01",
  "issuedAt": "2026-07-14T12:00:00Z",
  "expiresAt": "2026-07-15T12:00:00Z",
  "payload": "<Base64 of the exact manifest JSON bytes>",
  "signature": "<Base64 Ed25519 signature>"
}
```

| Field | Required | Type and constraints |
| --- | --- | --- |
| `format` | Yes | Exactly `flutter_app_updater.ed25519.v1`. |
| `keyId` | Yes | Non-empty key identifier present in `trustedPublicKeys`. |
| `issuedAt` | Yes | ISO-8601 validity-window start. |
| `expiresAt` | Yes | ISO-8601 validity-window end; later than `issuedAt` and within the configured maximum validity. |
| `payload` | Yes | Base64 of the exact manifest v3 JSON bytes. |
| `signature` | Yes | Base64 Ed25519 signature over the package's domain-separated input. |

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
  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}
```

Use separate actions when your app wants to download now and install later:

```json
{
  "type": "downloadPackage",
  "packageUrl": "https://example.com/app.apk",
  "packageType": "apk",
  "packageSizeBytes": 25600000,
  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}
```

Remote manifests cannot request installation of an arbitrary local path. A
host may construct an `InstallPackageAction` only at a trusted typed boundary,
for example after its own verified download. Android revalidates expected size,
SHA-256, package identity, and signing lineage immediately before installer
handoff.

## Advanced Android-only background downloads

`AndroidBackgroundDownloadManager` is an opt-in API for one durable,
user-visible APK transfer at a time. It is separate from the default
`AppUpdater` action flow and is available only on Android.

Foreground downloads and Android durable downloads have different URL
persistence contracts. The foreground action flow may use an HTTPS artifact URL
with short-lived query credentials. The foreground checkpoint stores only a
SHA-256 URL fingerprint, never the raw URL or query token. Android durable
`start()` accepts only a stable, credential-free entry URL with no userinfo,
query, or fragment. The durable task record persists only that stable entry URL.

For expiring download credentials, configure the stable entry endpoint to
return an HTTPS redirect to a short-lived signed URL. The signed redirect target
exists only as the current process's in-memory transport target and is never
persisted. Each redirect target is revalidated, and every HTTPS-to-HTTP
downgrade is rejected.

A start request must come from a visible, user-initiated host flow and must
include that stable HTTPS URL, the exact content length, and a lowercase or
uppercase SHA-256 digest:

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

Durable task state is stored under Android `noBackupFilesDir`; APK and partial
artifacts are stored under the app-private `filesDir` exposed by the package's
FileProvider. On first use after upgrading, tasks and artifacts from the
pre-release single-root layout are reset instead of migrated. Hosts must treat
those old tasks as no longer resumable and start a fresh user-visible transfer.

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
background execution on any OEM family.

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
  "installerSizeBytes": 82000000,
  "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
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
| macOS | Stable | Not applicable | Stable | Unsupported | Stable |
| Windows | Unsupported | Not applicable | Stable | Unsupported | Stable |

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

The supported floor is Flutter 3.22.0. The reusable full gate tests that exact
version and current stable Flutter, validates root/example analysis and tests,
enforces total and critical coverage at 80%, generates API docs, builds every
registered platform example, runs Android and Windows native tests, and checks a
clean publish archive.

```bash
flutter pub get
(cd example && flutter pub get)
dart format --output=none --set-exit-if-changed lib test example/lib example/test example/integration_test tool
flutter analyze --no-pub
flutter test --coverage --no-pub
dart doc --dry-run
(cd example && flutter analyze --no-pub && flutter test --no-pub)
(cd example && flutter build apk --debug --no-pub)
bash tool/ci/publish_dry_run.sh
```

The Android-native reliability gate runs from `example/android`:

```bash
../../android/gradlew :flutter_app_updater:testDebugUnitTest :flutter_app_updater:lintDebug :app:processDebugMainManifest
```

For a release, update `pubspec.yaml` and `CHANGELOG.md`, merge the release commit
to `main`, and tag that exact commit as `v<version>`. The publish workflow runs
the same full gate and requires tag, version, CHANGELOG, and `origin/main`
ancestry to agree. Validate locally with:

```bash
version="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
dart run tool/ci/verify_release_metadata.dart --tag "v$version"
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for development checks and
[SECURITY.md](SECURITY.md) for private vulnerability reporting.

## License

Apache-2.0
