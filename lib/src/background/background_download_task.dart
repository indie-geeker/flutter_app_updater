import '../models/update_error_code.dart';

/// Durable lifecycle state of an Android background download.
enum BackgroundDownloadStatus {
  /// Accepted but not yet downloading.
  queued,

  /// Currently transferring bytes.
  running,

  /// Paused until network constraints are satisfied.
  waitingForNetwork,

  /// Paused until sufficient storage is available.
  waitingForStorage,

  /// Temporarily suspended by Android.
  pausedBySystem,

  /// Transfer complete and validating size, hash, and APK identity.
  verifying,

  /// Verified artifact is ready for explicit installation.
  completed,

  /// Ended with a structured failure.
  failed,

  /// Ended after a cancellation request.
  canceled,
}

/// Failure retained with a terminal background download snapshot.
class BackgroundDownloadFailure {
  /// Stable updater failure code.
  final UpdateErrorCode code;

  /// Human-readable failure diagnostic.
  final String message;

  /// Optional platform-specific diagnostic code.
  final String? nativeCode;

  /// Creates retained failure details.
  const BackgroundDownloadFailure({
    required this.code,
    required this.message,
    this.nativeCode,
  });
}

/// Structured exception thrown by manager control operations.
class BackgroundDownloadException implements Exception {
  /// Stable updater failure code.
  final UpdateErrorCode code;

  /// Human-readable failure diagnostic.
  final String message;

  /// Optional platform-specific diagnostic code.
  final String? nativeCode;

  /// Creates a background control exception.
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

/// Immutable persisted snapshot of one Android background download.
class BackgroundDownloadTask {
  /// Stable task identifier assigned by the native implementation.
  final String id;

  /// Monotonic revision used to order and deduplicate snapshots.
  final int revision;

  /// Current durable lifecycle state.
  final BackgroundDownloadStatus status;

  /// Number of bytes persisted so far.
  final int downloadedBytes;

  /// Expected total size, when reported.
  final int? totalBytes;

  /// Verified local artifact path, available after completion.
  final String? filePath;

  /// Terminal failure details, when [status] is failed.
  final BackgroundDownloadFailure? failure;

  /// Time at which the task was accepted.
  final DateTime createdAt;

  /// Time at which this snapshot was produced.
  final DateTime updatedAt;

  /// Creates an immutable background task snapshot.
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

  /// Whether no further lifecycle transition is expected.
  bool get isTerminal =>
      status == BackgroundDownloadStatus.completed ||
      status == BackgroundDownloadStatus.failed ||
      status == BackgroundDownloadStatus.canceled;
}
