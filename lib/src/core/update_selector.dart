import 'package:flutter/foundation.dart';

import '../actions/update_action.dart';
import '../models/update_candidate.dart';
import '../models/update_error_code.dart';
import '../models/update_policy.dart';
import '../utils/version_comparator.dart';

/// Selects the newest compatible release for one installed application.
///
/// Platform and channel must match exactly. A release with a specific
/// architecture matches only when [architecture] is known and equal; otherwise
/// only a universal release can match. When both exist, the exact architecture
/// wins over the universal release at the same version and build number.
class UpdateSelector {
  /// The currently installed semantic version.
  final String installedVersion;

  /// The current build number used to break equal-version ties.
  final String? installedBuildNumber;

  /// The runtime platform that a release must target.
  final TargetPlatform platform;

  /// The runtime architecture, or `null` when it cannot be determined.
  final String? architecture;

  /// The runtime release channel that a candidate must match.
  final String channel;

  /// Creates a selector for the installed application state.
  const UpdateSelector({
    required this.installedVersion,
    this.installedBuildNumber,
    required this.platform,
    this.architecture,
    required this.channel,
  });

  /// Selects a newer compatible release from [releases].
  ///
  /// Returns [UpdateNotAvailable] when no compatible newer release exists.
  /// The returned recommendation is the first action in manifest order;
  /// `AppUpdater` subsequently applies distribution and executor capabilities.
  /// Throws [FormatException] when an input version or build number is invalid.
  UpdateCheckResult select(List<UpdateCandidate> releases) {
    final newerTargetReleases = releases
        .where(_matchesPlatformAndChannel)
        .where(_isNewer)
        .toList(growable: false);
    final candidates =
        newerTargetReleases.where(_matchesArchitecture).toList(growable: false);

    if (candidates.isEmpty) {
      if (newerTargetReleases.isNotEmpty) {
        return const UpdateCheckFailed(
          code: UpdateErrorCode.noMatchingRelease,
          message: 'No release matches the runtime architecture.',
        );
      }
      return const UpdateNotAvailable();
    }

    candidates.sort((left, right) {
      final versionCompare =
          VersionComparator.compare(right.version, left.version);
      if (versionCompare != 0) {
        return versionCompare;
      }
      final buildCompare =
          _buildNumberForSort(right).compareTo(_buildNumberForSort(left));
      if (buildCompare != 0) {
        return buildCompare;
      }
      return _architectureSpecificity(right)
          .compareTo(_architectureSpecificity(left));
    });

    final candidate = candidates.first;
    final isRequired = _isRequired(candidate);
    final recommendedAction = _recommendedAction(candidate);
    if (recommendedAction == null) {
      return UpdateCheckFailed(
        code: UpdateErrorCode.noSupportedAction,
        message: 'No supported action for ${candidate.version}.',
      );
    }

    return UpdateAvailable(
      candidate: candidate,
      recommendedAction: recommendedAction,
      actions: candidate.actions,
      isRequired: isRequired,
    );
  }

  bool _matchesPlatformAndChannel(UpdateCandidate release) {
    return release.platform == platform && release.channel == channel;
  }

  bool _matchesArchitecture(UpdateCandidate release) {
    final releaseArchitecture = release.architecture;
    return releaseArchitecture == null ||
        (architecture != null && releaseArchitecture == architecture);
  }

  int _architectureSpecificity(UpdateCandidate release) {
    return release.architecture == architecture ? 1 : 0;
  }

  bool _isNewer(UpdateCandidate release) {
    final versionCompare =
        VersionComparator.compare(installedVersion, release.version);
    if (versionCompare < 0) {
      return true;
    }
    if (versionCompare > 0) {
      return false;
    }

    final installedBuild = int.tryParse(installedBuildNumber ?? '');
    final releaseBuild = int.tryParse(release.buildNumber ?? '');
    if (installedBuild == null || releaseBuild == null) {
      return false;
    }
    return releaseBuild > installedBuild;
  }

  int _buildNumberForSort(UpdateCandidate release) {
    return int.tryParse(release.buildNumber ?? '') ?? -1;
  }

  bool _isRequired(UpdateCandidate candidate) {
    if (candidate.policy.level == UpdatePolicyLevel.required) {
      return true;
    }

    final minSupportedVersion = candidate.policy.minSupportedVersion;
    if (minSupportedVersion == null) {
      return false;
    }

    return VersionComparator.compare(installedVersion, minSupportedVersion) < 0;
  }

  UpdateAction? _recommendedAction(UpdateCandidate candidate) {
    if (candidate.actions.isEmpty) {
      return null;
    }
    return candidate.actions.first;
  }
}

/// Result of checking and selecting an update without performing side effects.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// A compatible newer release and its currently executable actions.
class UpdateAvailable extends UpdateCheckResult {
  /// The selected release candidate.
  final UpdateCandidate candidate;

  /// The first supported action in publisher-defined order.
  final UpdateAction recommendedAction;

  /// All supported actions, preserving publisher-defined order.
  final List<UpdateAction> actions;

  /// Whether release policy requires the host to enforce this update.
  final bool isRequired;

  /// Creates a successful update-selection result.
  const UpdateAvailable({
    required this.candidate,
    required this.recommendedAction,
    required this.actions,
    this.isRequired = false,
  });
}

/// Indicates that no compatible release is newer than the installed build.
class UpdateNotAvailable extends UpdateCheckResult {
  /// Creates a no-update result.
  const UpdateNotAvailable();
}

/// Describes a configuration, trust, fetch, parse, or selection failure.
class UpdateCheckFailed extends UpdateCheckResult {
  /// Stable machine-readable failure code.
  final UpdateErrorCode code;

  /// Human-readable diagnostic suitable for logging or host UI.
  final String message;

  /// Creates a structured check failure.
  const UpdateCheckFailed({
    required this.code,
    required this.message,
  });
}
