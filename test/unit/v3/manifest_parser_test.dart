import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/manifest/manifest_document.dart';
import 'package:flutter_app_updater/src/manifest/manifest_document_parser.dart';
import 'package:flutter_app_updater/src/manifest/manifest_parser.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
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
                'sha256': 'A' * 64,
              },
              {
                'type': 'openInstaller',
                'installerUrl': 'https://example.com/app.dmg',
                'installerType': 'dmg',
                'installerSizeBytes': 82000000,
                'sha256': 'B' * 64,
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
                'sha256': 'C' * 64,
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
      expect(packageAction.sha256, 'a' * 64);

      final installerAction = release.actions[2] as OpenInstallerAction;
      expect(installerAction.installerUrl.path, '/app.dmg');
      expect(installerAction.installerType, InstallerType.dmg);
      expect(installerAction.installerSizeBytes, 82000000);
      expect(installerAction.sha256, 'b' * 64);

      final installAction = release.actions[3] as InstallPackageAction;
      expect(installAction.packagePath, '/tmp/app.apk');
      expect(installAction.packageType, PackageType.apk);

      final downloadAndInstallAction =
          release.actions[4] as DownloadAndInstallPackageAction;
      expect(downloadAndInstallAction.packageUrl.path, '/app.apk');
      expect(downloadAndInstallAction.packageType, PackageType.apk);
      expect(downloadAndInstallAction.packageSizeBytes, 25600000);
      expect(downloadAndInstallAction.sha256, 'c' * 64);
    });

    test('parses Android market actions', () {
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
    });

    test('pure Dart document parser preserves every runtime wire value', () {
      final json = _completeManifest();

      final document = const ManifestDocumentParser().parse(json);
      final runtime = const ManifestParser().parse(json);

      expect(document.schemaVersion, runtime.schemaVersion);
      expect(document.appId, runtime.appId);
      expect(document.channel, runtime.channel);
      final documentRelease = document.releases.single;
      final runtimeRelease = runtime.releases.single;
      expect(documentRelease.version, runtimeRelease.version);
      expect(documentRelease.buildNumber, runtimeRelease.buildNumber);
      expect(documentRelease.channel, runtimeRelease.channel);
      expect(documentRelease.platform, ManifestPlatform.android);
      expect(runtimeRelease.platform, TargetPlatform.android);
      expect(documentRelease.architecture, runtimeRelease.architecture);
      expect(documentRelease.releaseNotes, runtimeRelease.releaseNotes);
      expect(documentRelease.releasedAt, runtimeRelease.releasedAt);
      expect(documentRelease.policy.level, ManifestPolicyLevel.required);
      expect(
        documentRelease.policy.minSupportedVersion,
        runtimeRelease.policy.minSupportedVersion,
      );
      expect(documentRelease.actions, hasLength(runtimeRelease.actions.length));

      final store = documentRelease.actions[0] as ManifestOpenStoreAction;
      expect(store.store, ManifestStoreKind.googlePlay);
      expect(store.storeUrl.host, 'play.google.com');
      final market =
          documentRelease.actions[1] as ManifestOpenAndroidMarketAction;
      expect(market.market, ManifestAndroidMarketKind.xiaomi);
      expect(market.targetPackageName, document.appId);
      expect(market.fallbackUrl?.host, 'app.mi.com');
      final package =
          documentRelease.actions[2] as ManifestDownloadPackageAction;
      expect(package.packageType, ManifestPackageType.apk);
      expect(package.packageSizeBytes, 25600000);
      expect(package.sha256, 'a' * 64);
      final local = documentRelease.actions[3] as ManifestInstallPackageAction;
      expect(local.packagePath, '/tmp/app.apk');
      expect(local.packageType, ManifestPackageType.apk);
      final combined =
          documentRelease.actions[4] as ManifestDownloadAndInstallPackageAction;
      expect(combined.packageType, ManifestPackageType.apk);
      expect(combined.sha256, 'c' * 64);
      final installer =
          documentRelease.actions[5] as ManifestOpenInstallerAction;
      expect(installer.installerType, ManifestInstallerType.dmg);
      expect(installer.sha256, 'b' * 64);
    });

    test('document and runtime parsers preserve wire interpretation errors',
        () {
      final cases = <Map<String, Object?>>[
        _completeManifest()..release['platform'] = 'solaris',
        _completeManifest()..policy['level'] = 'urgent',
        _completeManifest()..action(0)['store'] = 'steam',
        _completeManifest()..action(1)['market'] = 'unknown',
        _completeManifest()..action(2)['packageType'] = 'ipa',
        _completeManifest()..action(5)['installerType'] = 'pkg',
        _completeManifest()..release['releasedAt'] = 'not-a-date',
      ];

      for (final json in cases) {
        final documentError = _captureParseError(
          () => const ManifestDocumentParser().parse(json),
        );
        final runtimeError = _captureParseError(
          () => const ManifestParser().parse(json),
        );

        expect(documentError.code, runtimeError.code);
        expect(documentError.message, runtimeError.message);
      }
    });

    test('rejects unfinished Play in-app update actions', () {
      expect(
        () => const ManifestParser().parse({
          'schemaVersion': 3,
          'appId': 'com.example.app',
          'channel': 'stable',
          'releases': [
            {
              'version': '2.0.0',
              'platform': 'android',
              'releaseNotes': 'Bug fixes',
              'actions': [
                {'type': 'playInAppUpdate', 'mode': 'immediate'},
              ],
            },
          ],
        }),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.unsupportedActionType,
          ),
        ),
      );
    });
  });
}

Map<String, Object?> _completeManifest() {
  return {
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
            'type': 'openAndroidMarket',
            'market': 'xiaomi',
            'targetPackageName': 'com.example.app',
            'fallbackUrl': 'https://app.mi.com/details?id=com.example.app',
          },
          {
            'type': 'downloadPackage',
            'packageUrl': 'https://example.com/app.apk',
            'packageType': 'apk',
            'packageSizeBytes': 25600000,
            'sha256': 'A' * 64,
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
            'sha256': 'C' * 64,
          },
          {
            'type': 'openInstaller',
            'installerUrl': 'https://example.com/app.dmg',
            'installerType': 'dmg',
            'installerSizeBytes': 82000000,
            'sha256': 'B' * 64,
          },
        ],
      },
    ],
  };
}

ManifestParseException _captureParseError(void Function() parse) {
  try {
    parse();
  } on ManifestParseException catch (error) {
    return error;
  }
  fail('Expected ManifestParseException.');
}

extension on Map<String, Object?> {
  Map<String, Object?> get release {
    return (this['releases'] as List<Object?>).single as Map<String, Object?>;
  }

  Map<String, Object?> get policy {
    return release['policy'] as Map<String, Object?>;
  }

  Map<String, Object?> action(int index) {
    return (release['actions'] as List<Object?>)[index] as Map<String, Object?>;
  }
}
