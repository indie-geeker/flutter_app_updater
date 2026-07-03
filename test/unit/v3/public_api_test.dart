import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public library exports v3 updater model types', () {
    final updater = AppUpdater(
      source: UpdateSource.manifest(
        manifestUrl: Uri.parse('https://example.com/app-updates.json'),
      ),
      selector: const UpdateSelector(
        installedVersion: '1.0.0',
        platform: TargetPlatform.android,
        architecture: 'arm64',
        channel: 'stable',
      ),
    );
    final action = DownloadPackageAction(
      packageUrl: Uri.parse('https://example.com/app.apk'),
      packageType: PackageType.apk,
      sha256: 'a' * 64,
    );
    final candidate = UpdateCandidate(
      version: '2.0.0',
      channel: 'stable',
      platform: TargetPlatform.android,
      releaseNotes: 'Bug fixes',
      policy: const UpdatePolicy(level: UpdatePolicyLevel.required),
      actions: [
        OpenStoreAction(
          store: StoreKind.googlePlay,
          storeUrl: Uri.parse(
            'https://play.google.com/store/apps/details?id=com.example.app',
          ),
        ),
        const OpenAndroidMarketAction(
          market: AndroidMarketKind.xiaomi,
          targetPackageName: 'com.example.app',
        ),
        action,
        OpenInstallerAction(
          installerUrl: Uri.parse('https://example.com/app.msi'),
          installerType: InstallerType.msi,
          sha256: 'b' * 64,
        ),
      ],
    );

    expect(updater.source, isA<ManifestUpdateSource>());
    expect(candidate.actions, hasLength(4));
    expect(candidate.policy.level, UpdatePolicyLevel.required);
    expect(action.packageUrl.path, '/app.apk');
  });

  test('public barrel does not export v2 API files', () {
    final barrel = File('lib/flutter_app_updater.dart').readAsStringSync();

    expect(barrel, isNot(contains("src/updater.dart")));
    expect(barrel, isNot(contains("src/models/update_info.dart")));
  });

  test('README documents v3 without legacy fields', () {
    final readme = File('README.md').readAsStringSync();

    expect(readme, contains('v3 is a breaking update'));
    expect(readme, contains('storeUrl'));
    expect(readme, contains('packageUrl'));
    expect(readme, contains('installerUrl'));
    expect(readme, isNot(contains('downloadUrl')));
    expect(readme, isNot(contains('artifactUri')));
    expect(readme.toLowerCase(), isNot(contains('md5')));
  });
}
