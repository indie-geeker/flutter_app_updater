import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater_example/production/production_app_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/app/files';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform original;
  setUp(() {
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths();
    PackageInfo.setMockInitialValues(
        appName: 'Test',
        packageName: 'com.example.app',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
  });
  tearDown(() {
    PathProviderPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });
  test('Android foreground downloads use a FileProvider-specific directory',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final metadata = await const PluginProductionRuntimeLoader().load();
    expect(metadata.downloadDirectory,
        '/app/files/flutter_app_updater/foreground');
  });
  test('macOS retains its application support updates directory', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final metadata = await const PluginProductionRuntimeLoader().load();
    expect(metadata.downloadDirectory, '/app/files/updates');
  });
}
