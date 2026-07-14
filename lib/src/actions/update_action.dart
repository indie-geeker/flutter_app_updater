/// Official application stores that can receive an update action.
enum StoreKind {
  /// Apple's iOS and iPadOS App Store.
  appStore,

  /// Apple's Mac App Store.
  macAppStore,

  /// Google Play for Android applications.
  googlePlay,
}

/// Android application markets supported by [OpenAndroidMarketAction].
enum AndroidMarketKind {
  /// Huawei AppGallery.
  huawei,

  /// HONOR App Market.
  honor,

  /// Xiaomi GetApps.
  xiaomi,

  /// OPPO App Market.
  oppo,

  /// vivo App Store.
  vivo,

  /// Meizu App Store.
  meizu,

  /// Tencent MyApp.
  tencentMyApp,

  /// A host-provided Android market configuration.
  generic,
}

/// Android package formats represented by package actions.
enum PackageType {
  /// An installable Android Package Kit.
  apk,

  /// An Android App Bundle, which is downloadable but not locally installable.
  aab,
}

/// Desktop installer and package formats supported by installer actions.
enum InstallerType {
  /// A Windows MSIX application package.
  msix,

  /// A Windows Installer package.
  msi,

  /// A Windows executable installer.
  exe,

  /// A macOS disk image.
  dmg,

  /// A ZIP archive delivered for host-managed installation.
  zip,

  /// A Linux AppImage executable.
  appImage,

  /// A Debian package.
  deb,

  /// An RPM package.
  rpm,
}

/// A side-effect-free description of one way to deliver an update.
///
/// Manifest order is significant: the first supported action is recommended.
sealed class UpdateAction {
  /// Creates an update action description.
  const UpdateAction();
}

/// Opens a verified official-store URL after explicit execution.
class OpenStoreAction extends UpdateAction {
  /// Store whose host policy is enforced for [storeUrl].
  final StoreKind store;

  /// Absolute HTTPS destination in the selected official store.
  final Uri storeUrl;

  /// Creates an official-store action.
  const OpenStoreAction({
    required this.store,
    required this.storeUrl,
  });
}

/// Opens a configured Android market for the manifest application.
class OpenAndroidMarketAction extends UpdateAction {
  /// Market registry entry to invoke.
  final AndroidMarketKind market;

  /// Android package name, which remote manifests must bind to their app ID.
  final String targetPackageName;

  /// Optional absolute HTTPS fallback when the market app is unavailable.
  final Uri? fallbackUrl;

  /// Creates an Android-market action.
  const OpenAndroidMarketAction({
    required this.market,
    required this.targetPackageName,
    this.fallbackUrl,
  });
}

/// Downloads a package whose exact length and SHA-256 are known in advance.
class DownloadPackageAction extends UpdateAction {
  /// Trusted HTTPS package URL.
  final Uri packageUrl;

  /// Format of the downloaded package.
  final PackageType packageType;

  /// Exact expected package length in bytes.
  final int packageSizeBytes;

  /// Expected lowercase or uppercase 64-character SHA-256 digest.
  final String sha256;

  /// Creates a verified download action.
  const DownloadPackageAction({
    required this.packageUrl,
    required this.packageType,
    required this.packageSizeBytes,
    required this.sha256,
  });
}

/// Requests installation of a local Android package.
///
/// [packageSizeBytes] and [sha256] must either both be present or both absent.
/// Android always verifies package identity and signing lineage immediately
/// before installer handoff, and rechecks integrity when metadata is supplied.
class InstallPackageAction extends UpdateAction {
  /// Local package path passed to the Android verification boundary.
  final String packagePath;

  /// Package format; only [PackageType.apk] is locally installable.
  final PackageType packageType;

  /// Optional exact expected size, paired with [sha256].
  final int? packageSizeBytes;

  /// Optional expected SHA-256, paired with [packageSizeBytes].
  final String? sha256;

  /// Creates a local package installation request.
  const InstallPackageAction({
    required this.packagePath,
    this.packageType = PackageType.apk,
    this.packageSizeBytes,
    this.sha256,
  }) : assert(
          (packageSizeBytes == null) == (sha256 == null),
          'packageSizeBytes and sha256 must be provided together.',
        );
}

/// Downloads, verifies, and then installs an Android APK.
class DownloadAndInstallPackageAction extends UpdateAction {
  /// Trusted HTTPS APK URL.
  final Uri packageUrl;

  /// Package format; execution supports APK only.
  final PackageType packageType;

  /// Exact expected download and pre-install file length.
  final int packageSizeBytes;

  /// Expected SHA-256 checked after download and before installation.
  final String sha256;

  /// Creates a verified Android download-and-install action.
  const DownloadAndInstallPackageAction({
    required this.packageUrl,
    required this.packageType,
    required this.packageSizeBytes,
    required this.sha256,
  });
}

/// Downloads, verifies, and opens a desktop installer.
class OpenInstallerAction extends UpdateAction {
  /// Trusted HTTPS installer URL.
  final Uri installerUrl;

  /// Installer format used for platform capability selection.
  final InstallerType installerType;

  /// Exact expected installer length.
  final int installerSizeBytes;

  /// Expected 64-character SHA-256 digest.
  final String sha256;

  /// Creates a verified desktop-installer action.
  const OpenInstallerAction({
    required this.installerUrl,
    required this.installerType,
    required this.installerSizeBytes,
    required this.sha256,
  });
}
