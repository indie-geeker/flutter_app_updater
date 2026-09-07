import 'dart:io';
import 'package:flutter_app_updater/src/download/package_download_lock.dart';

Future<void> main(List<String> args) async {
  if (args.length == 2 && args[1] == '--legacy') {
    final file =
        await File('${args.first}.download.lock').open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
      stdout.writeln('acquired');
      await file.unlock();
    } on FileSystemException {
      stdout.writeln('blocked');
    } finally {
      await file.close();
    }
    return;
  }
  final lock = await PackageDownloadLock.tryAcquire(args.first);
  stdout.writeln(lock == null ? 'blocked' : 'acquired');
  if (args.contains('--hold') && lock != null) {
    await stdin.first;
  }
  await lock?.release();
}
