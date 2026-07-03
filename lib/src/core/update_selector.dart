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
      return VersionComparator.hasUpdate(installedVersion, release.version);
    }).toList();

    if (candidates.isEmpty) {
      return const UpdateNotAvailable();
    }

    candidates.sort((left, right) {
      return VersionComparator.compare(right.version, left.version);
    });

    final candidate = candidates.first;
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

  UpdateAction? _recommendedAction(UpdateCandidate candidate) {
    if (candidate.actions.isEmpty) {
      return null;
    }

    if (candidate.policy.level == UpdatePolicyLevel.required) {
      for (final action in candidate.actions) {
        if (action is DownloadPackageAction || action is OpenInstallerAction) {
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

  const UpdateAvailable({
    required this.candidate,
    required this.recommendedAction,
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
