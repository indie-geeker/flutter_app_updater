import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analysis requires documentation for every public API member', () {
    final options = File('analysis_options.yaml').readAsStringSync();

    expect(options, contains('public_member_api_docs: true'));
  });

  test('public library exports v3 updater model types', () {
    final updater = AppUpdater(
      source: UpdateSource.manifest(
        manifestUrl: Uri.parse('https://example.com/app-updates.json'),
        expectedAppId: 'com.example.app',
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
      packageSizeBytes: 42,
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
          packageSizeBytes: 42,
          sha256: 'a' * 64,
        ),
        OpenInstallerAction(
          installerUrl: Uri.parse('https://example.com/app.msi'),
          installerType: InstallerType.msi,
          installerSizeBytes: 42,
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
    expect(
      (updater.source as ManifestUpdateSource).expectedAppId,
      'com.example.app',
    );
    expect(manifest.releases.single, same(candidate));
    expect(candidate.actions, hasLength(6));
    expect(candidate.policy.level, UpdatePolicyLevel.required);
    expect(action.packageUrl.path, '/app.apk');
  });

  test('public library exports Android background download API types', () {
    final task = BackgroundDownloadTask(
      id: 'task-1',
      revision: 1,
      status: BackgroundDownloadStatus.queued,
      downloadedBytes: 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final manager = AndroidBackgroundDownloadManager();

    expect(task.isTerminal, isFalse);
    expect(manager, isA<AndroidBackgroundDownloadManager>());
    expect(
      const BackgroundDownloadException(
        code: UpdateErrorCode.backgroundDownloadUnavailable,
        message: 'Unavailable.',
      ),
      isA<Exception>(),
    );

    final managerSource = File(
      'lib/src/background/android_background_download_manager.dart',
    ).readAsStringSync();
    expect(
      managerSource,
      isNot(contains('final FlutterAppUpdaterPlatform platform;')),
    );
    expect(
      managerSource,
      isNot(contains('FlutterAppUpdaterPlatform? platform')),
    );

    Future<BackgroundDownloadTask> Function(DownloadPackageAction) start =
        manager.start;
    Future<BackgroundDownloadTask> Function(String) get = manager.get;
    Future<List<BackgroundDownloadTask>> Function() list = manager.list;
    Future<List<BackgroundDownloadTask>> Function() listUnfinished =
        manager.listUnfinished;
    Stream<BackgroundDownloadTask> Function(String) watch = manager.watch;
    Future<BackgroundDownloadTask> Function(String) resume = manager.resume;
    Future<BackgroundDownloadTask> Function(String) cancel = manager.cancel;
    Future<void> Function(String) remove = manager.remove;
    Future<InstallPackageAction> Function(String) prepareInstall =
        manager.createInstallAction;
    expect(start, isA<Function>());
    expect(get, isA<Function>());
    expect(list, isA<Function>());
    expect(listUnfinished, isA<Function>());
    expect(watch, isA<Function>());
    expect(resume, isA<Function>());
    expect(cancel, isA<Function>());
    expect(remove, isA<Function>());
    expect(prepareInstall, isA<Function>());
  });

  test('docs lock the Android background download support boundary', () {
    final readme = File('README.md').readAsStringSync();
    final exampleReadme = File('example/README.md').readAsStringSync();
    final contributing = File('CONTRIBUTING.md').readAsStringSync();
    final verification =
        File('tool/verification/android_background_download.md')
            .readAsStringSync();

    expect(readme, contains('Advanced Android-only background downloads'));
    expect(readme, contains('AndroidBackgroundDownloadManager'));
    for (final declaration in [
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
      'android.permission.RUN_USER_INITIATED_JOBS',
      'UserInitiatedDownloadJobService',
      'BackgroundDownloadForegroundService',
      'BackgroundDownloadActionReceiver',
    ]) {
      expect(readme, contains(declaration));
    }
    for (final contract in [
      'HTTPS',
      'exact content length',
      'SHA-256',
      'Range',
      'strong ETag',
      'API 21-25',
      'API 26-33',
      'API 21-33',
      'API 34+',
      'force-stop',
      'reboot',
      'WorkManager',
      'DownloadManager',
      'silent installation',
    ]) {
      expect(readme, contains(contract));
    }
    expect(readme, contains('host application owns notification permission'));
    expect(readme, contains('createInstallAction'));
    expect(readme, contains('does not install the APK'));
    expect(readme, isNot(contains('all Chinese ROMs')));

    for (final doc in [exampleReadme, contributing, verification]) {
      expect(
        doc,
        contains(
          '../../android/gradlew :flutter_app_updater:testDebugUnitTest '
          ':flutter_app_updater:lintDebug :app:processDebugMainManifest',
        ),
      );
    }
  });

  test('public barrel does not export v2 API files', () {
    final barrel = File('lib/flutter_app_updater.dart').readAsStringSync();

    expect(barrel, isNot(contains("src/updater.dart")));
    expect(barrel, isNot(contains("src/models/update_info.dart")));
  });

  test('README documents v3 without legacy fields', () {
    final readme = File('README.md').readAsStringSync();
    final exampleReadme = File('example/README.md').readAsStringSync();

    expect(readme, contains('AppUpdater.manifest'));
    expect(readme, contains('checkAndPrepare'));
    expect(readme, contains('performRecommended'));
    expect(readme, contains('downloadAndInstallPackage'));
    expect(readme, isNot(contains('Play In-App Updates')));
    expect(readme, isNot(contains('| OHOS |')));
    expect(
        readme, isNot(contains('Remote manifest fetching is not implemented')));
    expect(readme, contains('storeUrl'));
    expect(readme, contains('packageUrl'));
    expect(readme, contains('installerUrl'));
    expect(readme, contains('required SHA-256'));
    expect(readme, contains('signature'));
    expect(readme, isNot(contains('downloadUrl')));
    expect(readme, isNot(contains('artifactUri')));
    expect(readme.toLowerCase(), isNot(contains('md5')));
    expect(readme, isNot(contains('Windows | URL handler support')));
    expect(readme, contains('| Windows | Unsupported'));
    expect(readme, contains('configurable update simulator'));
    expect(readme, contains('doc/migration-v2-to-v3.md'));
    expect(readme, contains('doc/security-model.md'));
    expect(exampleReadme, contains('Update Simulator'));
    expect(exampleReadme, contains('No external side effects'));
    expect(exampleReadme, isNot(contains('Safe preview')));
    expect(exampleReadme, contains('real signed-manifest path'));
  });

  test('example demonstrates the convenience flow through the public API', () {
    final example = File('example/lib/main.dart').readAsStringSync();
    final home = File('example/lib/presentation/example_home_page.dart')
        .readAsStringSync();
    final productionController = File(
      'example/lib/production/production_update_controller.dart',
    ).readAsStringSync();
    final controller =
        File('example/lib/demo/update_demo_controller.dart').readAsStringSync();
    final manifestFactory =
        File('example/lib/demo/demo_manifest_factory.dart').readAsStringSync();
    final simulator = File('example/lib/demo/simulated_update_executor.dart')
        .readAsStringSync();
    final examplePubspec = File('example/pubspec.yaml').readAsStringSync();

    expect(example, contains('ExampleHomePage'));
    expect(home, contains('UpdateSimulatorPage'));
    expect(home, contains('ProductionIntegrationPage'));
    expect(productionController, contains('AppUpdater.manifest'));
    expect(productionController, contains('ManifestSignaturePolicy.required'));
    expect(controller, contains('UpdateSource.staticManifest'));
    expect(controller, contains('await updater.checkAndPrepare()'));
    expect(controller, contains('performRecommendedStream'));
    expect(controller, contains('UpdateActionCancelToken'));
    expect(manifestFactory, contains('DownloadAndInstallPackageAction'));
    expect(simulator, contains('SimulatedUpdateExecutor'));
    for (final source in [
      example,
      home,
      productionController,
      controller,
      manifestFactory,
      simulator,
    ]) {
      expect(source, isNot(contains('flutter_app_updater/src/')));
    }
    expect(examplePubspec, contains('version: 1.0.0+1'));
  });

  test('publish archive excludes internal implementation plans', () {
    final pubignore = File('.pubignore').readAsStringSync();

    expect(pubignore, contains('doc/plans/'));
    expect(pubignore, contains('docs/plans/'));
  });

  test('safe simulator does not request Android package installation', () {
    final pluginManifest =
        File('android/src/main/AndroidManifest.xml').readAsStringSync();
    final exampleManifest =
        File('example/android/app/src/main/AndroidManifest.xml')
            .readAsStringSync();

    expect(pluginManifest, isNot(contains('REQUEST_INSTALL_PACKAGES')));
    expect(exampleManifest, isNot(contains('REQUEST_INSTALL_PACKAGES')));
  });

  test('publish archive excludes machine-local platform configuration', () {
    final pubignore = File('.pubignore').readAsStringSync();

    expect(File('ohos/local.properties').existsSync(), isFalse);
    expect(pubignore, contains('**/local.properties'));
  });

  test('pubspec and repository do not register unfinished OHOS support', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final issueTemplate =
        File('.github/ISSUE_TEMPLATE/bug_report.yml').readAsStringSync();

    expect(pubspec, isNot(contains('      ohos:')));
    expect(issueTemplate, isNot(contains('        - OHOS')));
    expect(Directory('ohos').existsSync(), isFalse);
    expect(Directory('example/ohos').existsSync(), isFalse);
  });

  test('pubspec advertises a coherent Flutter SDK floor', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains("sdk: '>=3.4.0 <4.0.0'"));
    expect(pubspec, contains("flutter: '>=3.22.0'"));
  });

  test('pubspec and native packages contain release metadata', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final iosPodspec =
        File('ios/flutter_app_updater.podspec').readAsStringSync();
    final macosPodspec =
        File('macos/flutter_app_updater.podspec').readAsStringSync();

    expect(pubspec, contains('repository:'));
    expect(pubspec, contains('issue_tracker:'));
    expect(pubspec, contains('topics:'));
    for (final metadata in [iosPodspec, macosPodspec]) {
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
      contains(
        'dart-lang/setup-dart/.github/workflows/publish.yml@'
        '65eb853c7ba17dde3be364c3d2858773e7144260',
      ),
    );
    expect(workflow, isNot(contains('CREDENTIALS_JSON')));
    expect(workflow, isNot(contains('credentials.json')));
  });

  test('CI covers quality gates and native example builds', () {
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    final workflow = File('.github/workflows/full-gate.yml').readAsStringSync();

    expect(ci, contains('uses: ./.github/workflows/full-gate.yml'));
    expect(workflow, contains('workflow_call'));
    expect(workflow, contains('quality-minimum'));
    expect(workflow, contains('quality-stable'));
    expect(workflow, contains('flutter test --coverage'));
    expect(workflow, contains('Enforce total and critical 80% coverage'));
    expect(workflow, contains('manifest_fetcher'));
    expect(workflow, contains('package_downloader'));
    expect(workflow, contains('bash tool/ci/publish_dry_run.sh'));
    expect(workflow, contains('flutter build apk --debug'));
    expect(workflow, contains('macos-latest'));
    expect(workflow, contains('flutter build ios --simulator --debug'));
    expect(workflow, contains('flutter build macos --debug'));
    expect(workflow, contains('windows-latest'));
    expect(workflow, contains('flutter build windows --debug'));
    expect(workflow, contains('ctest --test-dir'));
    expect(workflow, contains('working-directory: example/android'));
    expect(
      workflow,
      contains(
        '../../android/gradlew :flutter_app_updater:testDebugUnitTest '
        ':flutter_app_updater:lintDebug :app:processDebugMainManifest',
      ),
    );
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
