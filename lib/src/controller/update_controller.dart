import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_updater/src/utils/constants.dart';
import '../channel/flutter_app_updater_platform_interface.dart';

import '../models/update_error.dart';
import '../models/update_info.dart';
import '../models/update_progress.dart';
import '../models/update_status.dart';
import '../network/update_downloader.dart';
import '../utils/update_checker.dart';

/// 应用更新控制器
///
/// 控制应用更新流程，协调检查更新、下载和安装过程
class UpdateController extends ChangeNotifier {
  /// 更新检查器
  UpdateChecker _checker;

  /// 下载器
  UpdateDownloader? _downloader;

  /// 取消令牌
  CancelToken? _cancelToken;

  /// 当前更新状态
  UpdateStatus _status = UpdateStatus.idle;

  /// 当前更新信息
  UpdateInfo? _updateInfo;

  /// 下载进度
  UpdateProgress? _progress;

  /// 错误信息
  UpdateError? _error;

  /// 本地保存路径
  String? _savePath;

  /// 获取当前状态
  UpdateStatus get status => _status;

  /// 获取更新信息
  UpdateInfo? get updateInfo => _updateInfo;

  /// 获取下载进度
  UpdateProgress? get progress => _progress;

  /// 获取错误信息
  UpdateError? get error => _error;

  /// 是否有可用更新
  bool get hasUpdate => _updateInfo != null;

  /// 是否正在下载
  bool get isDownloading => _status == UpdateStatus.downloading;

  /// 是否已下载完成
  bool get isDownloaded => _status == UpdateStatus.downloaded;

  /// 是否为强制更新
  bool get isForceUpdate => _updateInfo?.isForceUpdate ?? false;

  /// 下载的APK文件路径
  String? get downloadedFilePath =>
      _status == UpdateStatus.downloaded ? _savePath : null;

  /// 状态改变流
  final _statusController = StreamController<UpdateStatus>.broadcast();
  Stream<UpdateStatus> get statusStream => _statusController.stream;

  /// 进度更新流
  final _progressController = StreamController<UpdateProgress>.broadcast();
  Stream<UpdateProgress> get progressStream => _progressController.stream;

  /// 错误信息流
  final _errorController = StreamController<UpdateError>.broadcast();
  Stream<UpdateError> get errorStream => _errorController.stream;

  /// 当前版本号
  String? _currentVersion;

  UpdateController({
    UpdateCheckerCallback? onCheckUpdate,
    String? updateUrl,
    String? currentVersion, // 改为可选参数
    Map<String, String>? headers,
    String versionKey = defaultVersionKey,
    String downloadUrlKey = defaultDownloadUrlKey,
    String changeLogKey = defaultChangelogKey,
    String isForceUpdateKey = defaultIsForceUpdateKey,
    String? publishDateKey = defaultPublishDateKey,
    String? fileSizeKey = defaultFileSizeKey,
    String? md5Key = defaultMd5Key,
  }) : _currentVersion = currentVersion,
      _checker = UpdateChecker(
    onCheckUpdate: onCheckUpdate,
    updateUrl: updateUrl,
    currentVersion: currentVersion ?? '',  // 临时传空字符串，后续会更新
    headers: headers,
    versionKey: versionKey,
    downloadUrlKey: downloadUrlKey,
    changelogKey: changeLogKey,
    isForceUpdateKey: isForceUpdateKey,
    publishDateKey: publishDateKey,
    fileSizeKey: fileSizeKey,
    md5Key: md5Key,
  );

  /// 获取当前版本号
  String? get currentVersion => _currentVersion;

  /// 设置当前版本号
  set currentVersion(String? version) {
    if (version != null && version.isNotEmpty) {
      _currentVersion = version;
      // 更新checker中的版本号
      _updateCheckerVersion(version);
    }
  }

  /// 更新checker中的版本号
  void _updateCheckerVersion(String version) {
    // 由于UpdateChecker没有setter，需要重新创建实例
    final newChecker = UpdateChecker(
      onCheckUpdate: _checker.onCheckUpdate,
      updateUrl: _checker.updateUrl,
      currentVersion: version,
      headers: _checker.headers,
      versionKey: _checker.versionKey,
      downloadUrlKey: _checker.downloadUrlKey,
      changelogKey: _checker.changelogKey,
      isForceUpdateKey: _checker.isForceUpdateKey,
      publishDateKey: _checker.publishDateKey,
      fileSizeKey: _checker.fileSizeKey,
      md5Key: _checker.md5Key,
    );

    // 替换旧实例
    _checker = newChecker;
  }

  /// 检查更新
  ///
  /// 返回更新信息，如果没有可用更新则返回null
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      // 检查是否设置了版本号
      if (_currentVersion == null || _currentVersion!.isEmpty) {
        throw const UpdateError(
          code: 'MISSING_VERSION',
          message: '未设置当前应用版本号',
        );
      }
      
      _updateStatus(UpdateStatus.checking);

      final updateInfo = await _checker.checkForUpdate();

      if (updateInfo != null) {
        _updateInfo = updateInfo;
        _updateStatus(UpdateStatus.available);
      } else {
        _updateStatus(UpdateStatus.notAvailable);
      }

      return updateInfo;
    } catch (e) {
      final error = e is UpdateError ? e : UpdateError.server(e);
      _setError(error);
      _updateStatus(UpdateStatus.error);
      return null;
    }
  }

  /// 开始下载更新
  ///
  /// [savePath] 文件保存路径
  /// [autoInstall] 下载完成后是否自动安装
  Future<File?> downloadUpdate({
    String? savePath,
    bool autoInstall = false,
  }) async {
    if (_updateInfo == null) {
      throw const UpdateError(
        code: 'NO_UPDATE',
        message: '没有可用的更新',
      );
    }

    if (_status == UpdateStatus.downloading) {
      // 已经在下载中
      return null;
    }

    _savePath = savePath ?? _generateSavePath();

    try {
      _cancelToken = CancelToken();

      _downloader = UpdateDownloader(
        url: _updateInfo!.downloadUrl,
        savePath: _savePath!,
        supportRangeDownload: true,
        expectedFileSize: _updateInfo!.fileSize,
        md5: _updateInfo!.md5,
      );

      // 订阅下载进度
      _downloader!.progressStream.listen((progress) {
        _progress = progress;
        _progressController.add(progress);
        notifyListeners();
      });

      // 订阅下载状态
      _downloader!.statusStream.listen((status) {
        _updateStatus(status);

        if (status == UpdateStatus.downloaded && autoInstall) {
          installUpdate();
        }
      });

      // 订阅错误信息
      _downloader!.errorStream.listen((error) {
        _setError(error);
      });

      // 开始下载
      _updateStatus(UpdateStatus.downloading);
      return await _downloader!.download(cancelToken: _cancelToken);
    } catch (e) {
      final error = e is UpdateError ? e : UpdateError.download(e);
      _setError(error);
      _updateStatus(UpdateStatus.error);
      return null;
    }
  }

  /// 暂停下载
  Future<void> pauseDownload() async {
    if (_downloader != null && _status == UpdateStatus.downloading) {
      await _downloader!.pause();
      _updateStatus(UpdateStatus.paused);
    }
  }

  /// 恢复下载
  Future<File?> resumeDownload() async {
    if (_downloader != null && _status == UpdateStatus.paused) {
      try {
        _updateStatus(UpdateStatus.downloading);
        return await _downloader!.resume();
      } catch (e) {
        final error = e is UpdateError ? e : UpdateError.download(e);
        _setError(error);
        _updateStatus(UpdateStatus.error);
        return null;
      }
    }
    return null;
  }

  /// 取消下载
  Future<void> cancelDownload() async {
    _cancelToken?.cancel();

    if (_downloader != null) {
      await _downloader!.cancel();
      _updateStatus(UpdateStatus.canceled);
    }
  }

  /// 安装更新
  ///
  /// 注：仅适用于Android平台，iOS需要通过App Store更新
  Future<bool> installUpdate() async {
    if (_status != UpdateStatus.downloaded || _savePath == null) {
      return false;
    }

    final file = File(_savePath!);
    if (!await file.exists()) {
      _setError(UpdateError.file(Exception('安装文件不存在')));
      return false;
    }

    try {
      if (Platform.isAndroid) {
        // 调用平台通道安装APK
        await FlutterAppUpdaterPlatform.instance.installApp(path: file.path);
        debugPrint('开始安装更新：${file.path}');
        return true;
      } else {
        _setError(const UpdateError(
          code: 'PLATFORM_NOT_SUPPORTED',
          message: '当前平台不支持应用内安装',
        ));
        return false;
      }
    } catch (e) {
      _setError(UpdateError(
        code: 'INSTALL_FAILED',
        message: '安装失败',
        exception: e,
      ));
      return false;
    }
  }

  /// 重置状态
  void reset() {
    _cancelToken?.cancel();
    _downloader?.dispose();
    _downloader = null;
    _updateInfo = null;
    _progress = null;
    _error = null;
    _savePath = null;
    _updateStatus(UpdateStatus.idle);
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _downloader?.dispose();

    _statusController.close();
    _progressController.close();
    _errorController.close();

    super.dispose();
  }

  /// 更新状态
  void _updateStatus(UpdateStatus status) {
    if (_status != status) {
      _status = status;
      _statusController.add(status);
      notifyListeners();
    }
  }

  /// 设置错误
  void _setError(UpdateError error) {
    _error = error;
    _errorController.add(error);
    notifyListeners();
  }

  /// 生成文件保存路径
  String _generateSavePath() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    if (Platform.isAndroid) {
      // 在Android上，通常保存到外部存储的Download目录
      return '/storage/emulated/0/Download/app_update_$timestamp.apk';
    } else if (Platform.isIOS) {
      // 在iOS上，保存到应用的临时目录
      return '${Directory.systemTemp.path}/app_update_$timestamp.ipa';
    } else {
      // 其他平台
      return '${Directory.systemTemp.path}/app_update_$timestamp.bin';
    }
  }
}