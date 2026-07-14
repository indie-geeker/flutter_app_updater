import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../actions/update_action.dart';
import '../background/background_download_task.dart';
import '../models/update_error_code.dart';
import 'flutter_app_updater_platform_interface.dart';

const _backgroundDownloadEventChannelName =
    'flutter_app_updater/background_downloads';
const _startBackgroundDownloadMethod = 'startBackgroundDownload';
const _getBackgroundDownloadMethod = 'getBackgroundDownload';
const _listBackgroundDownloadsMethod = 'listBackgroundDownloads';
const _resumeBackgroundDownloadMethod = 'resumeBackgroundDownload';
const _cancelBackgroundDownloadMethod = 'cancelBackgroundDownload';
const _removeBackgroundDownloadMethod = 'removeBackgroundDownload';
const _prepareBackgroundDownloadInstallMethod =
    'prepareBackgroundDownloadInstall';

/// An implementation of [FlutterAppUpdaterPlatform] that uses method channels.
class MethodChannelFlutterAppUpdater extends FlutterAppUpdaterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final MethodChannel methodChannel;

  @visibleForTesting
  final EventChannel backgroundDownloadEventChannel;

  late final Stream<BackgroundDownloadTask> _backgroundDownloads =
      backgroundDownloadEventChannel
          .receiveBroadcastStream()
          .map(_decodeBackgroundDownloadTask);

  MethodChannelFlutterAppUpdater({
    MethodChannel? methodChannel,
    EventChannel? backgroundDownloadEventChannel,
  })  : methodChannel =
            methodChannel ?? const MethodChannel('flutter_app_updater'),
        backgroundDownloadEventChannel = backgroundDownloadEventChannel ??
            const EventChannel(_backgroundDownloadEventChannelName);

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<void> installApp({required String path}) async {
    return await methodChannel.invokeMethod('installApp', path);
  }

  @override
  Future<String?> getAppVersionCode() async {
    return await methodChannel.invokeMethod("getAppVersionCode");
  }

  @override
  Future<String?> getAppVersionName() async {
    return await methodChannel.invokeMethod<String>("getAppVersionName");
  }

  @override
  Future<String?> getDownloadPath() async {
    return await methodChannel.invokeMethod<String>("getDownloadPath");
  }

  @override
  Future<void> openStore({
    required String store,
    required String storeUrl,
  }) async {
    await methodChannel.invokeMethod<void>('openStore', {
      'store': store,
      'storeUrl': storeUrl,
    });
  }

  @override
  Future<void> openAndroidMarket({
    required String marketPackageName,
    required String marketUri,
    required String targetPackageName,
    String? fallbackUrl,
  }) async {
    await methodChannel.invokeMethod<void>('openAndroidMarket', {
      'marketPackageName': marketPackageName,
      'marketUri': marketUri,
      'targetPackageName': targetPackageName,
      if (fallbackUrl != null) 'fallbackUrl': fallbackUrl,
    });
  }

  @override
  Future<void> openInstaller({
    required String installerPath,
  }) async {
    await methodChannel.invokeMethod<void>('openInstaller', {
      'installerPath': installerPath,
    });
  }

  @override
  Future<BackgroundDownloadTask> startBackgroundDownload({
    required Uri packageUrl,
    required PackageType packageType,
    required int packageSizeBytes,
    required String sha256,
  }) async {
    final result = await methodChannel.invokeMethod<Object?>(
      _startBackgroundDownloadMethod,
      {
        'packageUrl': packageUrl.toString(),
        'packageType': packageType.name,
        'packageSizeBytes': packageSizeBytes,
        'sha256': sha256,
      },
    );
    return _decodeBackgroundDownloadTask(result);
  }

  @override
  Future<BackgroundDownloadTask> getBackgroundDownload(String taskId) async {
    final result = await methodChannel.invokeMethod<Object?>(
      _getBackgroundDownloadMethod,
      {'taskId': taskId},
    );
    return _decodeBackgroundDownloadTask(result);
  }

  @override
  Future<List<BackgroundDownloadTask>> listBackgroundDownloads() async {
    final result = await methodChannel.invokeMethod<Object?>(
      _listBackgroundDownloadsMethod,
    );
    if (result is! List) {
      return [_decodeBackgroundDownloadTask(result)];
    }
    return result
        .map<BackgroundDownloadTask>(_decodeBackgroundDownloadTask)
        .toList(growable: false);
  }

  @override
  Future<BackgroundDownloadTask> resumeBackgroundDownload(String taskId) async {
    final result = await methodChannel.invokeMethod<Object?>(
      _resumeBackgroundDownloadMethod,
      {'taskId': taskId},
    );
    return _decodeBackgroundDownloadTask(result);
  }

  @override
  Future<BackgroundDownloadTask> cancelBackgroundDownload(String taskId) async {
    final result = await methodChannel.invokeMethod<Object?>(
      _cancelBackgroundDownloadMethod,
      {'taskId': taskId},
    );
    return _decodeBackgroundDownloadTask(result);
  }

  @override
  Future<void> removeBackgroundDownload(String taskId) async {
    await methodChannel.invokeMethod<void>(
      _removeBackgroundDownloadMethod,
      {'taskId': taskId},
    );
  }

  @override
  Future<String> prepareBackgroundDownloadInstall(String taskId) async {
    final result = await methodChannel.invokeMethod<String>(
      _prepareBackgroundDownloadInstallMethod,
      {'taskId': taskId},
    );
    if (result == null) {
      throw PlatformException(
        code: 'BACKGROUND_DOWNLOAD_INVALID_STATE',
        message: 'Native install preparation returned no package path.',
      );
    }
    return result;
  }

  @override
  Stream<BackgroundDownloadTask> watchBackgroundDownloads() =>
      _backgroundDownloads;
}

BackgroundDownloadTask _decodeBackgroundDownloadTask(Object? value) {
  final map = value is Map ? value : const <Object?, Object?>{};
  final id = _string(map['id'])?.trim();
  final revision = _safeInt(map['revision']);
  final downloadedBytes = _safeInt(map['downloadedBytes']);
  final totalBytes =
      map['totalBytes'] == null ? null : _safeInt(map['totalBytes']);
  final createdAtEpochMs = _safeInt(map['createdAtEpochMs']);
  final updatedAtEpochMs = _safeInt(map['updatedAtEpochMs']);
  final createdAt = _tryDateTime(createdAtEpochMs);
  final updatedAt = _tryDateTime(updatedAtEpochMs);
  final rawStatus = _string(map['status']);
  final status = _status(rawStatus);
  final filePath = _nonBlankString(map['filePath']);
  final errorCode = _string(map['errorCode']);
  final errorMessage = _string(map['errorMessage']);
  final nativeErrorCode = _string(map['nativeErrorCode']);

  final invalidReason = switch ((
    id,
    revision,
    downloadedBytes,
    createdAt,
    updatedAt,
  )) {
    (null || '', _, _, _, _) => 'Native task has no valid id.',
    (_, null, _, _, _) => 'Native task has no valid revision.',
    (_, _, null, _, _) => 'Native task has no valid downloaded byte count.',
    (_, _, _, null, _) => 'Native task has no valid creation time.',
    (_, _, _, _, null) => 'Native task has no valid update time.',
    _ when revision! < 0 || downloadedBytes! < 0 =>
      'Native task contains a negative counter.',
    _
        when map['totalBytes'] != null &&
            (totalBytes == null || totalBytes < 0) =>
      'Native task has no valid total byte count.',
    _ => null,
  };

  if (invalidReason != null) {
    return _failedDecodedTask(
      id: id,
      revision: revision,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      createdAtEpochMs: createdAtEpochMs,
      updatedAtEpochMs: updatedAtEpochMs,
      message: errorMessage ?? invalidReason,
      nativeCode: nativeErrorCode ?? errorCode,
    );
  }
  if (status == null) {
    return _failedDecodedTask(
      id: id,
      revision: revision,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      createdAtEpochMs: createdAtEpochMs,
      updatedAtEpochMs: updatedAtEpochMs,
      message: errorMessage ?? 'Unknown native download status: $rawStatus.',
      nativeCode: rawStatus ?? nativeErrorCode ?? errorCode,
    );
  }
  if (status == BackgroundDownloadStatus.completed && filePath == null) {
    return _failedDecodedTask(
      id: id,
      revision: revision,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      createdAtEpochMs: createdAtEpochMs,
      updatedAtEpochMs: updatedAtEpochMs,
      message: errorMessage ?? 'Completed native task has no package path.',
      nativeCode: nativeErrorCode ?? errorCode,
    );
  }

  BackgroundDownloadFailure? failure;
  if (errorCode != null) {
    final mappedCode = _errorCode(errorCode);
    failure = BackgroundDownloadFailure(
      code: mappedCode ?? UpdateErrorCode.actionFailed,
      message: errorMessage ?? errorCode,
      nativeCode:
          mappedCode == null ? (nativeErrorCode ?? errorCode) : nativeErrorCode,
    );
  } else if (status == BackgroundDownloadStatus.failed) {
    failure = BackgroundDownloadFailure(
      code: UpdateErrorCode.actionFailed,
      message: errorMessage ?? 'Background download failed.',
      nativeCode: nativeErrorCode,
    );
  }

  return BackgroundDownloadTask(
    id: id!,
    revision: revision!,
    status: status,
    downloadedBytes: downloadedBytes!,
    totalBytes: totalBytes,
    filePath: filePath,
    failure: failure,
    createdAt: createdAt!,
    updatedAt: updatedAt!,
  );
}

BackgroundDownloadTask _failedDecodedTask({
  String? id,
  int? revision,
  int? downloadedBytes,
  int? totalBytes,
  int? createdAtEpochMs,
  int? updatedAtEpochMs,
  required String message,
  String? nativeCode,
}) {
  return BackgroundDownloadTask(
    id: id?.isNotEmpty == true ? id! : 'unknown',
    revision: revision != null && revision >= 0 ? revision : 0,
    status: BackgroundDownloadStatus.failed,
    downloadedBytes:
        downloadedBytes != null && downloadedBytes >= 0 ? downloadedBytes : 0,
    totalBytes: totalBytes != null && totalBytes >= 0 ? totalBytes : null,
    failure: BackgroundDownloadFailure(
      code: UpdateErrorCode.actionFailed,
      message: message,
      nativeCode: nativeCode,
    ),
    createdAt: _dateTime(createdAtEpochMs ?? 0),
    updatedAt: _dateTime(updatedAtEpochMs ?? createdAtEpochMs ?? 0),
  );
}

DateTime _dateTime(int epochMilliseconds) {
  try {
    return DateTime.fromMillisecondsSinceEpoch(epochMilliseconds);
  } on ArgumentError {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

DateTime? _tryDateTime(int? epochMilliseconds) {
  if (epochMilliseconds == null) {
    return null;
  }
  try {
    return DateTime.fromMillisecondsSinceEpoch(epochMilliseconds);
  } on ArgumentError {
    return null;
  }
}

int? _safeInt(Object? value) {
  if (value is! num || !value.isFinite) {
    return null;
  }
  final integer = value.toInt();
  return value == integer ? integer : null;
}

String? _string(Object? value) => value is String ? value : null;

String? _nonBlankString(Object? value) {
  final string = _string(value)?.trim();
  return string == null || string.isEmpty ? null : string;
}

BackgroundDownloadStatus? _status(String? value) {
  for (final status in BackgroundDownloadStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  return null;
}

UpdateErrorCode? _errorCode(String value) {
  for (final code in UpdateErrorCode.values) {
    if (code.value == value) {
      return code;
    }
  }
  return null;
}
