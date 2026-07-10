import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

import 'demo_scenario.dart';

class DemoManifestFactory {
  static const appId = 'com.example.update_simulator';

  const DemoManifestFactory();

  UpdateManifest build(DemoScenario scenario) {
    if (!DemoScenario.allowedDeliveries(scenario.platform)
        .contains(scenario.delivery)) {
      throw ArgumentError.value(
        scenario.delivery,
        'delivery',
        'Delivery is not available for ${scenario.platform.name}.',
      );
    }

    return UpdateManifest(
      schemaVersion: 3,
      appId: appId,
      channel: scenario.channel,
      releases: [
        UpdateCandidate(
          version: scenario.updateAvailable
              ? scenario.releaseVersion
              : scenario.installedVersion,
          buildNumber: scenario.updateAvailable
              ? scenario.releaseBuildNumber
              : scenario.installedBuildNumber,
          channel: scenario.channel,
          platform: scenario.platform,
          architecture: scenario.architecture,
          releaseNotes: scenario.releaseNotes,
          releasedAt: DateTime.utc(2026, 7, 10, 12),
          policy: UpdatePolicy(
            level: scenario.policyLevel,
            minSupportedVersion: scenario.minSupportedVersion,
          ),
          actions: [_buildAction(scenario)],
        ),
      ],
    );
  }

  UpdateAction _buildAction(DemoScenario scenario) {
    return switch (scenario.delivery) {
      DemoDelivery.officialStore => _buildStoreAction(scenario.platform),
      DemoDelivery.androidMarket => OpenAndroidMarketAction(
          market: AndroidMarketKind.xiaomi,
          targetPackageName: appId,
          fallbackUrl: Uri.parse(
            'https://market.example.invalid/apps/$appId',
          ),
        ),
      DemoDelivery.androidPackage => DownloadAndInstallPackageAction(
          packageUrl: Uri.parse(
            'https://downloads.example.invalid/update-simulator.apk',
          ),
          packageType: PackageType.apk,
          packageSizeBytes: scenario.packageSizeBytes,
          sha256: '0' * 64,
        ),
      DemoDelivery.desktopInstaller => OpenInstallerAction(
          installerUrl: Uri.parse(
            scenario.platform == TargetPlatform.macOS
                ? 'https://downloads.example.invalid/update-simulator.dmg'
                : 'https://downloads.example.invalid/update-simulator.msix',
          ),
          installerType: scenario.platform == TargetPlatform.macOS
              ? InstallerType.dmg
              : InstallerType.msix,
          installerSizeBytes: scenario.packageSizeBytes,
          sha256: '0' * 64,
        ),
    };
  }

  OpenStoreAction _buildStoreAction(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android => OpenStoreAction(
          store: StoreKind.googlePlay,
          storeUrl: Uri.parse(
            'https://play.google.com/store/apps/details?id=$appId',
          ),
        ),
      TargetPlatform.iOS => OpenStoreAction(
          store: StoreKind.appStore,
          storeUrl: Uri.parse('https://apps.apple.com/app/id000000000'),
        ),
      TargetPlatform.macOS => OpenStoreAction(
          store: StoreKind.macAppStore,
          storeUrl: Uri.parse('https://apps.apple.com/app/id000000000'),
        ),
      _ => throw ArgumentError.value(
          platform,
          'platform',
          'Official store is not available for ${platform.name}.',
        ),
    };
  }
}
