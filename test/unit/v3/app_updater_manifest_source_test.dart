import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater/src/manifest/manifest_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdater manifest source', () {
    test('fetches a remote manifest and selects an update', () async {
      final fetcher = _FakeManifestFetcher(_manifestJson(version: '2.0.0'));
      final source = UpdateSource.manifest(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        expectedAppId: 'com.example.app',
      );
      final updater = AppUpdater(
        source: source,
        manifestFetcher: fetcher,
      );

      final result = await updater.check(selector: _selector());

      expect(fetcher.sources, [source]);
      expect(result, isA<UpdateAvailable>());
      expect((result as UpdateAvailable).candidate.version, '2.0.0');
    });

    test('passes configured headers to the manifest fetcher', () async {
      final headers = {'authorization': 'Bearer token'};
      final fetcher = _FakeManifestFetcher(_manifestJson(version: '2.0.0'));
      final source = UpdateSource.manifest(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        expectedAppId: 'com.example.app',
        headers: headers,
      );
      final updater = AppUpdater(
        source: source,
        manifestFetcher: fetcher,
      );

      await updater.check(selector: _selector());

      expect(fetcher.sources.single.headers, headers);
    });

    test('rejects a remote manifest for a different application', () async {
      final updater = AppUpdater(
        source: UpdateSource.manifest(
          manifestUrl: Uri.parse('https://example.com/update.json'),
          expectedAppId: 'com.example.expected',
        ),
        manifestFetcher: _FakeManifestFetcher(
          _manifestJson(version: '2.0.0', appId: 'com.example.other'),
        ),
      );

      final result = await updater.check(selector: _selector());

      expect(result, isA<UpdateCheckFailed>());
      expect(
        (result as UpdateCheckFailed).code,
        UpdateErrorCode.appIdMismatch,
      );
    });

    test('requires a nonblank application ID for remote sources', () {
      expect(
        () => UpdateSource.manifest(
          manifestUrl: Uri.parse('https://example.com/update.json'),
          expectedAppId: '  ',
        ),
        throwsArgumentError,
      );
      expect(
        () => ManifestUpdateSource(
          manifestUrl: Uri.parse('https://example.com/update.json'),
          expectedAppId: '',
        ),
        throwsArgumentError,
      );
    });

    test('maps non-200 fetch failures to manifestFetchFailed', () async {
      final updater = AppUpdater(
        source: UpdateSource.manifest(
          manifestUrl: Uri.parse('https://example.com/update.json'),
          expectedAppId: 'com.example.app',
        ),
        manifestFetcher: _FakeManifestFetcher.throwing(
          const ManifestFetchException(
            message: 'Manifest request failed with HTTP 500.',
            statusCode: 500,
          ),
        ),
      );

      final result = await updater.check(selector: _selector());

      expect(result, isA<UpdateCheckFailed>());
      expect(
        (result as UpdateCheckFailed).code,
        UpdateErrorCode.manifestFetchFailed,
      );
    });

    test('maps invalid JSON to manifestInvalid', () async {
      final updater = AppUpdater(
        source: UpdateSource.manifest(
          manifestUrl: Uri.parse('https://example.com/update.json'),
          expectedAppId: 'com.example.app',
        ),
        manifestFetcher: _FakeManifestFetcher.throwing(
          const FormatException('Unexpected character.'),
        ),
      );

      final result = await updater.check(selector: _selector());

      expect(result, isA<UpdateCheckFailed>());
      expect(
        (result as UpdateCheckFailed).code,
        UpdateErrorCode.manifestInvalid,
      );
    });

    test('maps thrown network exceptions to manifestFetchFailed', () async {
      final updater = AppUpdater(
        source: UpdateSource.manifest(
          manifestUrl: Uri.parse('https://example.com/update.json'),
          expectedAppId: 'com.example.app',
        ),
        manifestFetcher: _FakeManifestFetcher.throwing(
          StateError('network down'),
        ),
      );

      final result = await updater.check(selector: _selector());

      expect(result, isA<UpdateCheckFailed>());
      expect(
        (result as UpdateCheckFailed).code,
        UpdateErrorCode.manifestFetchFailed,
      );
    });

    test('rejects remote actions that violate the remote policy', () async {
      final updater = AppUpdater(
        source: UpdateSource.manifest(
          manifestUrl: Uri.parse('https://example.com/update.json'),
          expectedAppId: 'com.example.app',
        ),
        manifestFetcher: _FakeManifestFetcher(
          _manifestJson(
            version: '2.0.0',
            action: {
              'type': 'installPackage',
              'packagePath': '/tmp/untrusted.apk',
            },
          ),
        ),
      );

      final result = await updater.check(selector: _selector());

      expect(result, isA<UpdateCheckFailed>());
      expect(
        (result as UpdateCheckFailed).code,
        UpdateErrorCode.unsupportedActionType,
      );
    });

    test('invalid installed version is configurationInvalid for both sources',
        () async {
      for (final updater in _updatersForManifest(
        _manifestJson(version: '2.0.0'),
      )) {
        final result = await updater.check(
          selector: _selector(installedVersion: 'not-a-version'),
        );

        expect(result, isA<UpdateCheckFailed>());
        expect(
          (result as UpdateCheckFailed).code,
          UpdateErrorCode.configurationInvalid,
        );
      }
    });

    test('invalid installed build number is configurationInvalid', () async {
      final updater = _updatersForManifest(
        _manifestJson(version: '2.0.0'),
      ).first;

      final result = await updater.check(
        selector: const UpdateSelector(
          installedVersion: '1.0.0',
          installedBuildNumber: '-1',
          platform: TargetPlatform.android,
          architecture: 'arm64',
          channel: 'stable',
        ),
      );

      expect(result, isA<UpdateCheckFailed>());
      expect(
        (result as UpdateCheckFailed).code,
        UpdateErrorCode.configurationInvalid,
      );
    });

    test(
        'invalid minimum-supported version is configurationInvalid for both sources',
        () async {
      for (final updater in _updatersWithInvalidMinimumSupportedVersion()) {
        final result = await updater.check(selector: _selector());

        expect(result, isA<UpdateCheckFailed>());
        expect(
          (result as UpdateCheckFailed).code,
          UpdateErrorCode.configurationInvalid,
        );
      }
    });

    test('checkAndPrepare does not leak invalid version exceptions', () async {
      for (final updater in _updatersForManifest(
        _manifestJson(version: '2.0.0'),
      )) {
        final result = await updater.checkAndPrepare(
          selector: _selector(installedVersion: 'not-a-version'),
        );

        expect(result, isA<PreparedUpdateCheckFailed>());
        expect(
          (result as PreparedUpdateCheckFailed).code,
          UpdateErrorCode.configurationInvalid,
        );
      }
    });
  });
}

List<AppUpdater> _updatersForManifest(Map<String, Object?> json) {
  final manifest = const ManifestParser().parse(json);
  return [
    AppUpdater(
      source: UpdateSource.staticManifest(manifest: manifest),
    ),
    AppUpdater(
      source: UpdateSource.manifest(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        expectedAppId: 'com.example.app',
      ),
      manifestFetcher: _FakeManifestFetcher(json),
    ),
  ];
}

List<AppUpdater> _updatersWithInvalidMinimumSupportedVersion() {
  final json = _manifestJson(
    version: '2.0.0',
    minSupportedVersion: 'not-a-version',
  );
  final staticManifest = UpdateManifest(
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
        policy: const UpdatePolicy(
          minSupportedVersion: 'not-a-version',
        ),
        actions: [
          OpenStoreAction(
            store: StoreKind.googlePlay,
            storeUrl: Uri.parse(
              'https://play.google.com/store/apps/details?id=com.example.app',
            ),
          ),
        ],
      ),
    ],
  );
  return [
    AppUpdater(source: UpdateSource.staticManifest(manifest: staticManifest)),
    AppUpdater(
      source: UpdateSource.manifest(
        manifestUrl: Uri.parse('https://example.com/update.json'),
        expectedAppId: 'com.example.app',
      ),
      manifestFetcher: _FakeManifestFetcher(json),
    ),
  ];
}

class _FakeManifestFetcher implements ManifestFetcher {
  final Map<String, Object?>? _json;
  final Object? _failure;
  final sources = <ManifestUpdateSource>[];

  _FakeManifestFetcher(this._json) : _failure = null;

  _FakeManifestFetcher.throwing(this._failure) : _json = null;

  @override
  Future<Map<String, Object?>> fetch(ManifestUpdateSource source) async {
    sources.add(source);
    final failure = _failure;
    if (failure != null) {
      throw failure;
    }
    return _json!;
  }
}

UpdateSelector _selector({String installedVersion = '1.0.0'}) {
  return UpdateSelector(
    installedVersion: installedVersion,
    platform: TargetPlatform.android,
    architecture: 'arm64',
    channel: 'stable',
  );
}

Map<String, Object?> _manifestJson({
  required String version,
  String appId = 'com.example.app',
  String? minSupportedVersion,
  Map<String, Object?>? action,
}) {
  return {
    'schemaVersion': 3,
    'appId': appId,
    'channel': 'stable',
    'releases': [
      {
        'version': version,
        'buildNumber': '20',
        'channel': 'stable',
        'platform': 'android',
        'architecture': 'arm64',
        'releaseNotes': 'Bug fixes',
        'releasedAt': '2026-07-03T00:00:00Z',
        if (minSupportedVersion != null)
          'policy': {'minSupportedVersion': minSupportedVersion},
        'actions': [
          action ??
              {
                'type': 'openStore',
                'store': 'googlePlay',
                'storeUrl':
                    'https://play.google.com/store/apps/details?id=com.example.app',
              },
        ],
      },
    ],
  };
}
