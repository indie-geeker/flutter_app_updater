import 'package:flutter/foundation.dart';

import '../actions/update_action.dart';
import '../models/update_candidate.dart';
import '../models/update_error_code.dart';
import '../models/update_policy.dart';
import '../utils/version_comparator.dart';

class UpdateSelector {
  final String installedVersion;
  final String? installedBuildNumber;
  final TargetPlatform platform;
  final String? architecture;
  final String channel;

  const UpdateSelector({
    required this.installedVersion,
    this.installedBuildNumber,
    required this.platform,
    this.architecture,
    required this.channel,
  });

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

sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class UpdateAvailable extends UpdateCheckResult {
  final UpdateCandidate candidate;
  final UpdateAction recommendedAction;
  final List<UpdateAction> actions;
  final bool isRequired;

  const UpdateAvailable({
    required this.candidate,
    required this.recommendedAction,
    required this.actions,
    this.isRequired = false,
  });
}

class UpdateNotAvailable extends UpdateCheckResult {
  const UpdateNotAvailable();
}

class UpdateCheckFailed extends UpdateCheckResult {
  final UpdateErrorCode code;
  final String message;

  const UpdateCheckFailed({
    required this.code,
    required this.message,
  });
}
