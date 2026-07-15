import 'package:flutter/foundation.dart';

import '../actions/update_action.dart';
import '../models/update_candidate.dart';
import '../models/update_policy.dart';
import 'manifest_document.dart';
import 'manifest_document_parser.dart';
import 'manifest_validator.dart';
import 'update_manifest.dart';

export 'manifest_validator.dart' show ManifestParseException;
export 'update_manifest.dart' show UpdateManifest;

/// Adapts a pure Dart manifest document into immutable Flutter v3 models.
class ManifestParser {
  /// Structural validator run before any field is interpreted.
  final ManifestValidator validator;

  /// Creates a parser with an injectable validator.
  const ManifestParser({
    this.validator = const ManifestValidator(),
  });

  /// Validates and parses [json].
  ///
  /// Throws [ManifestParseException] for invalid schema, enum values, URLs,
  /// versions, timestamps, or action metadata.
  UpdateManifest parse(Map<String, Object?> json) {
    final document = ManifestDocumentParser(validator: validator).parse(json);
    return UpdateManifest(
      schemaVersion: document.schemaVersion,
      appId: document.appId,
      channel: document.channel,
      releases: document.releases.map(_adaptRelease).toList(growable: false),
    );
  }

  UpdateCandidate _adaptRelease(ManifestReleaseDocument release) {
    return UpdateCandidate(
      version: release.version,
      buildNumber: release.buildNumber,
      channel: release.channel,
      platform: _adaptPlatform(release.platform),
      architecture: release.architecture,
      releaseNotes: release.releaseNotes,
      releasedAt: release.releasedAt,
      policy: _adaptPolicy(release.policy),
      actions: release.actions.map(_adaptAction).toList(growable: false),
    );
  }

  TargetPlatform _adaptPlatform(ManifestPlatform platform) {
    return switch (platform) {
      ManifestPlatform.android => TargetPlatform.android,
      ManifestPlatform.ios => TargetPlatform.iOS,
      ManifestPlatform.macos => TargetPlatform.macOS,
      ManifestPlatform.windows => TargetPlatform.windows,
      ManifestPlatform.linux => TargetPlatform.linux,
      ManifestPlatform.fuchsia => TargetPlatform.fuchsia,
    };
  }

  UpdatePolicy _adaptPolicy(ManifestPolicyDocument policy) {
    return UpdatePolicy(
      level: switch (policy.level) {
        ManifestPolicyLevel.optional => UpdatePolicyLevel.optional,
        ManifestPolicyLevel.recommended => UpdatePolicyLevel.recommended,
        ManifestPolicyLevel.required => UpdatePolicyLevel.required,
      },
      minSupportedVersion: policy.minSupportedVersion,
    );
  }

  UpdateAction _adaptAction(ManifestAction action) {
    return switch (action) {
      ManifestOpenStoreAction() => OpenStoreAction(
          store: switch (action.store) {
            ManifestStoreKind.appStore => StoreKind.appStore,
            ManifestStoreKind.macAppStore => StoreKind.macAppStore,
            ManifestStoreKind.googlePlay => StoreKind.googlePlay,
          },
          storeUrl: action.storeUrl,
        ),
      ManifestOpenAndroidMarketAction() => OpenAndroidMarketAction(
          market: switch (action.market) {
            ManifestAndroidMarketKind.huawei => AndroidMarketKind.huawei,
            ManifestAndroidMarketKind.honor => AndroidMarketKind.honor,
            ManifestAndroidMarketKind.xiaomi => AndroidMarketKind.xiaomi,
            ManifestAndroidMarketKind.oppo => AndroidMarketKind.oppo,
            ManifestAndroidMarketKind.vivo => AndroidMarketKind.vivo,
            ManifestAndroidMarketKind.meizu => AndroidMarketKind.meizu,
            ManifestAndroidMarketKind.tencentMyApp =>
              AndroidMarketKind.tencentMyApp,
            ManifestAndroidMarketKind.generic => AndroidMarketKind.generic,
          },
          targetPackageName: action.targetPackageName,
          fallbackUrl: action.fallbackUrl,
        ),
      ManifestDownloadPackageAction() => DownloadPackageAction(
          packageUrl: action.packageUrl,
          packageType: _adaptPackageType(action.packageType),
          packageSizeBytes: action.packageSizeBytes,
          sha256: action.sha256,
        ),
      ManifestInstallPackageAction() => InstallPackageAction(
          packagePath: action.packagePath,
          packageType: _adaptPackageType(action.packageType),
        ),
      ManifestDownloadAndInstallPackageAction() =>
        DownloadAndInstallPackageAction(
          packageUrl: action.packageUrl,
          packageType: _adaptPackageType(action.packageType),
          packageSizeBytes: action.packageSizeBytes,
          sha256: action.sha256,
        ),
      ManifestOpenInstallerAction() => OpenInstallerAction(
          installerUrl: action.installerUrl,
          installerType: switch (action.installerType) {
            ManifestInstallerType.msix => InstallerType.msix,
            ManifestInstallerType.msi => InstallerType.msi,
            ManifestInstallerType.exe => InstallerType.exe,
            ManifestInstallerType.dmg => InstallerType.dmg,
            ManifestInstallerType.zip => InstallerType.zip,
            ManifestInstallerType.appImage => InstallerType.appImage,
            ManifestInstallerType.deb => InstallerType.deb,
            ManifestInstallerType.rpm => InstallerType.rpm,
          },
          installerSizeBytes: action.installerSizeBytes,
          sha256: action.sha256,
        ),
    };
  }

  PackageType _adaptPackageType(ManifestPackageType packageType) {
    return switch (packageType) {
      ManifestPackageType.apk => PackageType.apk,
      ManifestPackageType.aab => PackageType.aab,
    };
  }
}
