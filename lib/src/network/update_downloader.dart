import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../models/update_error.dart';
import '../models/update_progress.dart';
import '../models/update_status.dart';
import '../utils/retry_strategy.dart';
import '../utils/update_logger.dart';

/// 应用更新下载器
///
/// 负责下载更新包并提供下载进度信息
/// 支持断点续传、后台下载和下载暂停/恢复
class UpdateDownloader {
  /// 下载URL
  final String url;

  /// 保存路径
  final String savePath;

  /// 是否支持断点续传
  final bool supportRangeDownload;

  /// 预期文件大小（字节）
  final int? expectedFileSize;

  /// 文件MD5校验值
  final String? md5;

  /// 下载总超时时间
  final Duration downloadTimeout;

  /// 重试策略
  final RetryStrategy retryStrategy;

  /// 下载进度流控制器
  final _progressController = StreamController<UpdateProgress>.broadcast();

  /// 下载状态流控制器
  final _statusController = StreamController<UpdateStatus>.broadcast();

  /// 下载错误流控制器
  final _errorController = StreamController<UpdateError>.broadcast();

  /// 下载进度流
  Stream<UpdateProgress> get progressStream => _progressController.stream;

  /// 下载状态流
  Stream<UpdateStatus> get statusStream => _statusController.stream;

  /// 下载错误流
  Stream<UpdateError> get errorStream => _errorController.stream;

  /// 当前下载状态
  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  /// 当前下载进度
  UpdateProgress _progress = UpdateProgress.unknown();
  UpdateProgress get progress => _progress;



  /// 计算下载速度的时间窗口（毫秒）
  static const _speedCalculationWindow = 3000;

  /// 最近的下载字节计数，用于计算速度
  final _recentDownloadedBytes = <int>[];
  final _recentTimestamps = <int>[];

  /// 下载客户端
  HttpClient? _httpClient;

  /// 下载请求
  HttpClientRequest? _request;


  /// 输出文件流
  IOSink? _fileSink;

  /// 下载是否已完成
  bool _isCompleted = false;

  /// 下载任务完成器
  Completer<File>? _downloadCompleter;

  /// 取消令牌
  CancelToken? _cancelToken;

  /// 已下载文件的临时路径
  String get _tempFilePath => '$savePath.download';

  /// 暂停标记
  bool _isPaused = false;

  UpdateDownloader({
    required this.url,
    required this.savePath,
    this.supportRangeDownload = true,
    this.expectedFileSize,
    this.md5,
    this.downloadTimeout = const Duration(minutes: 30),
    this.retryStrategy = RetryStrategy.standard,
  });

  /// 开始下载任务
  ///
  /// 返回一个 [Future] 完成时表示下载已完成，并返回下载的文件
  ///
  /// 设置了总超时时间[downloadTimeout]，超时后会抛出错误
  Future<File> download({
    CancelToken? cancelToken,
  }) async {
    if (_isCompleted) {
      // 已经下载完成，直接返回文件
      return File(savePath);
    }

    if (_status == UpdateStatus.downloading) {
      // 已经在下载中，返回当前下载任务
      return _downloadCompleter!.future;
    }

    // 创建一个新的下载任务
    _cancelToken = cancelToken;
    _downloadCompleter = Completer<File>();
    _isPaused = false;
    _updateStatus(UpdateStatus.downloading);

    try {
      // 检查是否可以恢复下载
      final downloadedFile = File(_tempFilePath);
      int downloadedBytes = 0;

      if (await downloadedFile.exists()) {
        downloadedBytes = await downloadedFile.length();

        // 如果已下载的文件大小等于预期大小，认为下载已完成
        if (expectedFileSize != null && downloadedBytes >= expectedFileSize!) {
          await _finalizeDownload();
          return File(savePath);
        }
      }

      // 使用重试机制开始或恢复下载
      await _downloadWithRetry(downloadedBytes);

      return _downloadCompleter!.future.timeout(
        downloadTimeout,
        onTimeout: () {
          _updateStatus(UpdateStatus.error);
          const error = UpdateError(
            code: 'DOWNLOAD_TIMEOUT',
            message: '下载超时',
          );
          _errorController.add(error);
          throw error;
        },
      );
    } catch (e) {
      final error = e is UpdateError
          ? e
          : UpdateError.download(e);

      _updateStatus(UpdateStatus.error);
      _errorController.add(error);

      if (!_downloadCompleter!.isCompleted) {
        _downloadCompleter!.completeError(error);
      }

      rethrow;
    }
  }

  /// 暂停下载
  Future<void> pause() async {
    if (_status != UpdateStatus.downloading || _isPaused) {
      return;
    }

    _isPaused = true;
    await _closeConnection();
    _updateStatus(UpdateStatus.paused);
  }

  /// 恢复下载
  Future<File> resume() async {
    if (_status != UpdateStatus.paused) {
      if (_status == UpdateStatus.downloading) {
        return _downloadCompleter!.future;
      }
      return download();
    }

    // 恢复下载
    final downloadedFile = File(_tempFilePath);
    int downloadedBytes = 0;

    if (await downloadedFile.exists()) {
      downloadedBytes = await downloadedFile.length();
    }

    _isPaused = false;
    _updateStatus(UpdateStatus.downloading);

    try {
      await _startDownload(downloadedBytes);
      return _downloadCompleter!.future;
    } catch (e) {
      final error = e is UpdateError
          ? e
          : UpdateError.download(e);

      _updateStatus(UpdateStatus.error);
      _errorController.add(error);
      _downloadCompleter!.completeError(error);

      rethrow;
    }
  }

  /// 取消下载
  Future<void> cancel() async {
    if (_status == UpdateStatus.canceled ||
        _status == UpdateStatus.downloaded) {
      return;
    }

    await _closeConnection();
    _cancelToken?.cancel();
    _updateStatus(UpdateStatus.canceled);

    if (!_downloadCompleter!.isCompleted) {
      _downloadCompleter!.completeError(
        const UpdateError(
          code: 'DOWNLOAD_CANCELED',
          message: '下载已取消',
        ),
      );
    }

    // 删除临时文件
    try {
      final tempFile = File(_tempFilePath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      // 忽略文件删除错误
      UpdateLogger.warning('删除临时文件失败: $e', tag: 'UpdateDownloader');
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await _closeConnection();

    await _progressController.close();
    await _statusController.close();
    await _errorController.close();
  }

  /// 使用重试机制下载
  ///
  /// [resumeFrom] 从指定字节位置恢复下载
  ///
  /// 根据配置的重试策略自动重试失败的下载
  Future<void> _downloadWithRetry(int resumeFrom) async {
    int attemptNumber = 0;

    while (true) {
      try {
        // 记录重试信息
        if (attemptNumber > 0) {
          UpdateLogger.info(
            '第${attemptNumber + 1}次尝试下载（重试$attemptNumber次）',
            tag: 'UpdateDownloader',
          );
        } else {
          UpdateLogger.info('开始下载', tag: 'UpdateDownloader');
        }

        // 尝试下载
        await _startDownload(resumeFrom);

        // 下载成功，退出重试循环
        if (attemptNumber > 0) {
          UpdateLogger.info(
            '下载成功（经过$attemptNumber次重试）',
            tag: 'UpdateDownloader',
          );
        }
        return;

      } catch (e) {

        // 检查是否被取消或暂停
        if (_cancelToken?.isCanceled == true || _isPaused) {
          UpdateLogger.debug('下载被取消或暂停，停止重试', tag: 'UpdateDownloader');
          rethrow;
        }

        // 检查是否应该重试
        if (!retryStrategy.shouldRetry(e, attemptNumber)) {
          UpdateLogger.warning(
            '下载失败，不满足重试条件: ${e.toString()}',
            tag: 'UpdateDownloader',
          );
          rethrow;
        }

        // 检查是否还有重试次数
        if (!retryStrategy.canRetry(attemptNumber)) {
          UpdateLogger.error(
            '下载失败，已达到最大重试次数${retryStrategy.maxAttempts}',
            tag: 'UpdateDownloader',
            error: e,
          );
          rethrow;
        }

        // 计算延迟时间
        final delay = retryStrategy.getDelay(attemptNumber);
        UpdateLogger.warning(
          '下载失败: ${e.toString()}，将在${delay.inSeconds}秒后重试（剩余${retryStrategy.maxAttempts - attemptNumber}次机会）',
          tag: 'UpdateDownloader',
        );

        // 等待后重试
        await Future.delayed(delay);
        attemptNumber++;
      }
    }
  }

  /// 开始或恢复下载
  Future<void> _startDownload(int resumeFrom) async {
    _recentDownloadedBytes.clear();
    _recentTimestamps.clear();

    try {
      // 确保下载目录存在
      await _ensureDirectoryExists(_tempFilePath);

      // 打开文件
      final file = File(_tempFilePath);
      IOSink fileSink;

      if (resumeFrom > 0 && supportRangeDownload) {
        // 断点续传，追加模式打开文件
        fileSink = file.openWrite(mode: FileMode.append);
      } else {
        // 新下载，或不支持断点续传，覆盖模式
        resumeFrom = 0;
        fileSink = file.openWrite(mode: FileMode.write);
      }

      _fileSink = fileSink;

      // 创建HTTP客户端
      final client = HttpClient();
      _httpClient = client;

      // 创建请求
      final request = await client.getUrl(Uri.parse(url));
      _request = request;

      // 设置断点续传的Range头
      if (resumeFrom > 0 && supportRangeDownload) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
      }

      // 发送请求
      final response = await request.close();

      // 检查响应状态
      final isResume = resumeFrom > 0 && supportRangeDownload;
      final expectedStatus = isResume ? 206 : 200;

      if (response.statusCode != expectedStatus) {
        throw UpdateError(
          code: 'HTTP_ERROR',
          message: '服务器返回错误代码：${response.statusCode}',
        );
      }

      // 获取文件总大小
      int totalSize;

      if (response.statusCode == 206) {
        // 断点续传响应，从Content-Range中获取总大小
        final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
        if (contentRange != null && contentRange.contains('/')) {
          final totalSizeStr = contentRange.split('/').last;
          totalSize = int.tryParse(totalSizeStr) ?? expectedFileSize ?? 0;
        } else {
          totalSize = resumeFrom + response.contentLength;
        }
      } else {
        // 普通响应
        totalSize = response.contentLength;
      }

      // 更新进度初始状态
      _progress = UpdateProgress(
        downloaded: resumeFrom,
        total: totalSize,
        speed: 0,
        estimatedTimeRemaining: null,
      );
      _progressController.add(_progress);

      // 接收数据
      await _receiveData(response, resumeFrom, totalSize);

    } catch (e) {
      await _closeConnection();

      if (_cancelToken?.isCanceled == true || _isPaused) {
        // 取消或暂停导致的异常，忽略
        return;
      }

      final error = e is UpdateError
          ? e
          : UpdateError.download(e);

      _updateStatus(UpdateStatus.error);
      _errorController.add(error);

      if (!_downloadCompleter!.isCompleted) {
        _downloadCompleter!.completeError(error);
      }
    }
  }

  /// 接收并保存数据
  Future<void> _receiveData(
      HttpClientResponse response,
      int initialBytes,
      int totalSize
      ) async {
    int receivedBytes = initialBytes;

    await for (final List<int> chunk in response) {
      if (_cancelToken?.isCanceled == true) {
        await _closeConnection();
        _updateStatus(UpdateStatus.canceled);
        return;
      }

      if (_isPaused) {
        await _closeConnection();
        _updateStatus(UpdateStatus.paused);
        return;
      }

      // 写入文件
      _fileSink?.add(chunk);

      // 更新进度
      receivedBytes += chunk.length;

      // 记录最近的下载字节数，用于计算速度
      final now = DateTime.now().millisecondsSinceEpoch;
      _recentDownloadedBytes.add(chunk.length);
      _recentTimestamps.add(now);

      // 移除旧的记录点
      while (_recentTimestamps.isNotEmpty &&
          now - _recentTimestamps.first > _speedCalculationWindow) {
        _recentDownloadedBytes.removeAt(0);
        _recentTimestamps.removeAt(0);
      }

      // 计算下载速度
      int? speed;
      int? estimatedTimeRemaining;

      if (_recentTimestamps.isNotEmpty) {
        final timeWindow = now - _recentTimestamps.first;
        if (timeWindow > 0) {
          final totalBytes = _recentDownloadedBytes.fold<int>(0, (a, b) => a + b);
          speed = (totalBytes * 1000 / timeWindow).round();

          // 计算剩余时间
          if (speed > 0 && totalSize > receivedBytes) {
            estimatedTimeRemaining = ((totalSize - receivedBytes) / speed).round();
          }
        }
      }

      // 更新进度
      _progress = _progress.copyWith(
        downloaded: receivedBytes,
        total: totalSize,
        speed: speed,
        estimatedTimeRemaining: estimatedTimeRemaining,
      );

      _progressController.add(_progress);

      // 检查是否下载完成
      if (totalSize > 0 && receivedBytes >= totalSize) {
        await _finalizeDownload();
        break;
      }
    }

    // 确保文件写入完成
    await _fileSink?.flush();
    await _closeConnection();

    // 如果下载未标记为完成，但已接收所有数据，则完成下载
    if (!_isCompleted) {
      await _finalizeDownload();
    }
  }

  /// 完成下载，移动临时文件到最终位置
  Future<void> _finalizeDownload() async {
    await _fileSink?.flush();
    await _closeConnection();

    try {
      final tempFile = File(_tempFilePath);

      // 检查MD5（如果提供）
      if (md5 != null && md5!.isNotEmpty) {
        UpdateLogger.info('开始校验文件MD5...', tag: 'UpdateDownloader');
        final isValid = await _verifyFileMd5(tempFile, md5!);
        if (!isValid) {
          // MD5校验失败，删除临时文件
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          throw const UpdateError(
            code: 'MD5_MISMATCH',
            message: 'MD5校验失败，文件可能已损坏或被篡改',
          );
        }
        UpdateLogger.info('MD5校验通过', tag: 'UpdateDownloader');
      }

      // 移动文件到最终位置
      if (await tempFile.exists()) {
        // 如果目标文件已存在，先删除它
        final targetFile = File(savePath);
        if (await targetFile.exists()) {
          await targetFile.delete();
        }

        // 移动文件
        await tempFile.rename(savePath);
      }

      _isCompleted = true;
      _updateStatus(UpdateStatus.downloaded);

      if (!_downloadCompleter!.isCompleted) {
        _downloadCompleter!.complete(File(savePath));
      }
    } catch (e) {
      final error = e is UpdateError
          ? e
          : UpdateError.file(e);

      _updateStatus(UpdateStatus.error);
      _errorController.add(error);

      if (!_downloadCompleter!.isCompleted) {
        _downloadCompleter!.completeError(error);
      }
    }
  }

  /// 确保目录存在
  ///
  /// [filePath] 文件路径
  ///
  /// 从文件路径中提取目录并确保其存在
  /// 如果目录不存在则递归创建
  Future<void> _ensureDirectoryExists(String filePath) async {
    try {
      final file = File(filePath);
      final directory = file.parent;

      if (!await directory.exists()) {
        UpdateLogger.debug('创建目录: ${directory.path}', tag: 'UpdateDownloader');
        await directory.create(recursive: true);
        UpdateLogger.debug('目录创建成功: ${directory.path}', tag: 'UpdateDownloader');
      }
    } catch (e) {
      UpdateLogger.error(
        '创建目录失败',
        error: e,
        tag: 'UpdateDownloader',
      );
      rethrow;
    }
  }

  /// 验证文件MD5
  ///
  /// [file] 要验证的文件
  /// [expectedMd5] 期望的MD5值
  ///
  /// 返回true表示MD5匹配，false表示不匹配
  Future<bool> _verifyFileMd5(File file, String expectedMd5) async {
    try {
      if (!await file.exists()) {
        return false;
      }

      // 读取文件并计算MD5
      final bytes = await file.readAsBytes();
      final digest = crypto.md5.convert(bytes);
      final actualMd5 = digest.toString();

      // 比较MD5（忽略大小写）
      final expected = expectedMd5.toLowerCase().trim();
      final actual = actualMd5.toLowerCase().trim();

      UpdateLogger.debug('期望MD5: $expected', tag: 'UpdateDownloader');
      UpdateLogger.debug('实际MD5: $actual', tag: 'UpdateDownloader');

      return expected == actual;
    } catch (e) {
      UpdateLogger.error('MD5校验过程出错: $e', tag: 'UpdateDownloader', error: e);
      return false;
    }
  }

  /// 关闭连接并释放资源
  Future<void> _closeConnection() async {
    // 首先安全地释放 HTTP 资源
    try {
      // 中止请求
      _request?.abort();
      _request = null;
      
      // 关闭 HTTP 客户端
      _httpClient?.close();
      _httpClient = null;
    } catch (e) {
      UpdateLogger.warning('关闭 HTTP 连接时出错: $e', tag: 'UpdateDownloader');
      _request = null;
      _httpClient = null;
    }

    // 单独处理文件流关闭
    if (_fileSink != null) {
      try {
        // 如果流没有被关闭，尝试关闭它
        var sink = _fileSink;
        _fileSink = null; // 先设置为 null，避免循环引用
        await sink?.flush();
        await sink?.close();
      } catch (e) {
        UpdateLogger.warning('关闭文件流时出错: $e', tag: 'UpdateDownloader');
        // 仅确保引用被释放
        _fileSink = null;
      }
    }
  }

  /// 更新下载状态
  void _updateStatus(UpdateStatus status) {
    if (_status != status) {
      _status = status;
      _statusController.add(status);
    }
  }
}

/// 取消令牌类
class CancelToken {
  bool _isCanceled = false;

  /// 取消状态
  bool get isCanceled => _isCanceled;

  /// 取消当前操作
  void cancel() {
    _isCanceled = true;
  }
}