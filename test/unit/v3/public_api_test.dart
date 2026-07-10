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
        const InstallPackageAction(packagePath: '/tmp/app.apk'),
        DownloadAndInstallPackageAction(
          packageUrl: Uri.parse('https://example.com/app.apk'),
          packageType: PackageType.apk,
        ),
        OpenInstallerAction(
          installerUrl: Uri.parse('https://example.com/app.msi'),
          installerType: InstallerType.msi,
          sha256: 'b' * 64,
        ),
      ],
    );
    final manifest = UpdateManifest(
      schemaVersion: 3,
      appId: 'com.example.app',
      channel: 'stable',
      releases: [candidate],
    );

    expect(updater.source, isA<ManifestUpdateSource>());
    expect(manifest.releases.single, same(candidate));
    expect(candidate.actions, hasLength(6));
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

    expect(readme, contains('AppUpdater.manifest'));
    expect(readme, contains('checkAndPrepare'));
    expect(readme, contains('performRecommended'));
    expect(readme, contains('downloadAndInstallPackage'));
    expect(readme, contains('Play In-App Updates'));
    expect(readme, contains('Planned'));
    expect(
        readme, isNot(contains('Remote manifest fetching is not implemented')));
    expect(readme, contains('storeUrl'));
    expect(readme, contains('packageUrl'));
    expect(readme, contains('installerUrl'));
    expect(readme, isNot(contains('required SHA-256')));
    expect(readme, isNot(contains('signature')));
    expect(readme, isNot(contains('downloadUrl')));
    expect(readme, isNot(contains('artifactUri')));
    expect(readme.toLowerCase(), isNot(contains('md5')));
    expect(readme, isNot(contains('Windows | URL handler support')));
    expect(readme, contains('Windows | Unsupported'));
  });

  test('example demonstrates the convenience flow through the public API', () {
    final example = File('example/lib/main.dart').readAsStringSync();
    final examplePubspec = File('example/pubspec.yaml').readAsStringSync();

    expect(example, contains('UpdateSource.staticManifest'));
    expect(example, contains('AppUpdater.manifest'));
    expect(example, contains('expectedAppId: expectedAppId'));
    expect(example, contains('await updater.checkAndPrepare()'));
    expect(example, contains('performRecommendedStream'));
    expect(example, contains('PreviewUpdateExecutor'));
    expect(example, contains('UpdateActionCancelToken'));
    expect(example, contains('DownloadAndInstallPackageAction'));
    expect(examplePubspec, contains('version: 1.0.0+1'));
  });

  test('publish archive excludes internal implementation plans', () {
    final pubignore = File('.pubignore').readAsStringSync();

    expect(pubignore, contains('doc/plans/'));
    expect(pubignore, contains('docs/plans/'));
  });

  test('Android package installation permission is opt in', () {
    final pluginManifest =
        File('android/src/main/AndroidManifest.xml').readAsStringSync();
    final exampleManifest =
        File('example/android/app/src/main/AndroidManifest.xml')
            .readAsStringSync();

    expect(pluginManifest, isNot(contains('REQUEST_INSTALL_PACKAGES')));
    expect(exampleManifest, contains('REQUEST_INSTALL_PACKAGES'));
  });

  test('publish archive excludes machine-local platform configuration', () {
    final pubignore = File('.pubignore').readAsStringSync();

    expect(File('ohos/local.properties').existsSync(), isFalse);
    expect(pubignore, contains('**/local.properties'));
  });

  test('pubspec advertises a coherent Flutter SDK floor', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains("sdk: '>=3.4.0 <4.0.0'"));
    expect(pubspec, contains("flutter: '>=3.4.0'"));
  });

  test('pubspec and native packages contain release metadata', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final iosPodspec =
        File('ios/flutter_app_updater.podspec').readAsStringSync();
    final macosPodspec =
        File('macos/flutter_app_updater.podspec').readAsStringSync();
    final ohosPackage = File('ohos/oh-package.json5').readAsStringSync();

    expect(pubspec, contains('repository:'));
    expect(pubspec, contains('issue_tracker:'));
    expect(pubspec, contains('topics:'));
    for (final metadata in [iosPodspec, macosPodspec, ohosPackage]) {
      expect(metadata, contains('3.0.0'));
      expect(metadata, isNot(contains('example.com')));
      expect(metadata, isNot(contains('Your Company')));
      expect(metadata, isNot(contains('Please describe')));
    }
  });

  test('publish workflow uses pub.dev OIDC and verifies the release tag', () {
    final workflow = File('.github/workflows/publish.yml').readAsStringSync();

    expect(workflow, contains('id-token: write'));
    expect(workflow, contains('environment: pub.dev'));
    expect(workflow, contains('GITHUB_REF_NAME'));
    expect(
      workflow,
      contains('dart-lang/setup-dart/.github/workflows/publish.yml@v1'),
    );
    expect(workflow, isNot(contains('CREDENTIALS_JSON')));
    expect(workflow, isNot(contains('credentials.json')));
  });

  test('CI covers quality gates and native example builds', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();

    expect(workflow, contains('flutter test --coverage'));
    expect(workflow, contains('Enforce 80% coverage floor'));
    expect(workflow, contains('manifest_fetcher'));
    expect(workflow, contains('package_downloader'));
    expect(workflow, contains('flutter pub publish --dry-run'));
    expect(workflow, contains('flutter build apk --debug'));
    expect(workflow, contains('macos-latest'));
    expect(workflow, contains('flutter build ios --simulator --debug'));
    expect(workflow, contains('flutter build macos --debug'));
    expect(workflow, contains('windows-latest'));
    expect(workflow, contains('flutter build windows --debug'));
  });

  test('repository includes lightweight open-source governance', () {
    for (final path in [
      'CONTRIBUTING.md',
      'SECURITY.md',
      '.github/dependabot.yml',
      '.github/ISSUE_TEMPLATE/bug_report.yml',
      '.github/PULL_REQUEST_TEMPLATE.md',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: '$path must exist');
      expect(File(path).lengthSync(), greaterThan(0));
    }
  });
}
