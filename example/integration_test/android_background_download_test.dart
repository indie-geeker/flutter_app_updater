import 'dart:convert';
import 'dart:io';

import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _serverOrigin = String.fromEnvironment(
  'BACKGROUND_DOWNLOAD_SERVER',
  defaultValue: 'http://127.0.0.1:18080',
);
const _taskTimeout = Duration(minutes: 3);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final server = _VerificationServer(Uri.parse(_serverOrigin));
  final manager = AndroidBackgroundDownloadManager();

  setUp(() async {
    await server.configure(
      mode: 'range',
      etagMode: 'strong',
      etagValue: 'verification-v1',
    );
    await _removeAllTasks(manager);
  });

  tearDown(() => _removeAllTasks(manager));

  testWidgets(
    'public API completes, survives observer reattach, and creates only an install action',
    (_) async {
      final spec = await server.configure(
        mode: 'slow',
        etagMode: 'strong',
        chunkSize: 64 * 1024,
        delayPerChunkMs: 5,
      );
      final started = await manager.start(spec.action).timeout(_taskTimeout);
      final firstProgress = await manager
          .watch(started.id)
          .firstWhere((task) => task.downloadedBytes > 0 && !task.isTerminal)
          .timeout(_taskTimeout);

      // Canceling the observer must detach only the EventChannel listener. A
      // new watcher reconciles from the persistent native snapshot.
      final reattached = await manager
          .watch(started.id)
          .firstWhere((task) => task.revision >= firstProgress.revision)
          .timeout(_taskTimeout);
      expect(reattached.id, started.id);

      final completed = await _waitForStatus(
        manager,
        started.id,
        {BackgroundDownloadStatus.completed},
      );
      expect(completed.filePath, isNotEmpty);

      final action =
          await manager.createInstallAction(started.id).timeout(_taskTimeout);
      expect(action.packageType, PackageType.apk);
      expect(action.packagePath, completed.filePath);
      // createInstallAction deliberately does not execute InstallPackageExecutor,
      // so this test never launches Android's installer UI.
    },
    skip: !Platform.isAndroid,
  );

  testWidgets(
    'cancel persists a terminal tombstone',
    (_) async {
      final spec = await server.configure(
        mode: 'slow',
        chunkSize: 16 * 1024,
        delayPerChunkMs: 20,
      );
      final started = await manager.start(spec.action).timeout(_taskTimeout);
      await manager
          .watch(started.id)
          .firstWhere((task) => task.status == BackgroundDownloadStatus.running)
          .timeout(_taskTimeout);

      final canceled = await manager.cancel(started.id).timeout(_taskTimeout);

      expect(canceled.status, BackgroundDownloadStatus.canceled);
      expect(
        (await manager.get(started.id).timeout(_taskTimeout)).status,
        BackgroundDownloadStatus.canceled,
      );
    },
    skip: !Platform.isAndroid,
  );

  testWidgets(
    'controlled disconnect resumes with Range and a stable validator',
    (_) async {
      final metadata = await server.read();
      final interrupted = await server.configure(
        mode: 'disconnect',
        etagMode: 'strong',
        disconnectAfterBytes: _disconnectPoint(metadata.length),
      );
      final started =
          await manager.start(interrupted.action).timeout(_taskTimeout);
      final waiting = await _waitForStatus(
        manager,
        started.id,
        {
          BackgroundDownloadStatus.waitingForNetwork,
          BackgroundDownloadStatus.pausedBySystem,
        },
      );
      expect(waiting.downloadedBytes, greaterThan(0));

      await server.configure(mode: 'range', etagMode: 'strong');
      await manager.resume(started.id).timeout(_taskTimeout);

      final completed = await _waitForStatus(
        manager,
        started.id,
        {BackgroundDownloadStatus.completed},
      );
      expect(completed.downloadedBytes, interrupted.length);
      final observations = (await server.read()).observations;
      expect(
        observations,
        contains(
          isA<_ArtifactObservation>()
              .having((item) => item.requestRange, 'Range',
                  'bytes=${waiting.downloadedBytes}-')
              .having((item) => item.requestIfRange, 'If-Range',
                  '"verification-v1"')
              .having((item) => item.responseStatus, 'status',
                  HttpStatus.partialContent),
        ),
      );
    },
    skip: !Platform.isAndroid,
  );

  testWidgets(
    'validator change forces a clean restart instead of appending stale bytes',
    (_) async {
      final metadata = await server.read();
      final interrupted = await server.configure(
        mode: 'disconnect',
        etagMode: 'strong',
        etagValue: 'before-change',
        disconnectAfterBytes: _disconnectPoint(metadata.length),
      );
      final started =
          await manager.start(interrupted.action).timeout(_taskTimeout);
      final waiting = await _waitForStatus(
        manager,
        started.id,
        {
          BackgroundDownloadStatus.waitingForNetwork,
          BackgroundDownloadStatus.pausedBySystem,
        },
      );

      await server.configure(
        mode: 'range',
        etagMode: 'strong',
        etagValue: 'after-change',
      );
      await manager.resume(started.id).timeout(_taskTimeout);

      final completed = await _waitForStatus(
        manager,
        started.id,
        {BackgroundDownloadStatus.completed},
      );
      expect(completed.downloadedBytes, interrupted.length);
      final observations = (await server.read()).observations;
      expect(
        observations,
        contains(
          isA<_ArtifactObservation>()
              .having((item) => item.requestRange, 'Range',
                  'bytes=${waiting.downloadedBytes}-')
              .having(
                  (item) => item.requestIfRange, 'If-Range', '"before-change"')
              .having((item) => item.responseStatus, 'status', HttpStatus.ok)
              .having((item) => item.responseEtag, 'ETag', '"after-change"'),
        ),
      );
    },
    skip: !Platform.isAndroid,
  );

  testWidgets(
    'exact EOF 416 completes a fully checkpointed artifact',
    (_) async {
      final metadata = await server.read();
      final interrupted = await server.configure(
        mode: 'disconnect',
        etagMode: 'strong',
        disconnectAfterBytes: metadata.length,
      );
      final started =
          await manager.start(interrupted.action).timeout(_taskTimeout);
      final waiting = await _waitForStatus(
        manager,
        started.id,
        {
          BackgroundDownloadStatus.waitingForNetwork,
          BackgroundDownloadStatus.pausedBySystem,
        },
      );
      expect(waiting.downloadedBytes, interrupted.length);

      await server.configure(mode: 'exact416', etagMode: 'strong');
      await manager.resume(started.id).timeout(_taskTimeout);

      final completed = await _waitForStatus(
        manager,
        started.id,
        {BackgroundDownloadStatus.completed},
      );
      expect(completed.downloadedBytes, interrupted.length);
      final observations = (await server.read()).observations;
      expect(
        observations,
        contains(
          isA<_ArtifactObservation>()
              .having((item) => item.requestRange, 'Range',
                  'bytes=${interrupted.length}-')
              .having((item) => item.responseStatus, 'status',
                  HttpStatus.requestedRangeNotSatisfiable)
              .having((item) => item.responseContentRange, 'Content-Range',
                  'bytes */${interrupted.length}'),
        ),
      );
    },
    skip: !Platform.isAndroid,
  );
}

int _disconnectPoint(int length) => (length ~/ 3).clamp(1, length - 1);

Future<BackgroundDownloadTask> _waitForStatus(
  AndroidBackgroundDownloadManager manager,
  String taskId,
  Set<BackgroundDownloadStatus> statuses,
) async {
  final snapshot = await manager.get(taskId).timeout(_taskTimeout);
  if (statuses.contains(snapshot.status)) return snapshot;
  return manager
      .watch(taskId)
      .firstWhere((task) => statuses.contains(task.status))
      .timeout(_taskTimeout);
}

Future<void> _removeAllTasks(AndroidBackgroundDownloadManager manager) async {
  final tasks = await manager.list().timeout(_taskTimeout);
  for (final task in tasks) {
    var terminal = task;
    if (!task.isTerminal) {
      terminal = await manager.cancel(task.id).timeout(_taskTimeout);
    }
    if (terminal.isTerminal) {
      await manager.remove(terminal.id).timeout(_taskTimeout);
    }
  }
}

final class _VerificationServer {
  const _VerificationServer(this.origin);

  final Uri origin;

  Future<_ArtifactSpec> read() => _request('GET');

  Future<_ArtifactSpec> configure({
    required String mode,
    String? etagMode,
    String? etagValue,
    int? disconnectAfterBytes,
    int? delayPerChunkMs,
    int? chunkSize,
  }) {
    return _request('POST', <String, Object?>{
      'mode': mode,
      if (etagMode != null) 'etagMode': etagMode,
      if (etagValue != null) 'etagValue': etagValue,
      if (disconnectAfterBytes != null)
        'disconnectAfterBytes': disconnectAfterBytes,
      if (delayPerChunkMs != null) 'delayPerChunkMs': delayPerChunkMs,
      if (chunkSize != null) 'chunkSize': chunkSize,
    });
  }

  Future<_ArtifactSpec> _request(
    String method, [
    Map<String, Object?>? body,
  ]) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final url = origin.resolve('/control');
      final request = method == 'POST'
          ? await client.postUrl(url)
          : await client.getUrl(url);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Verification server returned '
            '${response.statusCode}: $text');
      }
      final json = jsonDecode(text) as Map<String, dynamic>;
      return _ArtifactSpec(
        url: Uri.parse(json['artifactUrl'] as String),
        length: json['length'] as int,
        sha256: json['sha256'] as String,
        observations: (json['observations'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(_ArtifactObservation.fromJson)
            .toList(growable: false),
      );
    } finally {
      client.close(force: true);
    }
  }
}

final class _ArtifactSpec {
  const _ArtifactSpec({
    required this.url,
    required this.length,
    required this.sha256,
    required this.observations,
  });

  final Uri url;
  final int length;
  final String sha256;
  final List<_ArtifactObservation> observations;

  DownloadPackageAction get action => DownloadPackageAction(
        packageUrl: url,
        packageType: PackageType.apk,
        packageSizeBytes: length,
        sha256: sha256,
      );
}

final class _ArtifactObservation {
  const _ArtifactObservation({
    required this.requestRange,
    required this.requestIfRange,
    required this.responseStatus,
    required this.responseContentRange,
    required this.responseEtag,
  });

  factory _ArtifactObservation.fromJson(Map<String, dynamic> json) =>
      _ArtifactObservation(
        requestRange: json['requestRange'] as String?,
        requestIfRange: json['requestIfRange'] as String?,
        responseStatus: json['responseStatus'] as int,
        responseContentRange: json['responseContentRange'] as String?,
        responseEtag: json['responseEtag'] as String?,
      );

  final String? requestRange;
  final String? requestIfRange;
  final int responseStatus;
  final String? responseContentRange;
  final String? responseEtag;
}
