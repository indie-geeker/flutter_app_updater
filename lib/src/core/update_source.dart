import '../manifest/update_manifest.dart';
import '../manifest/manifest_signature.dart';

/// Describes where `AppUpdater` obtains release metadata.
sealed class UpdateSource {
  const UpdateSource();

  /// Creates a remote v3 manifest source.
  ///
  /// [manifestUrl] must be trusted HTTPS unless loopback HTTP is explicitly
  /// enabled. [expectedAppId] must be nonblank and is compared with the parsed
  /// manifest before release selection. Throws [ArgumentError] for a blank
  /// application identifier.
  factory UpdateSource.manifest({
    required Uri manifestUrl,
    required String expectedAppId,
    Map<String, String>? headers,
    bool allowInsecureLoopback,
    ManifestSignaturePolicy? signaturePolicy,
  }) = ManifestUpdateSource;

  /// Creates a trusted, already typed in-memory manifest source.
  const factory UpdateSource.staticManifest({
    required UpdateManifest manifest,
  }) = StaticManifestUpdateSource;
}

/// Configuration for fetching and authenticating a remote manifest.
class ManifestUpdateSource extends UpdateSource {
  /// The initial manifest endpoint.
  final Uri manifestUrl;

  /// The application identifier the remote manifest must declare.
  final String expectedAppId;

  /// Caller headers sent only while redirects remain on the same origin.
  final Map<String, String>? headers;

  /// Whether plain HTTP is accepted for loopback development endpoints.
  final bool allowInsecureLoopback;

  /// Trusted Ed25519 keys and signature requirements for the source.
  final ManifestSignaturePolicy signaturePolicy;

  /// Creates validated remote-manifest configuration.
  factory ManifestUpdateSource({
    required Uri manifestUrl,
    required String expectedAppId,
    Map<String, String>? headers,
    bool allowInsecureLoopback = false,
    ManifestSignaturePolicy? signaturePolicy,
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
      allowInsecureLoopback: allowInsecureLoopback,
      signaturePolicy: signaturePolicy ?? ManifestSignaturePolicy.optional(),
    );
  }

  const ManifestUpdateSource._({
    required this.manifestUrl,
    required this.expectedAppId,
    this.headers,
    required this.allowInsecureLoopback,
    required this.signaturePolicy,
  });
}

/// A trusted in-memory manifest source, typically used by adapters or tests.
class StaticManifestUpdateSource extends UpdateSource {
  /// The already parsed manifest.
  final UpdateManifest manifest;

  /// Creates an in-memory source from [manifest].
  const StaticManifestUpdateSource({
    required this.manifest,
  });
}
