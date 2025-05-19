import 'dart:convert';

/// 应用更新信息模型
/// 
/// 这个模型设计为足够灵活，可以适应不同项目的接口返回格式
/// 实现了 [fromJson] 和 [fromMap] 构造函数以支持不同的数据源
class AppUpdateInfo {
  /// 新版本号
  final String version;
  
  /// 新版本下载地址
  final String downloadUrl;
  
  /// 新版本说明
  final String description;
  
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

  AppUpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.description,
    required this.isForceUpdate,
    this.publishDate,
    this.fileSize,
    this.md5,
    this.extraInfo,
  });

  /// 从 [Map] 创建 [AppUpdateInfo] 对象
  /// 
  /// [data] 更新信息数据
  /// [versionKey] 版本号字段名，默认 'version'
  /// [downloadUrlKey] 下载地址字段名，默认 'downloadUrl'
  /// [descriptionKey] 描述字段名，默认 'description'
  /// [isForceUpdateKey] 强制更新字段名，默认 'isForceUpdate'
  /// [publishDateKey] 发布日期字段名，默认 'publishDate'
  /// [fileSizeKey] 文件大小字段名，默认 'fileSize'
  /// [md5Key] MD5字段名，默认 'md5'
  factory AppUpdateInfo.fromMap(
    Map<String, dynamic> data, {
    String versionKey = 'version',
    String downloadUrlKey = 'downloadUrl',
    String descriptionKey = 'description',
    String isForceUpdateKey = 'isForceUpdate',
    String? publishDateKey = 'publishDate',
    String? fileSizeKey = 'fileSize',
    String? md5Key = 'md5',
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
    final version = data[versionKey]?.toString() ?? '';
    final downloadUrl = data[downloadUrlKey]?.toString() ?? '';
    final description = data[descriptionKey]?.toString() ?? '';
    
    // 处理强制更新字段，支持布尔值或字符串格式
    bool isForceUpdate = false;
    final forceUpdateValue = data[isForceUpdateKey];
    if (forceUpdateValue is bool) {
      isForceUpdate = forceUpdateValue;
    } else if (forceUpdateValue is String) {
      isForceUpdate = forceUpdateValue.toLowerCase() == 'true' || 
                     forceUpdateValue == '1';
    } else if (forceUpdateValue is num) {
      isForceUpdate = forceUpdateValue != 0;
    }

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
      descriptionKey, 
      isForceUpdateKey,
      if (publishDateKey != null) publishDateKey,
      if (fileSizeKey != null) fileSizeKey,
      if (md5Key != null) md5Key,
    ];
    
    final extraInfo = Map<String, dynamic>.from(data)
      ..removeWhere((key, _) => usedKeys.contains(key));

    return AppUpdateInfo(
      version: version,
      downloadUrl: downloadUrl,
      description: description,
      isForceUpdate: isForceUpdate,
      publishDate: publishDate,
      fileSize: fileSize,
      md5: md5,
      extraInfo: extraInfo.isNotEmpty ? extraInfo : null,
    );
  }

  /// 从JSON字符串创建 [AppUpdateInfo] 对象
  factory AppUpdateInfo.fromJson(
    String source, {
    String versionKey = 'version',
    String downloadUrlKey = 'downloadUrl',
    String descriptionKey = 'description',
    String isForceUpdateKey = 'isForceUpdate',
    String? publishDateKey = 'publishDate',
    String? fileSizeKey = 'fileSize',
    String? md5Key = 'md5',
  }) {
    final data = json.decode(source) as Map<String, dynamic>;
    return AppUpdateInfo.fromMap(
      data,
      versionKey: versionKey,
      downloadUrlKey: downloadUrlKey,
      descriptionKey: descriptionKey,
      isForceUpdateKey: isForceUpdateKey,
      publishDateKey: publishDateKey,
      fileSizeKey: fileSizeKey,
      md5Key: md5Key,
    );
  }

  /// 转换为 [Map]
  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'downloadUrl': downloadUrl,
      'description': description,
      'isForceUpdate': isForceUpdate,
      if (publishDate != null) 'publishDate': publishDate!.toIso8601String(),
      if (fileSize != null) 'fileSize': fileSize,
      if (md5 != null) 'md5': md5,
      if (extraInfo != null) ...extraInfo!,
    };
  }

  /// 转换为JSON字符串
  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'AppUpdateInfo(version: $version, downloadUrl: $downloadUrl, '
           'description: $description, isForceUpdate: $isForceUpdate, '
           'publishDate: $publishDate, fileSize: $fileSize, md5: $md5, '
           'extraInfo: $extraInfo)';
  }
}
