import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/download/package_download_lock.dart';
import 'package:flutter_app_updater/src/download/package_downloader.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_app_updater/src/platform/update_action_cancel_token.dart';
import 'package:flutter_app_updater/src/utils/retry_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('package_lock_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('another isolate cannot acquire or release the owners lock', () async {
    final path = '${tempDir.path}/isolate.apk';
    final first = await PackageDownloadLock.tryAcquire(path);
    expect(first, isNotNull);
    try {
      expect(
          await Isolate.run(() async {
            final other = await PackageDownloadLock.tryAcquire(path);
            await other?.release();
            return other != null;
          }),
          isFalse);
      final blocked = await Process.run('dart', [
        'test/fixtures/package_lock_probe.dart',
        path,
      ]);
      expect(blocked.exitCode, 0, reason: blocked.stderr.toString());
      expect(blocked.stdout.toString().trim(), 'blocked');
      final legacy = await Process.run('dart', [
        'test/fixtures/package_lock_probe.dart',
        path,
        '--legacy',
      ]);
      expect(legacy.exitCode, 0, reason: legacy.stderr.toString());
      expect(legacy.stdout.toString().trim(), 'blocked');
    } finally {
      await first!.release();
    }
    final reacquired = await PackageDownloadLock.tryAcquire(path);
    expect(reacquired, isNotNull);
    await reacquired!.release();
  });

  test('process termination releases both ownership layers', () async {
    final path = '${tempDir.path}/process-exit.apk';
    final process = await Process.start(
        'dart', ['test/fixtures/package_lock_probe.dart', path, '--hold']);
    try {
      final ready = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      expect(ready, 'acquired');
      expect(await PackageDownloadLock.tryAcquire(path), isNull);
    } finally {
      process.kill();
      await process.exitCode;
    }
    final next = await PackageDownloadLock.tryAcquire(path);
    expect(next, isNotNull);
    await next!.release();
  });

  test('canonical parent aliases share ownership and other targets do not',
      () async {
    final real = await Directory('${tempDir.path}/real').create();
    final alias = await Link('${tempDir.path}/alias').create(real.path);
    final first = await PackageDownloadLock.tryAcquire('${real.path}/app.apk');
    try {
      expect(await PackageDownloadLock.tryAcquire('${alias.path}/app.apk'),
          isNull);
      final other =
          await PackageDownloadLock.tryAcquire('${real.path}/other.apk');
      expect(other, isNotNull);
      await other!.release();
    } finally {
      await first!.release();
    }
  }, skip: Platform.isWindows);

  test('symlink ownership files are rejected without touching their target',
      () async {
    final path = '${tempDir.path}/symlink.apk';
    final victim = await File('${tempDir.path}/victim').writeAsString('keep');
    await Link('$path.download.owner').create(victim.path);
    await expectLater(PackageDownloadLock.tryAcquire(path),
        throwsA(isA<FileSystemException>()));
    expect(await victim.readAsString(), 'keep');
  }, skip: Platform.isWindows);

  test('pre-canceled download preserves another processes partial state',
      () async {
    final path = '${tempDir.path}/canceled.apk';
    final partial = await File('$path.download').writeAsString('owned bytes');
    final metadata =
        await File('$path.download.meta.0').writeAsString('owned metadata');
    final process = await Process.start('dart', [
      'test/fixtures/package_lock_holder.dart',
      '$path.download.lock',
    ]);
    await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    try {
      final result = await PackageDownloader(
              client: _SingleResponseClient(_successResponse()))
          .download(
              action: _action(),
              savePath: path,
              cancelToken: UpdateActionCancelToken()..cancel());
      expect(result.code, UpdateErrorCode.actionCanceled);
      expect(await partial.exists(), isTrue);
      expect(await partial.readAsString(), 'owned bytes');
      expect(await metadata.readAsString(), 'owned metadata');
    } finally {
      process.stdin.writeln('release');
      await process.exitCode;
    }
  });

  test('a helper process owns the target until it releases the OS lock',
      () async {
    final savePath = '${tempDir.path}/app.apk';
    final lockPath = '$savePath.download.lock';
    final process = await Process.start(
      'dart',
      ['test/fixtures/package_lock_holder.dart', lockPath],
      workingDirectory: Directory.current.path,
    );
    final ready = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    expect(ready, 'locked');
    try {
      final blockedClient = _SingleResponseClient(_successResponse());

      final blocked = await PackageDownloader(
        client: blockedClient,
        retryStrategy: RetryStrategy.disabled,
      ).download(action: _action(), savePath: savePath);

      expect(blocked.code, UpdateErrorCode.downloadInProgress);
      expect(blockedClient.calls, 0);
    } finally {
      process.stdin.writeln('release');
      expect(await process.exitCode, 0);
    }

    final allowed = await PackageDownloader(
      client: _SingleResponseClient(_successResponse()),
      retryStrategy: RetryStrategy.disabled,
    ).download(action: _action(), savePath: savePath);
    expect(allowed.isSuccess, isTrue);
  });

  test('an unused persistent lock file does not block a download', () async {
    final savePath = '${tempDir.path}/unused.apk';
    await File('$savePath.download.lock').writeAsString('persistent inode');

    final result = await PackageDownloader(
      client: _SingleResponseClient(_successResponse()),
      retryStrategy: RetryStrategy.disabled,
    ).download(action: _action(), savePath: savePath);

    expect(result.isSuccess, isTrue);
    expect(await File('$savePath.download.lock').exists(), isTrue);
  });

  test('cancellation and protocol, storage, and hash failures release the lock',
      () async {
    final cases = <String, Future<PackageDownloadResult> Function(String)>{
      'protocol': (path) => PackageDownloader(
            client: _SingleResponseClient(
              PackageDownloadResponse(
                statusCode: 400,
                headers: const {},
                bytes: const Stream.empty(),
              ),
            ),
            retryStrategy: RetryStrategy.disabled,
          ).download(action: _action(), savePath: path),
      'hash': (path) => PackageDownloader(
            client: _SingleResponseClient(
              PackageDownloadResponse(
                statusCode: 200,
                headers: const {'content-length': '13'},
                bytes: Stream.value(utf8.encode('tampered-data')),
              ),
            ),
            retryStrategy: RetryStrategy.disabled,
          ).download(action: _action(), savePath: path),
      'storage': (path) async {
        await Directory('$path.download').create();
        return PackageDownloader(
          client: _SingleResponseClient(_successResponse()),
          retryStrategy: RetryStrategy.disabled,
        ).download(action: _action(), savePath: path);
      },
      'cancellation': (path) async {
        final token = UpdateActionCancelToken();
        final client = _HangingClient();
        final result = PackageDownloader(
          client: client,
          retryStrategy: RetryStrategy.disabled,
        ).download(action: _action(), savePath: path, cancelToken: token);
        await client.started.future;
        token.cancel();
        return result;
      },
    };

    for (final entry in cases.entries) {
      final savePath = '${tempDir.path}/${entry.key}.apk';
      final result = await entry.value(savePath);
      expect(result.isSuccess, isFalse, reason: entry.key);
      final lock = await PackageDownloadLock.tryAcquire(savePath);
      expect(lock, isNotNull, reason: entry.key);
      await lock!.release();
    }
  });
}

PackageDownloadResponse _successResponse() => PackageDownloadResponse(
      statusCode: 200,
      headers: const {'content-length': '13'},
      bytes: Stream.value(utf8.encode('package-bytes')),
    );

DownloadPackageAction _action() {
  final bytes = utf8.encode('package-bytes');
  return DownloadPackageAction(
    packageUrl: Uri.parse('https://example.com/app.apk'),
    packageType: PackageType.apk,
    packageSizeBytes: bytes.length,
    sha256: crypto.sha256.convert(bytes).toString(),
  );
}

class _SingleResponseClient implements PackageDownloadClient {
  final PackageDownloadResponse response;
  int calls = 0;

  _SingleResponseClient(this.response);

  @override
  Future<PackageDownloadResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
    UpdateActionCancelToken? cancelToken,
  }) async {
    calls += 1;
    return response;
  }
}

class _HangingClient implements PackageDownloadClient {
  final started = Completer<void>();
  final response = Completer<PackageDownloadResponse>();

  @override
  Future<PackageDownloadResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
    UpdateActionCancelToken? cancelToken,
  }) {
    started.complete();
    return response.future;
  }
}
