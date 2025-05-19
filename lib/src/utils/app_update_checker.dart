import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_update_info.dart';
import '../models/app_update_status.dart';
import 'app_version_comparator.dart';

/// 定义更新检查器回调函数类型
typedef AppUpdateCheckerCallback = Future<Map<String, dynamic>> Function();

/// 应用更新检查器
/// 
/// 负责检查是否有可用的应用更新
class AppUpdateChecker {
  /// 获取更新信息的自定义回调
  final AppUpdateCheckerCallback? onCheckUpdate;
  
  /// 更新检查URL
  final String? updateUrl;
  
  /// 当前应用版本
  final String currentVersion;
  
  /// 自定义HTTP headers
  final Map<String, String>? headers;
  
  /// 指定解析更新信息时的字段映射
  final String versionKey;
  final String downloadUrlKey;
  final String descriptionKey;
  final String isForceUpdateKey;
  final String? publishDateKey;
  final String? fileSizeKey;
  final String? md5Key;

  AppUpdateChecker({
    this.onCheckUpdate,
    this.updateUrl,
    required this.currentVersion,
    this.headers,
    this.versionKey = 'version',
    this.downloadUrlKey = 'downloadUrl',
    this.descriptionKey = 'description',
    this.isForceUpdateKey = 'isForceUpdate',
    this.publishDateKey = 'publishDate',
    this.fileSizeKey = 'fileSize',
    this.md5Key = 'md5',
  }) : assert(updateUrl != null || onCheckUpdate != null, 
            '必须提供 updateUrl 或 onCheckUpdate 其中之一');

  /// 检查更新
  /// 
  /// 返回一个 [Future] 包含更新信息，如果没有可用更新则返回 null
  Future<AppUpdateInfo?> checkForUpdate() async {
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
      final updateInfo = AppUpdateInfo.fromMap(
        data,
        versionKey: versionKey,
        downloadUrlKey: downloadUrlKey,
        descriptionKey: descriptionKey,
        isForceUpdateKey: isForceUpdateKey,
        publishDateKey: publishDateKey,
        fileSizeKey: fileSizeKey,
        md5Key: md5Key,
      );
      
      // 比较版本判断是否需要更新
      if (AppVersionComparator.hasUpdate(currentVersion, updateInfo.version)) {
        return updateInfo;
      }
      
      // 没有可用更新
      return null;
    } catch (e) {
      throw AppUpdateError.parse(e);
    }
  }
  
  /// 通过HTTP请求获取更新信息
  Future<Map<String, dynamic>> _fetchUpdateInfo() async {
    if (updateUrl == null) {
      throw AppUpdateError(
        code: 'MISSING_URL',
        message: '没有提供更新检查URL',
      );
    }
    
    try {
      final client = HttpClient();
      
      try {
        final request = await client.getUrl(Uri.parse(updateUrl!));
        
        // 添加请求头
        if (headers != null) {
          headers!.forEach((key, value) {
            request.headers.set(key, value);
          });
        }
        
        final response = await request.close();
        
        if (response.statusCode != 200) {
          throw AppUpdateError.server(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          );
        }
        
        // 读取响应内容
        final responseBody = await response.transform(utf8.decoder).join();
        
        // 解析JSON
        try {
          final data = json.decode(responseBody) as Map<String, dynamic>;
          return data;
        } catch (e) {
          throw AppUpdateError.parse(e);
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (e is AppUpdateError) {
        rethrow;
      }
      
      if (e is SocketException || e is TimeoutException) {
        throw AppUpdateError.network(e);
      }
      
      throw AppUpdateError.server(e);
    }
  }
}
