import '../models/update_error_code.dart';

enum BackgroundDownloadStatus {
  queued,
  running,
  waitingForNetwork,
  waitingForStorage,
  pausedBySystem,
  verifying,
  completed,
  failed,
  canceled,
}

class BackgroundDownloadFailure {
  final UpdateErrorCode code;
  final String message;
  final String? nativeCode;

  const BackgroundDownloadFailure({
    required this.code,
    required this.message,
    this.nativeCode,
  });
}

class BackgroundDownloadException implements Exception {
  final UpdateErrorCode code;
  final String message;
  final String? nativeCode;

  const BackgroundDownloadException({
    required this.code,
    required this.message,
    this.nativeCode,
  });

  @override
  String toString() {
    final native = nativeCode == null ? '' : ', nativeCode: $nativeCode';
    return 'BackgroundDownloadException(${code.value}$native): $message';
  }
}

class BackgroundDownloadTask {
  final String id;
  final int revision;
  final BackgroundDownloadStatus status;
  final int downloadedBytes;
  final int? totalBytes;
  final String? filePath;
  final BackgroundDownloadFailure? failure;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BackgroundDownloadTask({
    required this.id,
    required this.revision,
    required this.status,
    required this.downloadedBytes,
    this.totalBytes,
    this.filePath,
    this.failure,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isTerminal =>
      status == BackgroundDownloadStatus.completed ||
      status == BackgroundDownloadStatus.failed ||
      status == BackgroundDownloadStatus.canceled;
}
