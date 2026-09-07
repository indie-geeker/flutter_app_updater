import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Runtime application identity and storage used by the production example.
final class ProductionAppMetadata {
  final String version;
  final String buildNumber;
  final String appId;
  final String downloadDirectory;

  const ProductionAppMetadata({
    required this.version,
    required this.buildNumber,
    required this.appId,
    required this.downloadDirectory,
  });
}

/// Loads runtime values only after an enabled user requests an update check.
abstract interface class ProductionRuntimeLoader {
  Future<ProductionAppMetadata> load();
}

/// Loads installed package metadata and an application-support download path.
final class PluginProductionRuntimeLoader implements ProductionRuntimeLoader {
  const PluginProductionRuntimeLoader();

  @override
  Future<ProductionAppMetadata> load() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final supportDirectory = await getApplicationSupportDirectory();
    final suffix = defaultTargetPlatform == TargetPlatform.android
        ? 'flutter_app_updater${Platform.pathSeparator}foreground'
        : 'updates';
    return ProductionAppMetadata(
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      appId: packageInfo.packageName,
      downloadDirectory:
          '${supportDirectory.path}${Platform.pathSeparator}$suffix',
    );
  }
}
