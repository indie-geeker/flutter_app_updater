enum StoreKind {
  appStore,
  macAppStore,
  googlePlay,
}

enum AndroidMarketKind {
  huawei,
  honor,
  xiaomi,
  oppo,
  vivo,
  meizu,
  tencentMyApp,
  generic,
}

enum PlayUpdateMode {
  immediate,
  flexible,
}

enum PackageType {
  apk,
  aab,
}

enum InstallerType {
  msix,
  msi,
  exe,
  dmg,
  zip,
  appImage,
  deb,
  rpm,
}

sealed class UpdateAction {
  const UpdateAction();
}

class OpenStoreAction extends UpdateAction {
  final StoreKind store;
  final Uri storeUrl;

  const OpenStoreAction({
    required this.store,
    required this.storeUrl,
  });
}

class PlayInAppUpdateAction extends UpdateAction {
  final PlayUpdateMode mode;

  const PlayInAppUpdateAction({
    required this.mode,
  });
}

class OpenAndroidMarketAction extends UpdateAction {
  final AndroidMarketKind market;
  final String targetPackageName;
  final Uri? fallbackUrl;

  const OpenAndroidMarketAction({
    required this.market,
    required this.targetPackageName,
    this.fallbackUrl,
  });
}

class DownloadPackageAction extends UpdateAction {
  final Uri packageUrl;
  final PackageType packageType;
  final int? packageSizeBytes;
  final String sha256;
  final String? signature;

  const DownloadPackageAction({
    required this.packageUrl,
    required this.packageType,
    this.packageSizeBytes,
    required this.sha256,
    this.signature,
  });
}

class OpenInstallerAction extends UpdateAction {
  final Uri installerUrl;
  final InstallerType installerType;
  final int? installerSizeBytes;
  final String sha256;
  final String? signature;

  const OpenInstallerAction({
    required this.installerUrl,
    required this.installerType,
    this.installerSizeBytes,
    required this.sha256,
    this.signature,
  });
}
