import '../manifest/update_manifest.dart';

sealed class UpdateSource {
  const UpdateSource();

  factory UpdateSource.manifest({
    required Uri manifestUrl,
    required String expectedAppId,
    Map<String, String>? headers,
  }) = ManifestUpdateSource;

  const factory UpdateSource.staticManifest({
    required UpdateManifest manifest,
  }) = StaticManifestUpdateSource;
}

class ManifestUpdateSource extends UpdateSource {
  final Uri manifestUrl;
  final String expectedAppId;
  final Map<String, String>? headers;

  factory ManifestUpdateSource({
    required Uri manifestUrl,
    required String expectedAppId,
    Map<String, String>? headers,
  }) {
    final normalizedAppId = expectedAppId.trim();
    if (normalizedAppId.isEmpty) {
      throw ArgumentError.value(
        expectedAppId,
        'expectedAppId',
        'must not be blank',
      );
    }
    return ManifestUpdateSource._(
      manifestUrl: manifestUrl,
      expectedAppId: normalizedAppId,
      headers: headers,
    );
  }

  const ManifestUpdateSource._({
    required this.manifestUrl,
    required this.expectedAppId,
    this.headers,
  });
}

class StaticManifestUpdateSource extends UpdateSource {
  final UpdateManifest manifest;

  const StaticManifestUpdateSource({
    required this.manifest,
  });
}
