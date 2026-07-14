import '../manifest/update_manifest.dart';
import '../manifest/manifest_signature.dart';

sealed class UpdateSource {
  const UpdateSource();

  factory UpdateSource.manifest({
    required Uri manifestUrl,
    required String expectedAppId,
    Map<String, String>? headers,
    bool allowInsecureLoopback,
    ManifestSignaturePolicy? signaturePolicy,
  }) = ManifestUpdateSource;

  const factory UpdateSource.staticManifest({
    required UpdateManifest manifest,
  }) = StaticManifestUpdateSource;
}

class ManifestUpdateSource extends UpdateSource {
  final Uri manifestUrl;
  final String expectedAppId;
  final Map<String, String>? headers;
  final bool allowInsecureLoopback;
  final ManifestSignaturePolicy signaturePolicy;

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

class StaticManifestUpdateSource extends UpdateSource {
  final UpdateManifest manifest;

  const StaticManifestUpdateSource({
    required this.manifest,
  });
}
