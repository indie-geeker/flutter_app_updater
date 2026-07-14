import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

enum DemoDelivery {
  officialStore,
  androidMarket,
  androidDownload,
  androidInstall,
  androidDownloadAndInstall,
  desktopInstaller,
}

enum DemoOutcome {
  success,
  downloadFailed,
  hashMismatch,
  installPermissionRequired,
  platformNotSupported,
  actionFailed,
}

const _unset = Object();

class DemoScenario {
  final String installedVersion;
  final String installedBuildNumber;
  final TargetPlatform platform;
  final String runtimeArchitecture;
  final String runtimeChannel;
  final bool updateAvailable;
  final String releaseVersion;
  final String releaseBuildNumber;
  final String releaseArchitecture;
  final String releaseChannel;
  final String releaseNotes;
  final UpdatePolicyLevel policyLevel;
  final String? minSupportedVersion;
  final DemoDelivery delivery;
  final DemoDelivery? fallbackDelivery;
  final int packageSizeBytes;
  final Duration executionDuration;
  final DemoOutcome outcome;
  final bool succeedOnRetry;

  const DemoScenario({
    required this.installedVersion,
    required this.installedBuildNumber,
    required this.platform,
    required this.runtimeArchitecture,
    required this.runtimeChannel,
    required this.updateAvailable,
    required this.releaseVersion,
    required this.releaseBuildNumber,
    required this.releaseArchitecture,
    required this.releaseChannel,
    required this.releaseNotes,
    required this.policyLevel,
    required this.minSupportedVersion,
    required this.delivery,
    required this.fallbackDelivery,
    required this.packageSizeBytes,
    required this.executionDuration,
    required this.outcome,
    required this.succeedOnRetry,
  });

  factory DemoScenario.defaults() => const DemoScenario(
        installedVersion: '1.0.0',
        installedBuildNumber: '10',
        platform: TargetPlatform.android,
        runtimeArchitecture: 'arm64',
        runtimeChannel: 'stable',
        updateAvailable: true,
        releaseVersion: '2.0.0',
        releaseBuildNumber: '20',
        releaseArchitecture: 'arm64',
        releaseChannel: 'stable',
        releaseNotes: 'Improved stability and update reliability.',
        policyLevel: UpdatePolicyLevel.recommended,
        minSupportedVersion: null,
        delivery: DemoDelivery.androidDownloadAndInstall,
        fallbackDelivery: DemoDelivery.officialStore,
        packageSizeBytes: 50000000,
        executionDuration: Duration(seconds: 2),
        outcome: DemoOutcome.success,
        succeedOnRetry: false,
      );

  UpdateSelector toSelector() => UpdateSelector(
        installedVersion: installedVersion,
        installedBuildNumber: installedBuildNumber,
        platform: platform,
        architecture: runtimeArchitecture.trim().isEmpty
            ? null
            : runtimeArchitecture.trim(),
        channel: runtimeChannel,
      );

  DemoScenario copyWith({
    String? installedVersion,
    String? installedBuildNumber,
    TargetPlatform? platform,
    String? runtimeArchitecture,
    String? runtimeChannel,
    bool? updateAvailable,
    String? releaseVersion,
    String? releaseBuildNumber,
    String? releaseArchitecture,
    String? releaseChannel,
    String? releaseNotes,
    UpdatePolicyLevel? policyLevel,
    Object? minSupportedVersion = _unset,
    DemoDelivery? delivery,
    Object? fallbackDelivery = _unset,
    int? packageSizeBytes,
    Duration? executionDuration,
    DemoOutcome? outcome,
    bool? succeedOnRetry,
  }) {
    return DemoScenario(
      installedVersion: installedVersion ?? this.installedVersion,
      installedBuildNumber: installedBuildNumber ?? this.installedBuildNumber,
      platform: platform ?? this.platform,
      runtimeArchitecture: runtimeArchitecture ?? this.runtimeArchitecture,
      runtimeChannel: runtimeChannel ?? this.runtimeChannel,
      updateAvailable: updateAvailable ?? this.updateAvailable,
      releaseVersion: releaseVersion ?? this.releaseVersion,
      releaseBuildNumber: releaseBuildNumber ?? this.releaseBuildNumber,
      releaseArchitecture: releaseArchitecture ?? this.releaseArchitecture,
      releaseChannel: releaseChannel ?? this.releaseChannel,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      policyLevel: policyLevel ?? this.policyLevel,
      minSupportedVersion: identical(minSupportedVersion, _unset)
          ? this.minSupportedVersion
          : minSupportedVersion as String?,
      delivery: delivery ?? this.delivery,
      fallbackDelivery: identical(fallbackDelivery, _unset)
          ? this.fallbackDelivery
          : fallbackDelivery as DemoDelivery?,
      packageSizeBytes: packageSizeBytes ?? this.packageSizeBytes,
      executionDuration: executionDuration ?? this.executionDuration,
      outcome: outcome ?? this.outcome,
      succeedOnRetry: succeedOnRetry ?? this.succeedOnRetry,
    );
  }

  static List<DemoDelivery> allowedDeliveries(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android => const [
          DemoDelivery.officialStore,
          DemoDelivery.androidMarket,
          DemoDelivery.androidDownload,
          DemoDelivery.androidInstall,
          DemoDelivery.androidDownloadAndInstall,
        ],
      TargetPlatform.iOS => const [DemoDelivery.officialStore],
      TargetPlatform.macOS => const [
          DemoDelivery.officialStore,
          DemoDelivery.desktopInstaller,
        ],
      TargetPlatform.windows => const [DemoDelivery.desktopInstaller],
      TargetPlatform.linux || TargetPlatform.fuchsia => const [],
    };
  }

  static List<DemoOutcome> allowedOutcomes(DemoDelivery delivery) {
    return [
      DemoOutcome.success,
      if (isDownloadDelivery(delivery)) ...[
        DemoOutcome.downloadFailed,
        DemoOutcome.hashMismatch,
      ],
      if (isInstallationDelivery(delivery))
        DemoOutcome.installPermissionRequired,
      DemoOutcome.platformNotSupported,
      DemoOutcome.actionFailed,
    ];
  }

  static bool isDownloadDelivery(DemoDelivery delivery) {
    return delivery == DemoDelivery.androidDownload ||
        delivery == DemoDelivery.androidDownloadAndInstall ||
        delivery == DemoDelivery.desktopInstaller;
  }

  static bool isInstallationDelivery(DemoDelivery delivery) {
    return delivery == DemoDelivery.androidInstall ||
        delivery == DemoDelivery.androidDownloadAndInstall;
  }
}
