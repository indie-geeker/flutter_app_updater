import 'dart:io';

import 'package_download_posix_lock.dart';

/// An advisory OS-level lock that owns one package download target.
final class PackageDownloadLock {
  final RandomAccessFile _handle;
  final PackageDownloadPosixLock? _owner;
  bool _released = false;

  PackageDownloadLock._(this._handle, this._owner);

  /// Attempts to own [savePath] without waiting for another process.
  ///
  /// The lock file remains on disk after release so deleting and recreating an
  /// inode cannot let two writers believe they own the same target.
  static Future<PackageDownloadLock?> tryAcquire(String savePath) async {
    final target = File(savePath).absolute;
    final parent = await target.parent.resolveSymbolicLinks();
    final name = target.uri.pathSegments.last;
    final canonicalPath = '$parent${Platform.pathSeparator}$name';
    PackageDownloadPosixLock? owner;
    if (!Platform.isWindows) {
      owner = await PackageDownloadPosixLock.tryAcquire(
          '$canonicalPath.download.owner');
      if (owner == null) return null;
    }
    RandomAccessFile? handle;
    try {
      final path = '$canonicalPath.download.lock';
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw FileSystemException('Download lock must be a regular file', path);
      }
      handle = await File(path).open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.exclusive);
      } on FileSystemException {
        await handle.close();
        handle = null;
        owner?.release();
        return null;
      }
      return PackageDownloadLock._(handle, owner);
    } catch (_) {
      try {
        await handle?.close();
      } finally {
        owner?.release();
      }
      rethrow;
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
    _owner?.release();
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }
}
