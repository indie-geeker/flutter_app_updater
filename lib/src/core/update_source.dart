sealed class UpdateSource {
  const UpdateSource();

  const factory UpdateSource.manifest({
    required Uri manifestUrl,
    Map<String, String>? headers,
  }) = ManifestUpdateSource;
}

class ManifestUpdateSource extends UpdateSource {
  final Uri manifestUrl;
  final Map<String, String>? headers;

  const ManifestUpdateSource({
    required this.manifestUrl,
    this.headers,
  });
}
