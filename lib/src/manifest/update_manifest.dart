import '../models/update_candidate.dart';

class UpdateManifest {
  final int schemaVersion;
  final String appId;
  final String channel;
  final List<UpdateCandidate> releases;

  const UpdateManifest({
    required this.schemaVersion,
    required this.appId,
    required this.channel,
    required this.releases,
  });
}
