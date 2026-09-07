/// Internal transfer metadata shared by all verified artifact types.
class ArtifactDescriptor {
  /// Absolute artifact URL.
  final Uri packageUrl;

  /// Exact expected byte count.
  final int packageSizeBytes;

  /// Expected SHA-256 digest.
  final String sha256;

  /// Creates transfer metadata without imposing a platform package type.
  const ArtifactDescriptor(
      {required this.packageUrl,
      required this.packageSizeBytes,
      required this.sha256});
}
