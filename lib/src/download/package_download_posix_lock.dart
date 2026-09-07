import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Handle-scoped Unix ownership, independent of the legacy process-level lock.
///
/// A separate inode is essential: closing a failed flock contender must not
/// release the owner's legacy fcntl locks. Both persistent files remain on disk.
final class PackageDownloadPosixLock {
  final int _fd;
  bool _released = false;

  PackageDownloadPosixLock._(this._fd);

  static final _libc = DynamicLibrary.process();
  static final _open = _libc.lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)>('open');
  static final _flock = _libc.lookupFunction<Int32 Function(Int32, Int32),
      int Function(int, int)>('flock');
  static final _close =
      _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static final _errno = _libc
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
    Platform.isMacOS || Platform.isIOS
        ? '__error'
        : Platform.isAndroid
            ? '__errno'
            : '__errno_location',
  );

  /// Attempts a nonblocking exclusive lock without following a final symlink.
  static Future<PackageDownloadPosixLock?> tryAcquire(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException('Download owner must be a regular file', path);
    }
    // Create without truncation. The native open deliberately omits O_CREAT,
    // avoiding platform-specific variadic calling conventions for its mode.
    final creator = await File(path).open(mode: FileMode.append);
    await creator.close();
    final nativePath = path.toNativeUtf8();
    final int fd;
    try {
      final darwin = Platform.isMacOS || Platform.isIOS;
      fd = _open(
          nativePath,
          2 |
              (darwin ? 0x100 : 0x20000) |
              (darwin ? 0x1000000 : 0x80000)); // RDWR | NOFOLLOW | CLOEXEC
    } finally {
      malloc.free(nativePath);
    }
    if (fd < 0) {
      throw FileSystemException('Unable to open download ownership file', path,
          OSError('open', _errno().value));
    }
    if (_flock(fd, 2 | 4) == 0) return PackageDownloadPosixLock._(fd);
    final error = _errno().value;
    _close(fd);
    if (error == 11 || error == 35) return null; // EAGAIN / EWOULDBLOCK
    throw FileSystemException('Unable to lock download ownership file', path,
        OSError('flock', error));
  }

  /// Closing the descriptor releases ownership, including on process exit.
  void release() {
    if (_released) return;
    _released = true;
    _close(_fd);
  }
}
