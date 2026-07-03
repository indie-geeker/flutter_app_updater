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
    final candidates = releases.where(_matchesTarget).where((release) {
      return _isNewer(release);
    }).toList();

    if (candidates.isEmpty) {
      return const UpdateNotAvailable();
    }

    candidates.sort((left, right) {
      final versionCompare =
          VersionComparator.compare(right.version, left.version);
      if (versionCompare != 0) {
        return versionCompare;
      }
      return _buildNumberForSort(right).compareTo(_buildNumberForSort(left));
    });

    final candidate = candidates.first;
    final isRequired = _isRequired(candidate);
    final recommendedAction = _recommendedAction(candidate, isRequired);
    if (recommendedAction == null) {
      return UpdateCheckFailed(
        code: UpdateErrorCode.noSupportedAction,
        message: 'No supported action for ${candidate.version}.',
      );
    }

    return UpdateAvailable(
      candidate: candidate,
      recommendedAction: recommendedAction,
      isRequired: isRequired,
    );
  }

  bool _matchesTarget(UpdateCandidate release) {
    return release.platform == platform &&
        release.channel == channel &&
        _matchesArchitecture(release);
  }

  bool _matchesArchitecture(UpdateCandidate release) {
    final releaseArchitecture = release.architecture;
    if (releaseArchitecture == null || architecture == null) {
      return true;
    }
    return releaseArchitecture == architecture;
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

  UpdateAction? _recommendedAction(
    UpdateCandidate candidate,
    bool isRequired,
  ) {
    if (candidate.actions.isEmpty) {
      return null;
    }

    if (isRequired) {
      for (final action in candidate.actions) {
        if (action is DownloadAndInstallPackageAction ||
            action is DownloadPackageAction ||
            action is OpenInstallerAction) {
          return action;
        }
      }
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
  final bool isRequired;

  const UpdateAvailable({
    required this.candidate,
    required this.recommendedAction,
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
