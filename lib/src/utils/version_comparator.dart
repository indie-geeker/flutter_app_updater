/// 应用版本比较工具类
///
/// 用于比较两个版本号的大小，支持常见的版本号格式：
/// - 语义化版本 (Semantic Versioning): 如 1.2.3
/// - 带构建号版本: 如 1.2.3+4
/// - 带预发布标识版本: 如 1.2.3-alpha.1
class VersionComparator {
  /// 比较两个版本号
  ///
  /// [currentVersion] 当前版本号
  /// [newVersion] 新版本号
  ///
  /// 返回值:
  /// - 负数: 如果 newVersion 大于 currentVersion (有更新)
  /// - 0: 如果两个版本相等
  /// - 正数: 如果 currentVersion 大于 newVersion (无需更新)
  static int compare(String currentVersion, String newVersion) {
    // 清理版本号字符串
    final cleanCurrentVersion = _cleanVersion(currentVersion);
    final cleanNewVersion = _cleanVersion(newVersion);

    // 解析版本号
    final current = _parseVersion(cleanCurrentVersion);
    final newer = _parseVersion(cleanNewVersion);

    // 比较主版本、次版本、修订版本
    for (int i = 0; i < 3; i++) {
      if (i >= current.length) return -1; // 新版本有更多部分
      if (i >= newer.length) return 1;    // 当前版本有更多部分

      final currentPart = current[i];
      final newPart = newer[i];

      final comparison = currentPart.compareTo(newPart);
      if (comparison != 0) return comparison;
    }

    // 主要版本号相同，检查预发布版本
    return _comparePreRelease(cleanCurrentVersion, cleanNewVersion);
  }

  /// 检查是否有可用更新
  ///
  /// [currentVersion] 当前版本号
  /// [newVersion] 新版本号
  ///
  /// 如果新版本大于当前版本，返回 true
  static bool hasUpdate(String currentVersion, String newVersion) {
    return compare(currentVersion, newVersion) < 0;
  }

  /// 清理版本号字符串
  static String _cleanVersion(String version) {
    // 移除版本号前的'v'或'V'前缀
    if (version.toLowerCase().startsWith('v')) {
      version = version.substring(1);
    }

    // 移除构建元数据部分 (例如 1.2.3+4 中的 +4)
    final buildIndex = version.indexOf('+');
    if (buildIndex > 0) {
      version = version.substring(0, buildIndex);
    }

    return version.trim();
  }

  /// 解析版本号为数字列表
  static List<int> _parseVersion(String version) {
    // 分离预发布标识符
    final parts = version.split('-');
    final versionCore = parts[0];

    // 解析主版本号部分
    final segments = versionCore.split('.');
    final result = <int>[];

    for (final segment in segments) {
      final number = int.tryParse(segment);
      result.add(number ?? 0);
    }

    // 补全至少3个部分 (主版本.次版本.修订版本)
    while (result.length < 3) {
      result.add(0);
    }

    return result;
  }

  /// 比较预发布版本
  static int _comparePreRelease(String currentVersion, String newVersion) {
    // 检查是否有预发布标识符
    final hasCurrent = currentVersion.contains('-');
    final hasNew = newVersion.contains('-');

    // 预发布版本比较规则：
    // 1. 有预发布标识的版本比没有预发布标识的版本低
    // 2. 只有当两个版本都有预发布标识时才进行比较

    if (!hasCurrent && !hasNew) return 0;   // 都没有预发布标识
    if (!hasCurrent && hasNew) return 1;    // 新版本有预发布标识，当前没有
    if (hasCurrent && !hasNew) return -1;   // 当前版本有预发布标识，新版本没有

    // 两者都有预发布标识，比较预发布标识
    final currentPre = currentVersion.split('-')[1];
    final newPre = newVersion.split('-')[1];

    // 预发布标识的字典顺序比较
    // 例如: alpha < beta < rc
    return currentPre.compareTo(newPre);
  }
}