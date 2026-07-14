import '../models/update_candidate.dart';

/// Parsed v3 update manifest for one application and release channel.
class UpdateManifest {
  /// Manifest schema version; remote input currently requires version 3.
  final int schemaVersion;

  /// Application identifier bound to the host's `expectedAppId`.
  final String appId;

  /// Default release channel described by the manifest.
  final String channel;

  /// Candidate releases in publisher-provided order.
  final List<UpdateCandidate> releases;

  /// Creates a typed manifest, typically for a trusted local adapter.
  const UpdateManifest({
    required this.schemaVersion,
    required this.appId,
    required this.channel,
    required this.releases,
  });
}
