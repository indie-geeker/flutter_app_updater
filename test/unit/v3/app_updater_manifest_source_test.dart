import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdater manifest source', () {
    test('fetches a remote manifest and selects an update', () async {
      final fetcher = _FakeManifestFetcher(_manifestJson(version: '2.0.0'));
      final source = UpdateSource.manifest(
        manifestUrl: Uri.parse('https://example.com/update.json'),
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
        headers: headers,
      );
      final updater = AppUpdater(
        source: source,
        manifestFetcher: fetcher,
      );

      await updater.check(selector: _selector());

      expect(fetcher.sources.single.headers, headers);
    });

    test('maps non-200 fetch failures to manifestFetchFailed', () async {
      final updater = AppUpdater(
        source: UpdateSource.manifest(
          manifestUrl: Uri.parse('https://example.com/update.json'),
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
  });
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

UpdateSelector _selector() {
  return const UpdateSelector(
    installedVersion: '1.0.0',
    platform: TargetPlatform.android,
    architecture: 'arm64',
    channel: 'stable',
  );
}

Map<String, Object?> _manifestJson({
  required String version,
}) {
  return {
    'schemaVersion': 3,
    'appId': 'com.example.app',
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
        'actions': [
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
