import 'package:flutter/foundation.dart';

import '../actions/update_action.dart';
import 'update_policy.dart';

class UpdateCandidate {
  final String version;
  final String? buildNumber;
  final String channel;
  final TargetPlatform platform;
  final String? architecture;
  final String releaseNotes;
  final DateTime? releasedAt;
  final UpdatePolicy policy;
  final List<UpdateAction> actions;

  const UpdateCandidate({
    required this.version,
    this.buildNumber,
    required this.channel,
    required this.platform,
    this.architecture,
    required this.releaseNotes,
    this.releasedAt,
    required this.policy,
    required this.actions,
  });
}
