import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'models/app_update_info.dart';
import 'models/app_update_status.dart';
import 'utils/app_update_checker.dart';
import 'utils/app_update_downloader.dart';
import 'utils/app_version_comparator.dart';

/// 应用更新控制器
/// 
/// 控制应用更新流程，协调检查更新、下载和安装过程
class AppUpdateController extends ChangeNotifier {
  /// 更新检查器
  final AppUpdateChecker _checker;
  
  /// 下载器
  AppUpdateDownloader? _downloader;
  
  /// 取消令牌
  CancelToken? _cancelToken;
  
  /// 当前更新状态
  AppUpdateStatus _status = AppUpdateStatus.idle;
  
  /// 当前更新信息
  AppUpdateInfo? _updateInfo;
  
  /// 下载进度
  AppUpdateProgress? _progress;
  
  /// 错误信息
  AppUpdateError? _error;
  
  /// 本地保存路径
  String? _savePath;
  
  /// 获取当前状态
  AppUpdateStatus get status => _status;
  
  /// 获取更新信息
  AppUpdateInfo? get updateInfo => _updateInfo;
  
  /// 获取下载进度
  AppUpdateProgress? get progress => _progress;
  
  /// 获取错误信息
  AppUpdateError? get error => _error;
  
  /// 是否有可用更新
  bool get hasUpdate => _updateInfo != null;
  
  /// 是否正在下载
  bool get isDownloading => _status == AppUpdateStatus.downloading;
  
  /// 是否已下载完成
  bool get isDownloaded => _status == AppUpdateStatus.downloaded;
  
  /// 是否为强制更新
  bool get isForceUpdate => _updateInfo?.isForceUpdate ?? false;
  
  /// 下载的APK文件路径
  String? get downloadedFilePath => 
      _status == AppUpdateStatus.downloaded ? _savePath : null;
  
  /// 状态改变流
  final _statusController = StreamController<AppUpdateStatus>.broadcast();
  Stream<AppUpdateStatus> get statusStream => _statusController.stream;
  
  /// 进度更新流
  final _progressController = StreamController<AppUpdateProgress>.broadcast();
  Stream<AppUpdateProgress> get progressStream => _progressController.stream;
  
  /// 错误信息流
  final _errorController = StreamController<AppUpdateError>.broadcast();
  Stream<AppUpdateError> get errorStream => _errorController.stream;

  AppUpdateController({
    AppUpdateCheckerCallback? onCheckUpdate,
    String? updateUrl,
    required String currentVersion,
    Map<String, String>? headers,
    String versionKey = 'version',
    String downloadUrlKey = 'downloadUrl',
    String descriptionKey = 'description',
    String isForceUpdateKey = 'isForceUpdate',
    String? publishDateKey = 'publishDate',
    String? fileSizeKey = 'fileSize',
    String? md5Key = 'md5',
  }) : _checker = AppUpdateChecker(
         onCheckUpdate: onCheckUpdate,
         updateUrl: updateUrl,
         currentVersion: currentVersion,
         headers: headers,
         versionKey: versionKey,
         downloadUrlKey: downloadUrlKey,
         descriptionKey: descriptionKey,
         isForceUpdateKey: isForceUpdateKey,
         publishDateKey: publishDateKey,
         fileSizeKey: fileSizeKey,
         md5Key: md5Key,
       );

  /// 检查更新
  /// 
  /// 返回更新信息，如果没有可用更新则返回null
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      _updateStatus(AppUpdateStatus.checking);
      
      final updateInfo = await _checker.checkForUpdate();
      
      if (updateInfo != null) {
        _updateInfo = updateInfo;
        _updateStatus(AppUpdateStatus.available);
      } else {
        _updateStatus(AppUpdateStatus.notAvailable);
      }
      
      return updateInfo;
    } catch (e) {
      final error = e is AppUpdateError ? e : AppUpdateError.server(e);
      _setError(error);
      _updateStatus(AppUpdateStatus.error);
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
      throw AppUpdateError(
        code: 'NO_UPDATE',
        message: '没有可用的更新',
      );
    }
    
    if (_status == AppUpdateStatus.downloading) {
      // 已经在下载中
      return null;
    }
    
    _savePath = savePath ?? _generateSavePath();
    
    try {
      _cancelToken = CancelToken();
      
      _downloader = AppUpdateDownloader(
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
        
        if (status == AppUpdateStatus.downloaded && autoInstall) {
          installUpdate();
        }
      });
      
      // 订阅错误信息
      _downloader!.errorStream.listen((error) {
        _setError(error);
      });
      
      // 开始下载
      _updateStatus(AppUpdateStatus.downloading);
      return await _downloader!.download(cancelToken: _cancelToken);
    } catch (e) {
      final error = e is AppUpdateError ? e : AppUpdateError.download(e);
      _setError(error);
      _updateStatus(AppUpdateStatus.error);
      return null;
    }
  }
  
  /// 暂停下载
  Future<void> pauseDownload() async {
    if (_downloader != null && _status == AppUpdateStatus.downloading) {
      await _downloader!.pause();
      _updateStatus(AppUpdateStatus.paused);
    }
  }
  
  /// 恢复下载
  Future<File?> resumeDownload() async {
    if (_downloader != null && _status == AppUpdateStatus.paused) {
      try {
        _updateStatus(AppUpdateStatus.downloading);
        return await _downloader!.resume();
      } catch (e) {
        final error = e is AppUpdateError ? e : AppUpdateError.download(e);
        _setError(error);
        _updateStatus(AppUpdateStatus.error);
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
      _updateStatus(AppUpdateStatus.canceled);
    }
  }
  
  /// 安装更新
  /// 
  /// 注：仅适用于Android平台，iOS需要通过App Store更新
  Future<bool> installUpdate() async {
    if (_status != AppUpdateStatus.downloaded || _savePath == null) {
      return false;
    }
    
    final file = File(_savePath!);
    if (!await file.exists()) {
      _setError(AppUpdateError.file(Exception('安装文件不存在')));
      return false;
    }
    
    try {
      if (Platform.isAndroid) {
        // 在真实应用中，这里需要调用平台特定代码来安装APK
        // 为了保持轻量级，这里只是一个占位实现
        debugPrint('安装更新：${file.path}');
        return true;
      } else {
        _setError(AppUpdateError(
          code: 'PLATFORM_NOT_SUPPORTED',
          message: '当前平台不支持应用内安装',
        ));
        return false;
      }
    } catch (e) {
      _setError(AppUpdateError(
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
    _updateStatus(AppUpdateStatus.idle);
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
  void _updateStatus(AppUpdateStatus status) {
    if (_status != status) {
      _status = status;
      _statusController.add(status);
      notifyListeners();
    }
  }
  
  /// 设置错误
  void _setError(AppUpdateError error) {
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
