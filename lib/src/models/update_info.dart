import 'dart:convert';

import '../utils/constants.dart';

/// 应用更新信息模型
///
/// 这个模型设计为足够灵活，可以适应不同项目的接口返回格式
/// 实现了 [fromJson] 和 [fromMap] 构造函数以支持不同的数据源
class UpdateInfo{
  /// 新版本号
  final String newVersion;
  /// 新版本下载地址
  final String downloadUrl;
  /// 新版本说明
  final String changelog;
  /// 是否强制更新
  final bool isForceUpdate;
  /// 版本发布时间
  final DateTime? publishDate;
  /// 文件大小(字节)
  final int? fileSize;
  /// 文件MD5校验值
  final String? md5;
  /// 额外信息，用于存储不同项目特有的字段
  final Map<String, dynamic>? extraInfo;

  UpdateInfo({
    required this.newVersion,
    required this.downloadUrl,
    required this.changelog,
    this.isForceUpdate = false,
    this.publishDate,
    this.fileSize,
    this.md5,
    this.extraInfo,
  });


  factory UpdateInfo.fromMap(Map<String, dynamic> data,{
    String versionKey = defaultVersionKey,
    String downloadUrlKey = defaultDownloadUrlKey,
    String? changelogKey = defaultChangelogKey,
    String? isForceUpdateKey = defaultIsForceUpdateKey,
    String? publishDateKey = defaultPublishDateKey,
    String? fileSizeKey = defaultFileSizeKey,
    String? md5Key = defaultMd5Key,
  }) {

    // 尝试解析日期，支持多种格式
    DateTime? publishDate;
    if (publishDateKey != null && data.containsKey(publishDateKey)) {
      final dateValue = data[publishDateKey];
      if (dateValue is String) {
        try {
          publishDate = DateTime.parse(dateValue);
        } catch (_) {
          // 日期解析失败，忽略错误
        }
      } else if (dateValue is int) {
        // 假设是毫秒时间戳
        publishDate = DateTime.fromMillisecondsSinceEpoch(dateValue);
      }
    }

    // 提取主要字段
    // 版本号处理 - 支持字符串或数字类型
    final versionValue = data[versionKey];
    final String newVersion = versionValue is int || versionValue is double 
        ? versionValue.toString() 
        : (versionValue as String? ?? '');
        
    final downloadUrl = data[downloadUrlKey] as String? ?? '';
    final changelog = data[changelogKey] as String? ?? '';
    
    // 强制更新处理 - 支持布尔值或字符串类型(“true”/“false”)
    final forceUpdateValue = data[isForceUpdateKey];
    final bool isForceUpdate = forceUpdateValue is bool 
        ? forceUpdateValue 
        : (forceUpdateValue?.toString().toLowerCase() == 'true') || false;

    // 文件大小处理
    int? fileSize;
    if (fileSizeKey != null && data.containsKey(fileSizeKey)) {
      final sizeValue = data[fileSizeKey];
      if (sizeValue is int) {
        fileSize = sizeValue;
      } else if (sizeValue is String) {
        fileSize = int.tryParse(sizeValue);
      }
    }

    // MD5处理
    String? md5;
    if (md5Key != null && data.containsKey(md5Key)) {
      md5 = data[md5Key]?.toString();
    }

    // 创建额外信息Map，移除已使用的字段
    final usedKeys = [
      versionKey,
      downloadUrlKey,
      changelogKey,
      if(isForceUpdateKey != null) isForceUpdateKey,
      if (publishDateKey != null) publishDateKey,
      if (fileSizeKey != null) fileSizeKey,
      if (md5Key != null) md5Key,
    ];

    final extraInfo = Map<String, dynamic>.from(data)
      ..removeWhere((key, _) => usedKeys.contains(key));

    return UpdateInfo(
        newVersion: newVersion,
        downloadUrl: downloadUrl,
        changelog: changelog,
      isForceUpdate: isForceUpdate,
        publishDate: publishDate,
        fileSize: fileSize,
        md5: md5,
        extraInfo: extraInfo.isNotEmpty ? extraInfo : null,
    );
  }

    /// 从JSON字符串创建 [UpdateInfo] 对象
    factory UpdateInfo.fromJson(String jsonString, {
      String versionKey = defaultVersionKey,
      String downloadUrlKey = defaultDownloadUrlKey,
      String? changelogKey = defaultChangelogKey,
      String? isForceUpdateKey = defaultIsForceUpdateKey,
      String? publishDateKey = defaultPublishDateKey,
      String? fileSizeKey = defaultFileSizeKey,
      String? md5Key = defaultMd5Key,
    }) {
      final Map<String, dynamic> data = jsonDecode(jsonString);
      return UpdateInfo.fromMap(data,
          versionKey: versionKey,
          downloadUrlKey: downloadUrlKey,
          changelogKey: changelogKey,
          isForceUpdateKey: isForceUpdateKey,
          publishDateKey: publishDateKey,
          fileSizeKey: fileSizeKey,
          md5Key: md5Key);
    }

/// 转换为 [Map]
  Map<String, dynamic> toMap({
    String versionKey = defaultVersionKey,
    String downloadUrlKey = defaultDownloadUrlKey,
    String? changelogKey = defaultChangelogKey,
    String? isForceUpdateKey = defaultIsForceUpdateKey,
    String? publishDateKey = defaultPublishDateKey,
    String? fileSizeKey = defaultFileSizeKey,
    String? md5Key = defaultMd5Key,
  }) {
    final map = <String, dynamic>{
      versionKey: newVersion,
      downloadUrlKey: downloadUrl,
      if (changelogKey != null) changelogKey: changelog,
      if (isForceUpdateKey != null) isForceUpdateKey: isForceUpdate,
      if (publishDateKey != null) publishDateKey: publishDate?.toIso8601String(),
      if (fileSizeKey != null) fileSizeKey: fileSize,
      if (md5Key != null) md5Key: md5,
      if (extraInfo != null) ...extraInfo!,
    };
    return map;
  }

  /// 转换为JSON字符串
  String toJson({
    String versionKey = defaultVersionKey,
    String downloadUrlKey = defaultDownloadUrlKey,
    String? changelogKey = defaultChangelogKey,
    String? isForceUpdateKey = defaultIsForceUpdateKey,
    String? publishDateKey = defaultPublishDateKey,
    String? fileSizeKey = defaultFileSizeKey,
    String? md5Key = defaultMd5Key,
  }) {
    return jsonEncode(toMap(
        versionKey: versionKey,
        downloadUrlKey: downloadUrlKey,
        changelogKey: changelogKey,
        isForceUpdateKey: isForceUpdateKey,
        publishDateKey: publishDateKey,
        fileSizeKey: fileSizeKey,
        md5Key: md5Key));
  }
}