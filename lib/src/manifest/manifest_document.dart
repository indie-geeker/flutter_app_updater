// ignore_for_file: public_member_api_docs

/// Package-owned platform values parsed from the manifest wire format.
enum ManifestPlatform {
  android,
  ios,
  macos,
  windows,
  linux,
  fuchsia,
}

/// Publisher recommendation levels represented by a manifest document.
enum ManifestPolicyLevel {
  optional,
  recommended,
  required,
}

/// Official application stores represented by a manifest document.
enum ManifestStoreKind {
  appStore,
  macAppStore,
  googlePlay,
}

/// Android application markets represented by a manifest document.
enum ManifestAndroidMarketKind {
  huawei,
  honor,
  xiaomi,
  oppo,
  vivo,
  meizu,
  tencentMyApp,
  generic,
}

/// Android package formats represented by a manifest document.
enum ManifestPackageType {
  apk,
  aab,
}

/// Desktop installer formats represented by a manifest document.
enum ManifestInstallerType {
  msix,
  msi,
  exe,
  dmg,
  zip,
  appImage,
  deb,
  rpm,
}

/// Immutable, Flutter-independent representation of one v3 manifest.
final class ManifestDocument {
  final int schemaVersion;
  final String appId;
  final String channel;
  final List<ManifestReleaseDocument> releases;

  ManifestDocument({
    required this.schemaVersion,
    required this.appId,
    required this.channel,
    required Iterable<ManifestReleaseDocument> releases,
  }) : releases = List.unmodifiable(releases);
}

/// Immutable, Flutter-independent representation of one manifest release.
final class ManifestReleaseDocument {
  final String version;
  final String? buildNumber;
  final String channel;
  final ManifestPlatform platform;
  final String? architecture;
  final String releaseNotes;
  final DateTime? releasedAt;
  final ManifestPolicyDocument policy;
  final List<ManifestAction> actions;

  ManifestReleaseDocument({
    required this.version,
    this.buildNumber,
    required this.channel,
    required this.platform,
    this.architecture,
    required this.releaseNotes,
    this.releasedAt,
    required this.policy,
    required Iterable<ManifestAction> actions,
  }) : actions = List.unmodifiable(actions);
}

/// Immutable publisher policy parsed from a manifest release.
final class ManifestPolicyDocument {
  final ManifestPolicyLevel level;
  final String? minSupportedVersion;

  const ManifestPolicyDocument({
    this.level = ManifestPolicyLevel.optional,
    this.minSupportedVersion,
  });
}

/// Flutter-independent representation of one manifest delivery action.
sealed class ManifestAction {
  const ManifestAction();
}

/// Official-store action parsed from a manifest document.
final class ManifestOpenStoreAction extends ManifestAction {
  final ManifestStoreKind store;
  final Uri storeUrl;

  const ManifestOpenStoreAction({
    required this.store,
    required this.storeUrl,
  });
}

/// Android-market action parsed from a manifest document.
final class ManifestOpenAndroidMarketAction extends ManifestAction {
  final ManifestAndroidMarketKind market;
  final String targetPackageName;
  final Uri? fallbackUrl;

  const ManifestOpenAndroidMarketAction({
    required this.market,
    required this.targetPackageName,
    this.fallbackUrl,
  });
}

/// Remote package download action parsed from a manifest document.
final class ManifestDownloadPackageAction extends ManifestAction {
  final Uri packageUrl;
  final ManifestPackageType packageType;
  final int packageSizeBytes;
  final String sha256;

  const ManifestDownloadPackageAction({
    required this.packageUrl,
    required this.packageType,
    required this.packageSizeBytes,
    required this.sha256,
  });
}

/// Local package installation action parsed from a manifest document.
final class ManifestInstallPackageAction extends ManifestAction {
  final String packagePath;
  final ManifestPackageType packageType;

  const ManifestInstallPackageAction({
    required this.packagePath,
    required this.packageType,
  });
}

/// Remote package download-and-install action parsed from a manifest document.
final class ManifestDownloadAndInstallPackageAction extends ManifestAction {
  final Uri packageUrl;
  final ManifestPackageType packageType;
  final int packageSizeBytes;
  final String sha256;

  const ManifestDownloadAndInstallPackageAction({
    required this.packageUrl,
    required this.packageType,
    required this.packageSizeBytes,
    required this.sha256,
  });
}

/// Remote desktop-installer action parsed from a manifest document.
final class ManifestOpenInstallerAction extends ManifestAction {
  final Uri installerUrl;
  final ManifestInstallerType installerType;
  final int installerSizeBytes;
  final String sha256;

  const ManifestOpenInstallerAction({
    required this.installerUrl,
    required this.installerType,
    required this.installerSizeBytes,
    required this.sha256,
  });
}
