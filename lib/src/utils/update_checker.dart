import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_app_updater/src/utils/version_comparator.dart';

import '../models/update_error.dart';
import '../models/update_info.dart';
import '../network/http_client.dart';
import '../utils/constants.dart';

/// 定义更新检查器回调函数类型
typedef UpdateCheckerCallback = Future<Map<String, dynamic>> Function();

/// 应用更新检查器
///
/// 负责检查是否有可用的应用更新
class UpdateChecker {
  /// 获取更新信息的自定义回调
  final UpdateCheckerCallback? onCheckUpdate;

  /// 更新检查URL
  final String? updateUrl;

  /// 当前应用版本
  final String currentVersion;

  /// 自定义HTTP headers
  final Map<String, String>? headers;

  /// 指定解析更新信息时的字段映射
  final String versionKey;
  final String downloadUrlKey;
  final String changelogKey;
  final String isForceUpdateKey;
  final String? publishDateKey;
  final String? fileSizeKey;
  final String? md5Key;

  UpdateChecker({
    this.onCheckUpdate,
    this.updateUrl,
    required this.currentVersion,
    this.headers,
    this.versionKey = defaultVersionKey,
    this.downloadUrlKey = defaultDownloadUrlKey,
    this.changelogKey = defaultChangelogKey,
    this.isForceUpdateKey = defaultIsForceUpdateKey,
    this.publishDateKey = defaultPublishDateKey,
    this.fileSizeKey = defaultFileSizeKey,
    this.md5Key = defaultMd5Key,
  }) : assert(updateUrl != null || onCheckUpdate != null,
  '必须提供 updateUrl 或 onCheckUpdate 其中之一');

  /// 检查更新
  ///
  /// 返回一个 [Future] 包含更新信息，如果没有可用更新则返回 null
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      Map<String, dynamic> data;

      if (onCheckUpdate != null) {
        // 使用自定义回调获取更新信息
        data = await onCheckUpdate!();
      } else {
        // 使用HTTP请求获取更新信息
        data = await _fetchUpdateInfo();
      }

      // 解析更新信息
      final updateInfo = UpdateInfo.fromMap(
        data,
        versionKey: versionKey,
        downloadUrlKey: downloadUrlKey,
        changelogKey: changelogKey,
        isForceUpdateKey: isForceUpdateKey,
        publishDateKey: publishDateKey,
        fileSizeKey: fileSizeKey,
        md5Key: md5Key,
      );

      // 打印版本信息以便调试
      debugPrint('当前应用版本: $currentVersion');
      debugPrint('服务器返回版本: ${updateInfo.newVersion}');
      
      // 比较版本判断是否需要更新
      final hasUpdate = VersionComparator.hasUpdate(currentVersion, updateInfo.newVersion);
      final compareResult = VersionComparator.compare(currentVersion, updateInfo.newVersion);
      debugPrint('版本比较结果: $compareResult (负数表示有更新，0表示相同，正数表示无需更新)');
      debugPrint('是否有可用更新: $hasUpdate');
      
      if (hasUpdate) {
        return updateInfo;
      }

      // 没有可用更新
      debugPrint('无可用更新: 当前版本($currentVersion)不低于服务器版本(${updateInfo.newVersion})');
      return null;
    } catch (e) {
      throw UpdateError.parse(e);
    }
  }

  /// 通过HTTP请求获取更新信息
  Future<Map<String, dynamic>> _fetchUpdateInfo() async {
    if (updateUrl == null) {
      throw const UpdateError(
        code: 'MISSING_URL',
        message: '没有提供更新检查URL',
      );
    }
    
    try {
      // 使用HttpClientManager执行GET请求
      return await HttpClientManager().get(
        updateUrl!,
        headers: headers,
      );
    } catch (e) {
      // HttpClientManager已经处理了异常转换，所以这里可以直接抛出
      rethrow;
    }
  }
}