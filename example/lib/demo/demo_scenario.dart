import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

enum DemoDelivery {
  officialStore,
  androidMarket,
  androidPackage,
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
  final String architecture;
  final String channel;
  final bool updateAvailable;
  final String releaseVersion;
  final String releaseBuildNumber;
  final String releaseNotes;
  final UpdatePolicyLevel policyLevel;
  final String? minSupportedVersion;
  final DemoDelivery delivery;
  final int packageSizeBytes;
  final Duration executionDuration;
  final DemoOutcome outcome;

  const DemoScenario({
    required this.installedVersion,
    required this.installedBuildNumber,
    required this.platform,
    required this.architecture,
    required this.channel,
    required this.updateAvailable,
    required this.releaseVersion,
    required this.releaseBuildNumber,
    required this.releaseNotes,
    required this.policyLevel,
    required this.minSupportedVersion,
    required this.delivery,
    required this.packageSizeBytes,
    required this.executionDuration,
    required this.outcome,
  });

  factory DemoScenario.defaults() => const DemoScenario(
        installedVersion: '1.0.0',
        installedBuildNumber: '10',
        platform: TargetPlatform.android,
        architecture: 'arm64',
        channel: 'stable',
        updateAvailable: true,
        releaseVersion: '2.0.0',
        releaseBuildNumber: '20',
        releaseNotes: 'Improved stability and update reliability.',
        policyLevel: UpdatePolicyLevel.recommended,
        minSupportedVersion: null,
        delivery: DemoDelivery.androidPackage,
        packageSizeBytes: 50000000,
        executionDuration: Duration(seconds: 2),
        outcome: DemoOutcome.success,
      );

  UpdateSelector toSelector() => UpdateSelector(
        installedVersion: installedVersion,
        installedBuildNumber: installedBuildNumber,
        platform: platform,
        architecture: architecture,
        channel: channel,
      );

  DemoScenario copyWith({
    String? installedVersion,
    String? installedBuildNumber,
    TargetPlatform? platform,
    String? architecture,
    String? channel,
    bool? updateAvailable,
    String? releaseVersion,
    String? releaseBuildNumber,
    String? releaseNotes,
    UpdatePolicyLevel? policyLevel,
    Object? minSupportedVersion = _unset,
    DemoDelivery? delivery,
    int? packageSizeBytes,
    Duration? executionDuration,
    DemoOutcome? outcome,
  }) {
    return DemoScenario(
      installedVersion: installedVersion ?? this.installedVersion,
      installedBuildNumber: installedBuildNumber ?? this.installedBuildNumber,
      platform: platform ?? this.platform,
      architecture: architecture ?? this.architecture,
      channel: channel ?? this.channel,
      updateAvailable: updateAvailable ?? this.updateAvailable,
      releaseVersion: releaseVersion ?? this.releaseVersion,
      releaseBuildNumber: releaseBuildNumber ?? this.releaseBuildNumber,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      policyLevel: policyLevel ?? this.policyLevel,
      minSupportedVersion: identical(minSupportedVersion, _unset)
          ? this.minSupportedVersion
          : minSupportedVersion as String?,
      delivery: delivery ?? this.delivery,
      packageSizeBytes: packageSizeBytes ?? this.packageSizeBytes,
      executionDuration: executionDuration ?? this.executionDuration,
      outcome: outcome ?? this.outcome,
    );
  }

  static List<DemoDelivery> allowedDeliveries(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android => const [
          DemoDelivery.officialStore,
          DemoDelivery.androidMarket,
          DemoDelivery.androidPackage,
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
}
