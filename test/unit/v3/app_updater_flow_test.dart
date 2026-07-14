import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdater convenience flow', () {
    test('manifest factory builds a checkable updater', () async {
      final updater = AppUpdater.manifest(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        expectedAppId: 'com.example.app',
        installedVersion: '1.0.0',
        platform: TargetPlatform.android,
        architecture: 'arm64',
        channel: 'stable',
        manifestFetcher: _FakeManifestFetcher(_manifestJson()),
      );

      final result = await updater.checkAndPrepare();

      expect(result, isA<PreparedUpdateAvailable>());
      final available = result as PreparedUpdateAvailable;
      expect(available.candidate.version, '2.0.0');
      expect(
          available.recommendedAction, isA<DownloadAndInstallPackageAction>());
      expect(available.actions, hasLength(1));
      expect(available.isRequired, isFalse);
    });

    test('performRecommended executes the prepared recommended action',
        () async {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 42,
        sha256: 'a' * 64,
      );
      final executor = _RecordingExecutor(
        supportsAction: (candidate) => candidate is DownloadPackageAction,
      );
      final updater = AppUpdater(
        source: UpdateSource.staticManifest(
          manifest: UpdateManifest(
            schemaVersion: 3,
            appId: 'com.example.app',
            channel: 'stable',
            releases: [
              UpdateCandidate(
                version: '2.0.0',
                channel: 'stable',
                platform: TargetPlatform.android,
                architecture: 'arm64',
                releaseNotes: 'Bug fixes',
                policy: const UpdatePolicy(),
                actions: [action],
              ),
            ],
          ),
        ),
        selector: const UpdateSelector(
          installedVersion: '1.0.0',
          platform: TargetPlatform.android,
          architecture: 'arm64',
          channel: 'stable',
        ),
        executors: [executor],
      );

      final result = await updater.checkAndPrepare();
      final actionResult =
          await updater.performRecommended(result as PreparedUpdateAvailable);

      expect(actionResult.isSuccess, isTrue);
      expect(executor.performedActions, [same(action)]);
    });

    test('storeOnly keeps executable store actions in manifest order',
        () async {
      final download = _downloadAction('first.apk');
      final store = _storeAction();
      final installer = _installerAction();
      final updater = _updaterForActions(
        [download, store, installer],
        distributionPolicy: UpdateDistributionPolicy.storeOnly,
        executors: [_RecordingExecutor(supportsAction: (_) => true)],
      );

      final result = await updater.checkAndPrepare();

      expect(result, isA<PreparedUpdateAvailable>());
      final available = result as PreparedUpdateAvailable;
      expect(available.actions, [same(store)]);
      expect(available.recommendedAction, same(store));
    });

    test('selfHostedOnly removes official store and market actions', () async {
      final download = _downloadAction('app.apk');
      final installer = _installerAction();
      final updater = _updaterForActions(
        [_storeAction(), _marketAction(), download, installer],
        distributionPolicy: UpdateDistributionPolicy.selfHostedOnly,
        executors: [_RecordingExecutor(supportsAction: (_) => true)],
      );

      final result = await updater.checkAndPrepare();

      expect(result, isA<PreparedUpdateAvailable>());
      final available = result as PreparedUpdateAvailable;
      expect(available.actions, [same(download), same(installer)]);
      expect(available.recommendedAction, same(download));
    });

    test('unsupported actions are removed without reordering', () async {
      final store = _storeAction();
      final download = _downloadAction('unsupported.apk');
      final installer = _installerAction();
      final updater = _updaterForActions(
        [store, download, installer],
        executors: [
          _RecordingExecutor(
            supportsAction: (action) =>
                action is OpenStoreAction || action is OpenInstallerAction,
          ),
        ],
      );

      final result = await updater.checkAndPrepare();

      expect(result, isA<PreparedUpdateAvailable>());
      final available = result as PreparedUpdateAvailable;
      expect(available.actions, [same(store), same(installer)]);
      expect(available.recommendedAction, same(store));
    });

    test('empty policy and capability intersection is structured failure',
        () async {
      final updater = _updaterForActions(
        [_downloadAction('app.apk')],
        distributionPolicy: UpdateDistributionPolicy.storeOnly,
        executors: [_RecordingExecutor(supportsAction: (_) => true)],
      );

      final result = await updater.checkAndPrepare();

      expect(result, isA<PreparedUpdateCheckFailed>());
      expect(
        (result as PreparedUpdateCheckFailed).code,
        UpdateErrorCode.noSupportedAction,
      );
    });
  });
}

AppUpdater _updaterForActions(
  List<UpdateAction> actions, {
  UpdateDistributionPolicy distributionPolicy = UpdateDistributionPolicy.any,
  required List<UpdateActionExecutor> executors,
}) {
  return AppUpdater(
    source: UpdateSource.staticManifest(
      manifest: UpdateManifest(
        schemaVersion: 3,
        appId: 'com.example.app',
        channel: 'stable',
        releases: [
          UpdateCandidate(
            version: '2.0.0',
            channel: 'stable',
            platform: TargetPlatform.android,
            architecture: 'arm64',
            releaseNotes: 'Bug fixes',
            policy: const UpdatePolicy(),
            actions: actions,
          ),
        ],
      ),
    ),
    selector: const UpdateSelector(
      installedVersion: '1.0.0',
      platform: TargetPlatform.android,
      architecture: 'arm64',
      channel: 'stable',
    ),
    platform: TargetPlatform.android,
    distributionPolicy: distributionPolicy,
    executors: executors,
  );
}

OpenStoreAction _storeAction() => OpenStoreAction(
      store: StoreKind.googlePlay,
      storeUrl: Uri.parse(
        'https://play.google.com/store/apps/details?id=com.example.app',
      ),
    );

OpenAndroidMarketAction _marketAction() => const OpenAndroidMarketAction(
      market: AndroidMarketKind.xiaomi,
      targetPackageName: 'com.example.app',
    );

DownloadPackageAction _downloadAction(String name) => DownloadPackageAction(
      packageUrl: Uri.parse('https://example.com/$name'),
      packageType: PackageType.apk,
      packageSizeBytes: 42,
      sha256: 'a' * 64,
    );

OpenInstallerAction _installerAction() => OpenInstallerAction(
      installerUrl: Uri.parse('https://example.com/app.msi'),
      installerType: InstallerType.msi,
      installerSizeBytes: 42,
      sha256: 'b' * 64,
    );

class _FakeManifestFetcher implements ManifestFetcher {
  final Map<String, Object?> json;

  _FakeManifestFetcher(this.json);

  @override
  Future<Map<String, Object?>> fetch(ManifestUpdateSource source) async => json;
}

Map<String, Object?> _manifestJson() {
  return {
    'schemaVersion': 3,
    'appId': 'com.example.app',
    'channel': 'stable',
    'releases': [
      {
        'version': '2.0.0',
        'channel': 'stable',
        'platform': 'android',
        'architecture': 'arm64',
        'releaseNotes': 'Bug fixes',
        'actions': [
          {
            'type': 'downloadAndInstallPackage',
            'packageUrl': 'https://example.com/app.apk',
            'packageType': 'apk',
            'packageSizeBytes': 42,
            'sha256': 'a' * 64,
          },
        ],
      },
    ],
  };
}

class _RecordingExecutor implements UpdateActionExecutor {
  final bool Function(UpdateAction action) supportsAction;
  final performedActions = <UpdateAction>[];

  _RecordingExecutor({
    required this.supportsAction,
  });

  @override
  bool supports(UpdateAction action) => supportsAction(action);

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    performedActions.add(action);
    return const UpdateActionResult.success();
  }
}
