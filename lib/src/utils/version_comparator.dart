import 'package:pub_semver/pub_semver.dart';

/// Utilities for comparing application versions.
///
/// Supports semantic versions, prerelease identifiers, build metadata, and an
/// optional `v` prefix. Common shortened versions such as `1` and `1.2`
/// are normalized to `1.0.0` and `1.2.0`.
class VersionComparator {
  /// Compares [currentVersion] with [newVersion].
  ///
  /// Returns a negative value when the new version is newer, zero when equal,
  /// and a positive value when the current version is newer. Build metadata
  /// does not affect precedence.
  static int compare(String currentVersion, String newVersion) {
    final current = _parseVersion(currentVersion, includeBuild: false);
    final newer = _parseVersion(newVersion, includeBuild: false);
    return current.compareTo(newer);
  }

  /// Whether [newVersion] has higher precedence than [currentVersion].
  static bool hasUpdate(String currentVersion, String newVersion) {
    return compare(currentVersion, newVersion) < 0;
  }

  /// Whether [version] is a supported semantic-version input.
  ///
  /// More than three numeric segments, empty segments, leading zeroes, and
  /// malformed prerelease or build identifiers are rejected.
  static bool isValidVersion(String version) {
    try {
      if (_hasLeadingZeroNumericIdentifiers(version)) {
        return false;
      }
      _parseVersion(version);
      return true;
    } on FormatException {
      return false;
    }
  }

  static bool _hasLeadingZeroNumericIdentifiers(String version) {
    var normalized = version.trim();
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }

    final suffixIndex = _firstSuffixIndex(normalized);
    final core =
        suffixIndex < 0 ? normalized : normalized.substring(0, suffixIndex);
    if (core.split('.').any(_hasLeadingZero)) {
      return true;
    }

    final preReleaseIndex = normalized.indexOf('-');
    if (preReleaseIndex < 0) {
      return false;
    }
    final buildIndex = normalized.indexOf('+', preReleaseIndex);
    final preRelease = normalized.substring(
      preReleaseIndex + 1,
      buildIndex < 0 ? normalized.length : buildIndex,
    );
    return preRelease.split('.').any((identifier) {
      return RegExp(r'^\d+$').hasMatch(identifier) &&
          _hasLeadingZero(identifier);
    });
  }

  static bool _hasLeadingZero(String identifier) {
    return identifier.length > 1 && identifier.startsWith('0');
  }

  static Version _parseVersion(
    String version, {
    bool includeBuild = true,
  }) {
    var normalized = version.trim();
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }

    final suffixIndex = _firstSuffixIndex(normalized);
    final core =
        suffixIndex < 0 ? normalized : normalized.substring(0, suffixIndex);
    var suffix = suffixIndex < 0 ? '' : normalized.substring(suffixIndex);
    final segments = core.split('.');
    if (segments.isEmpty ||
        segments.length > 3 ||
        segments.any((segment) =>
            segment.isEmpty || !RegExp(r'^\d+$').hasMatch(segment))) {
      throw FormatException('Could not parse "$version".');
    }

    while (segments.length < 3) {
      segments.add('0');
    }

    if (!includeBuild) {
      final buildIndex = suffix.indexOf('+');
      if (buildIndex >= 0) {
        suffix = suffix.substring(0, buildIndex);
      }
    }

    normalized = '${segments.join('.')}$suffix';
    return Version.parse(normalized);
  }

  static int _firstSuffixIndex(String version) {
    final preReleaseIndex = version.indexOf('-');
    final buildIndex = version.indexOf('+');
    if (preReleaseIndex < 0) return buildIndex;
    if (buildIndex < 0) return preReleaseIndex;
    return preReleaseIndex < buildIndex ? preReleaseIndex : buildIndex;
  }
}
