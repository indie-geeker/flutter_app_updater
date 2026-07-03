import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/manifest/manifest_parser.dart';
import 'package:flutter_app_updater/src/models/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManifestParser', () {
    test('parses schema version, metadata, candidate fields, and actions', () {
      final manifest = const ManifestParser().parse({
        'schemaVersion': 3,
        'appId': 'com.example.app',
        'channel': 'stable',
        'releases': [
          {
            'version': '2.0.0',
            'buildNumber': '42',
            'channel': 'stable',
            'platform': 'android',
            'architecture': 'arm64',
            'releaseNotes': 'Bug fixes',
            'releasedAt': '2026-07-03T10:00:00Z',
            'policy': {
              'level': 'required',
              'minSupportedVersion': '1.5.0',
            },
            'actions': [
              {
                'type': 'openStore',
                'store': 'googlePlay',
                'storeUrl':
                    'https://play.google.com/store/apps/details?id=com.example.app',
              },
              {
                'type': 'downloadPackage',
                'packageUrl': 'https://example.com/app.apk',
                'packageType': 'apk',
                'packageSizeBytes': 25600000,
              },
              {
                'type': 'openInstaller',
                'installerUrl': 'https://example.com/app.dmg',
                'installerType': 'dmg',
                'installerSizeBytes': 82000000,
              },
              {
                'type': 'installPackage',
                'packagePath': '/tmp/app.apk',
                'packageType': 'apk',
              },
              {
                'type': 'downloadAndInstallPackage',
                'packageUrl': 'https://example.com/app.apk',
                'packageType': 'apk',
                'packageSizeBytes': 25600000,
              },
            ],
          },
        ],
      });

      expect(manifest.schemaVersion, 3);
      expect(manifest.appId, 'com.example.app');
      expect(manifest.channel, 'stable');

      final release = manifest.releases.single;
      expect(release.version, '2.0.0');
      expect(release.buildNumber, '42');
      expect(release.channel, 'stable');
      expect(release.platform, TargetPlatform.android);
      expect(release.architecture, 'arm64');
      expect(release.releaseNotes, 'Bug fixes');
      expect(release.releasedAt, DateTime.parse('2026-07-03T10:00:00Z'));
      expect(release.policy.level, UpdatePolicyLevel.required);
      expect(release.policy.minSupportedVersion, '1.5.0');

      final storeAction = release.actions[0] as OpenStoreAction;
      expect(storeAction.store, StoreKind.googlePlay);
      expect(storeAction.storeUrl.host, 'play.google.com');

      final packageAction = release.actions[1] as DownloadPackageAction;
      expect(packageAction.packageUrl.path, '/app.apk');
      expect(packageAction.packageType, PackageType.apk);
      expect(packageAction.packageSizeBytes, 25600000);
      expect(packageAction.sha256, isNull);

      final installerAction = release.actions[2] as OpenInstallerAction;
      expect(installerAction.installerUrl.path, '/app.dmg');
      expect(installerAction.installerType, InstallerType.dmg);
      expect(installerAction.installerSizeBytes, 82000000);
      expect(installerAction.sha256, isNull);

      final installAction = release.actions[3] as InstallPackageAction;
      expect(installAction.packagePath, '/tmp/app.apk');
      expect(installAction.packageType, PackageType.apk);

      final downloadAndInstallAction =
          release.actions[4] as DownloadAndInstallPackageAction;
      expect(downloadAndInstallAction.packageUrl.path, '/app.apk');
      expect(downloadAndInstallAction.packageType, PackageType.apk);
      expect(downloadAndInstallAction.packageSizeBytes, 25600000);
      expect(downloadAndInstallAction.sha256, isNull);
    });

    test('parses Android market and Play in-app update actions', () {
      final release = const ManifestParser()
          .parse({
            'schemaVersion': 3,
            'appId': 'com.example.app',
            'channel': 'stable',
            'releases': [
              {
                'version': '2.0.0',
                'platform': 'android',
                'releaseNotes': 'Bug fixes',
                'actions': [
                  {
                    'type': 'openAndroidMarket',
                    'market': 'xiaomi',
                    'targetPackageName': 'com.example.app',
                    'fallbackUrl':
                        'https://app.mi.com/details?id=com.example.app',
                  },
                  {
                    'type': 'playInAppUpdate',
                    'mode': 'immediate',
                  },
                ],
              },
            ],
          })
          .releases
          .single;

      final marketAction = release.actions[0] as OpenAndroidMarketAction;
      expect(marketAction.market, AndroidMarketKind.xiaomi);
      expect(marketAction.targetPackageName, 'com.example.app');
      expect(marketAction.fallbackUrl?.host, 'app.mi.com');

      final playAction = release.actions[1] as PlayInAppUpdateAction;
      expect(playAction.mode, PlayUpdateMode.immediate);
    });
  });
}
