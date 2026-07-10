import 'package:pub_semver/pub_semver.dart';

/// 应用版本比较工具类。
///
/// 支持语义化版本、构建元数据、预发布标识以及可选的 `v` 前缀。为了兼容
/// 常见应用版本输入，`1` 和 `1.2` 会分别标准化为 `1.0.0` 和 `1.2.0`。
class VersionComparator {
  /// 比较两个版本号。
  ///
  /// 返回负数表示 [newVersion] 更新，零表示相等，正数表示
  /// [currentVersion] 更新。构建元数据不参与版本优先级比较。
  static int compare(String currentVersion, String newVersion) {
    final current = _parseVersion(currentVersion, includeBuild: false);
    final newer = _parseVersion(newVersion, includeBuild: false);
    return current.compareTo(newer);
  }

  static bool hasUpdate(String currentVersion, String newVersion) {
    return compare(currentVersion, newVersion) < 0;
  }

  /// 判断版本号是否为支持的语义化格式。
  ///
  /// 超过三个数字段、空数字段或畸形的预发布/构建标识符会被拒绝。
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
