import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_app_updater/src/utils/constants.dart';

import 'channel/flutter_app_updater_platform_interface.dart';
import 'controller/update_controller.dart';
import 'models/update_info.dart';
import 'ui/update_dialog.dart';


/// 应用更新服务
///
/// 提供一个简单的方式来管理应用更新流程
/// 负责检查更新、显示更新对话框和处理下载
class FlutterAppUpdater {
  /// 更新控制器
  final UpdateController _controller;

  /// 初始化标志
  bool _initialized = false;

  /// 最近一次检查更新时间
  DateTime? _lastCheckTime;

  /// 定时检查任务
  Timer? _checkTimer;

  /// 获取控制器实例
  UpdateController get controller => _controller;

  /// 获取最近一次检查时间
  DateTime? get lastCheckTime => _lastCheckTime;

  FlutterAppUpdater({
    UpdateController? controller,
    String? updateUrl,
    Function? onCheckUpdate,
    String? currentVersion,
    Map<String, String>? headers,
    String versionKey = defaultVersionKey,
    String downloadUrlKey = defaultDownloadUrlKey,
    String changeLogKey = defaultChangelogKey,
    String isForceUpdateKey = defaultIsForceUpdateKey,
    String? publishDateKey = defaultPublishDateKey,
    String? fileSizeKey = defaultFileSizeKey,
    String? md5Key = defaultMd5Key,
  }) : _controller = controller ?? UpdateController(
    updateUrl: updateUrl,
    onCheckUpdate: onCheckUpdate as dynamic,
    currentVersion: currentVersion, // 可以为空，初始化时会获取
    headers: headers,
    versionKey: versionKey,
    downloadUrlKey: downloadUrlKey,
    changeLogKey: changeLogKey,
    isForceUpdateKey: isForceUpdateKey,
    publishDateKey: publishDateKey,
    fileSizeKey: fileSizeKey,
    md5Key: md5Key,
  );

  /// 初始化服务
  ///
  /// [checkOnInit] 是否在初始化时就检查更新
  /// [checkInterval] 自动检查更新的时间间隔（小时），设为null禁用自动检查
  Future<FlutterAppUpdater> init({
    bool checkOnInit = false,
    int? checkInterval,
  }) async {
    if (_initialized) return this;

    // 如果没有设置版本号，自动获取
    if (_controller.currentVersion == null || _controller.currentVersion!.isEmpty) {
      final version = await getPlatformVersion();
      if (version != null && version.isNotEmpty) {
        _controller.currentVersion = version;
      }
    }

    if (checkOnInit) {
      await checkForUpdate();
    }

    if (checkInterval != null && checkInterval > 0) {
      // 设置定时检查
      _checkTimer?.cancel();
      _checkTimer = Timer.periodic(
        Duration(hours: checkInterval),
            (_) => checkForUpdate(showDialogIfAvailable: true),
      );
    }

    _initialized = true;
    return this;
  }

  /// 检查更新
  ///
  /// [showDialogIfAvailable] 如果有可用更新，是否自动显示更新对话框
  /// [forceCheck] 是否强制检查，忽略冷却时间
  /// [context] 显示对话框所需的BuildContext
  /// [dialogBuilder] 自定义对话框构建器
  Future<UpdateInfo?> checkForUpdate({
    bool showDialogIfAvailable = false,
    bool forceCheck = false,
    BuildContext? context,
    Widget Function(BuildContext, UpdateInfo)? dialogBuilder,
  }) async {
    // 检查是否在冷却期内
    if (!forceCheck && _lastCheckTime != null) {
      final now = DateTime.now();
      final diff = now.difference(_lastCheckTime!);

      // 默认冷却时间为1小时
      if (diff.inHours < 1) {
        return _controller.updateInfo;
      }
    }

    final updateInfo = await _controller.checkForUpdate();
    _lastCheckTime = DateTime.now();

    if (updateInfo != null && showDialogIfAvailable && context != null) {
      // 显示更新对话框
      if (context.mounted) {
        showUpdateDialog(
          context: context,
          updateInfo: updateInfo,
          dialogBuilder: dialogBuilder,
        );
      }
    }

    return updateInfo;
  }

  /// 显示更新对话框
  ///
  /// [context] 显示对话框所需的BuildContext
  /// [updateInfo] 更新信息
  /// [dialogBuilder] 自定义对话框构建器
  Future<bool?> showUpdateDialog({
    required BuildContext context,
    required UpdateInfo updateInfo,
    Widget Function(BuildContext, UpdateInfo)? dialogBuilder,
  }) async {
    // 使用自定义对话框构建器或默认对话框
    final dialog = dialogBuilder != null
        ? dialogBuilder(context, updateInfo)
        : UpdateDialog(
      updateInfo: updateInfo,
      controller: _controller,
    );

    // 强制更新时使用不可取消的对话框
    if (updateInfo.isForceUpdate) {
      return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: dialog,
        ),
      );
    } else {
      // 普通对话框
      return await showDialog<bool>(
        context: context,
        builder: (context) => dialog,
      );
    }
  }

  /// 下载更新
  ///
  /// [savePath] 保存路径
  /// [autoInstall] 下载完成后是否自动安装
  /// [showNotification] 是否显示下载通知
  Future<File?> downloadUpdate({
    String? savePath,
    bool autoInstall = false,
    bool showNotification = true,
  }) async {
    try {
      // 开始下载
      final file = await _controller.downloadUpdate(
        savePath: savePath,
        autoInstall: autoInstall,
      );

      // 如果需要显示通知，在真实应用中这里可以集成通知功能
      if (showNotification && file != null) {
        // 此处为通知集成预留位置
      }

      return file;
    } catch (e) {
      // 下载失败处理
      return null;
    }
  }

  /// 安装更新
  Future<bool> installUpdate() {
    return _controller.installUpdate();
  }

  /// 释放资源
  void dispose() {
    _checkTimer?.cancel();
    _controller.dispose();
  }

  /// 其他辅助方法
  Future<String?> getPlatformVersion() {
    return FlutterAppUpdaterPlatform.instance.getPlatformVersion();
  }

  Future<String?> getAppVersionCode() {
    return FlutterAppUpdaterPlatform.instance.getAppVersionCode();
  }

  Future<String?> getAppVersionName() {
    return FlutterAppUpdaterPlatform.instance.getAppVersionName();
  }
}