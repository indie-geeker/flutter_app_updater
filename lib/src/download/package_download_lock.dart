import 'dart:io';

/// An advisory OS-level lock that owns one package download target.
final class PackageDownloadLock {
  final RandomAccessFile _handle;
  bool _released = false;

  PackageDownloadLock._(this._handle);

  /// Attempts to own [savePath] without waiting for another process.
  ///
  /// The lock file remains on disk after release so deleting and recreating an
  /// inode cannot let two writers believe they own the same target.
  static Future<PackageDownloadLock?> tryAcquire(String savePath) async {
    final handle = await File('$savePath.download.lock').open(
      mode: FileMode.append,
    );
    try {
      await handle.lock(FileLock.exclusive);
      return PackageDownloadLock._(handle);
    } on FileSystemException {
      await handle.close();
      return null;
    }
  }

  /// Releases this process's ownership while retaining the lock file.
  Future<void> release() async {
    if (_released) {
      return;
    }
    _released = true;
    Object? failure;
    StackTrace? failureStackTrace;
    try {
      await _handle.unlock();
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    }
    try {
      await _handle.close();
    } catch (error, stackTrace) {
      failure ??= error;
      failureStackTrace ??= stackTrace;
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }
}
