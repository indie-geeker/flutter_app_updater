import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/release_metadata.dart';

void main() {
  test('accepts an exact stable tag and changelog heading', () {
    final metadata = ReleaseMetadata.fromContents(
      tag: 'v3.0.0',
      pubspec: _pubspec('3.0.0'),
      changelog: '## Unreleased\n\n## 3.0.0 - 2026-07-10\n',
    );

    expect(metadata.tag, 'v3.0.0');
    expect(metadata.version.toString(), '3.0.0');
    expect(metadata.isPrerelease, isFalse);
  });

  test('rejects a tag that differs from pubspec version', () {
    expect(
      () => ReleaseMetadata.fromContents(
        tag: 'v3.0.1',
        pubspec: _pubspec('3.0.0'),
        changelog: '## 3.0.0\n',
      ),
      throwsA(
        isA<ReleaseMetadataException>().having(
          (error) => error.message,
          'message',
          contains('does not match'),
        ),
      ),
    );
  });

  test('rejects malformed tags and build metadata', () {
    for (final tag in [
      '3.0.0',
      'v3.0',
      'v03.0.0',
      'v3.0.0+build.1',
      'v3.0.0-',
    ]) {
      expect(
        () => ReleaseMetadata.fromContents(
          tag: tag,
          pubspec: _pubspec('3.0.0'),
          changelog: '## 3.0.0\n',
        ),
        throwsA(isA<ReleaseMetadataException>()),
        reason: tag,
      );
    }
  });

  test('requires a changelog heading for the exact version', () {
    expect(
      () => ReleaseMetadata.fromContents(
        tag: 'v3.0.0',
        pubspec: _pubspec('3.0.0'),
        changelog: '## Unreleased\n\n## 2.9.0\n',
      ),
      throwsA(
        isA<ReleaseMetadataException>().having(
          (error) => error.message,
          'message',
          contains('CHANGELOG'),
        ),
      ),
    );
  });

  test('allows exact SemVer prereleases under the selected policy', () {
    final metadata = ReleaseMetadata.fromContents(
      tag: 'v3.1.0-rc.1',
      pubspec: _pubspec('3.1.0-rc.1'),
      changelog: '## 3.1.0-rc.1 - 2026-07-13\n',
    );

    expect(metadata.isPrerelease, isTrue);
    expect(metadata.version.toString(), '3.1.0-rc.1');
  });
}

String _pubspec(String version) => '''
name: flutter_app_updater
version: $version
environment:
  sdk: '>=3.4.0 <4.0.0'
''';
