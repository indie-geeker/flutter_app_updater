# Flutter App Updater v3 Redesign Design

## Goal

Redesign `flutter_app_updater` as a v3 breaking release that supports official store updates, Chinese Android market jumps, direct package updates, and desktop installer updates without preserving the v2 API or field names.

## Context

The current v2 API is centered on direct package downloads:

- `FlutterAppUpdater`
- `UpdateInfo`
- `downloadUrl`
- `newVersion`
- `changelog`
- `isForceUpdate`
- `md5`

That model works for self-hosted Android APK updates, but it does not describe Play Store updates, App Store jumps, Chinese Android market jumps, or desktop installers cleanly. In v3, the central concept should be an update candidate with one or more explicit actions, not a single download URL.

## Design Decision

Use a breaking v3 redesign based on:

- `AppUpdater`
- `UpdateSource`
- `UpdateCandidate`
- `UpdatePolicy`
- `UpdateAction`

Do not preserve old v2 API compatibility. Remove legacy naming when it makes the public API less clear.

## Alternatives Considered

### Extend v2

Keep `FlutterAppUpdater`, `UpdateInfo`, and `downloadUrl`, then add optional fields for stores and desktop installers.

This has the lowest migration cost, but it keeps the package tied to APK download semantics. Store updates and desktop installers would become edge cases bolted onto an old model.

### v3 Breaking Redesign

Replace v2 API with an update-source and action-oriented model.

This is the recommended path. It gives each update path a precise action:

- open official store
- open Chinese Android market
- run Play In-App Update
- download package
- open desktop installer

### Split Into Multiple Packages

Create separate packages such as `flutter_app_updater_core`, `flutter_app_updater_store`, and `flutter_app_updater_desktop`.

This may be useful later, but it adds release and maintenance overhead before the v3 API has stabilized.

## Recommended Architecture

```dart
final updater = AppUpdater(
  source: UpdateSource.manifest(
    manifestUrl: Uri.parse('https://example.com/app-updates.json'),
  ),
);

final result = await updater.check();

if (result.hasUpdate) {
  await updater.perform(result.recommendedAction);
}
```

The public workflow is:

1. Configure an `UpdateSource`.
2. Check for an `UpdateCandidate`.
3. Select an `UpdateAction`.
4. Perform that action.

## Core Types

```dart
class UpdateCandidate {
  final String version;
  final String? buildNumber;
  final String channel;
  final TargetPlatform platform;
  final String? architecture;
  final String releaseNotes;
  final DateTime? releasedAt;
  final UpdatePolicy policy;
  final List<UpdateAction> actions;
}
```

```dart
class UpdatePolicy {
  final UpdatePolicyLevel level;
  final String? minSupportedVersion;
}
```

```dart
enum UpdatePolicyLevel {
  optional,
  recommended,
  required,
}
```

```dart
sealed class UpdateAction {
  const UpdateAction();
}
```

## Action Types and Field Names

Avoid generic names such as `artifactUri` in the public API and manifest. Use direct field names that match the action.

### Official Store

```dart
class OpenStoreAction extends UpdateAction {
  final StoreKind store;
  final Uri storeUrl;
}
```

Use for:

- Apple App Store
- Mac App Store
- Google Play fallback page

Manifest example:

```json
{
  "type": "openStore",
  "store": "appStore",
  "storeUrl": "https://apps.apple.com/app/id123456789"
}
```

### Google Play In-App Updates

```dart
class PlayInAppUpdateAction extends UpdateAction {
  final PlayUpdateMode mode;
}
```

Use for Android apps distributed through Google Play.

Manifest example:

```json
{
  "type": "playInAppUpdate",
  "mode": "immediate"
}
```

### Chinese Android Markets

```dart
class OpenAndroidMarketAction extends UpdateAction {
  final AndroidMarketKind market;
  final String targetPackageName;
  final Uri? fallbackUrl;
}
```

Use for:

- Huawei AppGallery
- Honor App Market
- Xiaomi GetApps / Mi Market
- OPPO App Market
- vivo App Store
- Meizu App Store
- Tencent MyApp
- generic Android market fallback

Manifest example:

```json
{
  "type": "openAndroidMarket",
  "market": "xiaomi",
  "targetPackageName": "com.example.app",
  "fallbackUrl": "https://app.mi.com/details?id=com.example.app"
}
```

Native Android implementation should use `Intent.ACTION_VIEW`, store-specific package names, Android 11+ `<queries>`, and a fallback chain.

### Direct Package Download

```dart
class DownloadPackageAction extends UpdateAction {
  final Uri packageUrl;
  final PackageType packageType;
  final int? packageSizeBytes;
  final String sha256;
  final String? signature;
}
```

Use for direct package distribution, especially Android APK self-hosted updates.

Manifest example:

```json
{
  "type": "downloadPackage",
  "packageUrl": "https://example.com/app.apk",
  "packageType": "apk",
  "packageSizeBytes": 25600000,
  "sha256": "..."
}
```

`downloadUrl` should not be used in v3. `packageUrl` is clearer because it describes what is downloaded.

### Desktop Installer

```dart
class OpenInstallerAction extends UpdateAction {
  final Uri installerUrl;
  final InstallerType installerType;
  final int? installerSizeBytes;
  final String sha256;
  final String? signature;
}
```

Use for desktop installers:

- Windows: `msix`, `msi`, `exe`
- macOS: `dmg`, `zip`
- Linux: `appImage`, `deb`, `rpm`

Manifest example:

```json
{
  "type": "openInstaller",
  "installerUrl": "https://example.com/app.dmg",
  "installerType": "dmg",
  "installerSizeBytes": 82000000,
  "sha256": "..."
}
```

Desktop v3 should start with safe download and opening the installer. It should not promise silent replacement or background self-update.

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

## Field Naming Rules

Use direct names:

- `version`, not `newVersion`
- `releaseNotes`, not `changelog`
- `releasedAt`, not `publishDate`
- `packageUrl`, not `downloadUrl`
- `installerUrl`, not `artifactUri`
- `storeUrl`, not `targetUrl`
- `targetPackageName`, not `package`
- `packageSizeBytes`, not `fileSize`
- `sha256`, not `md5`
- `policy.level`, not `isForceUpdate`

Use action-scoped names instead of generic global names. A store action has `storeUrl`; a package action has `packageUrl`; an installer action has `installerUrl`.

## Store Update Support

### Google Play

Support two paths:

- `PlayInAppUpdateAction` for Play In-App Updates.
- `OpenStoreAction` as a Play Store fallback.

Play In-App Updates should be optional and Android-only.

### Apple App Store and Mac App Store

Support store opening only:

- external App Store URL
- StoreKit product page where practical

Do not claim iOS in-app installation support.

### Chinese Android Markets

Support as `OpenAndroidMarketAction`.

The initial supported markets should be:

- Huawei
- Honor
- Xiaomi
- OPPO
- vivo
- Meizu
- Tencent MyApp
- generic Android market

Each market implementation should have:

- market package name
- URI template
- optional HTTPS fallback
- availability check
- structured error when unavailable

The package should promise best-effort store jumping, not automatic update installation.

## Direct Package Update Support

Keep the current direct update capability, but rebuild the public API around `DownloadPackageAction`.

Required improvements:

- SHA-256 verification
- optional signed manifest or package signature
- ETag and Last-Modified checks for resume safety
- Range fallback handling
- atomic package replacement after verification
- structured download and verification errors

## Desktop Update Support

Desktop v3 should support safe download and opening installers.

Supported first version:

- Windows: `msix`, `msi`, `exe`
- macOS: `dmg`, `zip`
- Linux: `appImage`, `deb`, `rpm`

Out of scope for v3:

- silent replacement
- binary diff update
- background daemon
- automatic relaunch

These can be considered for a later version after the v3 model is stable.

## Error Handling

Use structured errors:

- `MANIFEST_FETCH_FAILED`
- `MANIFEST_INVALID`
- `NO_MATCHING_RELEASE`
- `NO_SUPPORTED_ACTION`
- `STORE_NOT_AVAILABLE`
- `MARKET_NOT_AVAILABLE`
- `PLAY_IN_APP_UPDATE_UNAVAILABLE`
- `PACKAGE_DOWNLOAD_FAILED`
- `PACKAGE_HASH_MISMATCH`
- `PACKAGE_SIGNATURE_INVALID`
- `INSTALLER_OPEN_FAILED`
- `PLATFORM_NOT_SUPPORTED`

Avoid returning `null` for failures.

## Testing Strategy

Unit tests:

- manifest parsing
- action parsing
- field validation
- platform filtering
- architecture filtering
- channel filtering
- policy evaluation
- version comparison
- fallback action selection

Android tests:

- store package detection
- generated market intent data
- fallback order
- package visibility metadata

Download tests:

- SHA-256 success and failure
- Range resume success
- Range unsupported fallback
- stale partial file detection

Desktop tests:

- installer type parsing
- unsupported installer rejection
- platform-specific action selection

## Documentation Plan

Rewrite README around v3 concepts:

1. What this package does.
2. Official store updates.
3. Chinese Android market jumps.
4. Direct package updates.
5. Desktop installer updates.
6. Manifest v3 schema.
7. Platform support matrix.
8. Security model.
9. Migration note: v3 is not API-compatible with v2.

## Implementation Phases

### Phase 1: Core v3 Model

Create the new core types and remove old public exports.

Deliverables:

- `AppUpdater`
- `UpdateSource`
- `UpdateCandidate`
- `UpdatePolicy`
- `UpdateAction`
- `UpdateCheckResult`
- v3 public export file

### Phase 2: Manifest v3

Implement manifest parsing, validation, and release selection.

Deliverables:

- schema parser
- model validation
- platform/channel/architecture filtering
- tests for invalid manifests

### Phase 3: Store Actions

Implement official store and market jumps.

Deliverables:

- `OpenStoreAction`
- `PlayInAppUpdateAction`
- `OpenAndroidMarketAction`
- Android native market opener
- iOS/macOS store opener

### Phase 4: Direct Package Updates

Rebuild package download around `DownloadPackageAction`.

Deliverables:

- SHA-256 verification
- resumable download safety checks
- Android APK installer action
- structured errors

### Phase 5: Desktop Installer Updates

Implement safe installer download and opening.

Deliverables:

- `OpenInstallerAction`
- installer type validation
- Windows/macOS/Linux opener stubs or implementations
- desktop documentation

### Phase 6: Release Tooling

Add a CLI for manifest generation and validation.

Deliverables:

- manifest generator
- SHA-256 calculator
- manifest verifier
- remote file availability checker

## Approval Criteria

The v3 design is ready when:

- no public API depends on `downloadUrl`
- store, market, package, and installer updates are modeled as separate actions
- manifest schema is readable without package-internal vocabulary
- failures are structured and never collapsed into `null`
- README clearly states which platforms can update through stores, package downloads, or desktop installers

