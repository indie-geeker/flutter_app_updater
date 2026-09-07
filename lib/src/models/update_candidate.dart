import 'package:flutter/foundation.dart';

import '../actions/update_action.dart';
import 'update_policy.dart';

/// A release that can be evaluated and delivered by the updater.
///
/// The const constructor retains the supplied list. [snapshot] copies and
/// freezes that list at parser and updater boundaries.
///
/// Actions remain in publisher-defined order. After policy and capability
/// filtering, the first supported action becomes the recommendation.
class UpdateCandidate {
  /// The release's semantic version.
  final String version;

  /// The optional monotonically increasing build number.
  final String? buildNumber;

  /// The release channel, such as `stable` or `beta`.
  final String channel;

  /// The Flutter target platform for this release.
  final TargetPlatform platform;

  /// The target architecture, or `null` for a universal release.
  final String? architecture;

  /// Human-readable release notes supplied by the publisher.
  final String releaseNotes;

  /// The publisher timestamp for the release, when available.
  final DateTime? releasedAt;

  /// The host-facing recommendation and support policy.
  final UpdatePolicy policy;

  /// Ordered delivery alternatives for the release.
  final List<UpdateAction> actions;

  /// Creates a release candidate, retaining the supplied action list.
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

  /// Copies the release with an independent, unmodifiable action list.
  UpdateCandidate snapshot() => UpdateCandidate(
        version: version,
        buildNumber: buildNumber,
        channel: channel,
        platform: platform,
        architecture: architecture,
        releaseNotes: releaseNotes,
        releasedAt: releasedAt,
        policy: policy,
        actions: List.unmodifiable(actions),
      );
}
