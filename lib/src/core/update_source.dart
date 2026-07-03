import '../manifest/update_manifest.dart';

sealed class UpdateSource {
  const UpdateSource();

  const factory UpdateSource.manifest({
    required Uri manifestUrl,
    Map<String, String>? headers,
  }) = ManifestUpdateSource;

  const factory UpdateSource.staticManifest({
    required UpdateManifest manifest,
  }) = StaticManifestUpdateSource;
}

class ManifestUpdateSource extends UpdateSource {
  final Uri manifestUrl;
  final Map<String, String>? headers;

  const ManifestUpdateSource({
    required this.manifestUrl,
    this.headers,
  });
}

class StaticManifestUpdateSource extends UpdateSource {
  final UpdateManifest manifest;

  const StaticManifestUpdateSource({
    required this.manifest,
  });
}
