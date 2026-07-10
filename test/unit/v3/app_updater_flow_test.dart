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
  });
}

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
