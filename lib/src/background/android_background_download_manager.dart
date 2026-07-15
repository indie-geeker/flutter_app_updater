import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../actions/update_action.dart';
import '../channel/flutter_app_updater_platform_interface.dart';
import '../download/package_downloader.dart';
import '../models/update_error_code.dart';
import 'background_download_task.dart';

/// Controls durable, OS-owned Android package downloads.
///
/// The manager is Android-only. It persists task state through the platform
/// implementation so a host can reconcile work after process restart. Public
/// operations throw [BackgroundDownloadException] with structured codes for
/// native or state failures, and [UnsupportedError] on other platforms.
class AndroidBackgroundDownloadManager {
  FlutterAppUpdaterPlatform get _platform => FlutterAppUpdaterPlatform.instance;

  late final Stream<BackgroundDownloadTask> _backgroundDownloads =
      _platform.watchBackgroundDownloads();

  /// Creates a manager bound to the active platform implementation.
  AndroidBackgroundDownloadManager();

  /// Starts a verified background download for [action].
  ///
  /// The action must contain trusted HTTPS, exact size, and SHA-256 metadata.
  Future<BackgroundDownloadTask> start(DownloadPackageAction action) async {
    _ensureAndroid();
    _validateAction(action);
    return _perform(
      () => _platform.startBackgroundDownload(
        packageUrl: action.packageUrl,
        packageType: action.packageType,
        packageSizeBytes: action.packageSizeBytes,
        sha256: action.sha256.trim().toLowerCase(),
      ),
      fallbackCode: UpdateErrorCode.backgroundDownloadStartRejected,
    );
  }

  /// Returns the latest snapshot for [taskId].
  Future<BackgroundDownloadTask> get(String taskId) async {
    _ensureAndroid();
    final id = _validateTaskId(taskId);
    return _perform(
      () => _platform.getBackgroundDownload(id),
      fallbackCode: UpdateErrorCode.backgroundDownloadNotFound,
    );
  }

  /// Returns snapshots for all retained background download tasks.
  Future<List<BackgroundDownloadTask>> list() async {
    _ensureAndroid();
    return _perform(
      _platform.listBackgroundDownloads,
      fallbackCode: UpdateErrorCode.backgroundDownloadUnavailable,
    );
  }

  /// Returns retained tasks that have not reached a terminal state.
  Future<List<BackgroundDownloadTask>> listUnfinished() async {
    final tasks = await list();
    return tasks.where((task) => !task.isTerminal).toList(growable: false);
  }

  /// Watches revision-ordered snapshots for [taskId] until it is terminal.
  ///
  /// The initial persisted snapshot is reconciled with events that arrive while
  /// it is loading; duplicate or older revisions are suppressed.
  Stream<BackgroundDownloadTask> watch(String taskId) {
    _ensureAndroid();
    return _watch(_validateTaskId(taskId));
  }

  /// Requests that a resumable task continue.
  Future<BackgroundDownloadTask> resume(String taskId) async {
    _ensureAndroid();
    final id = _validateTaskId(taskId);
    return _perform(
      () => _platform.resumeBackgroundDownload(id),
      fallbackCode: UpdateErrorCode.backgroundDownloadInvalidState,
    );
  }

  /// Requests cancellation and returns the resulting task snapshot.
  Future<BackgroundDownloadTask> cancel(String taskId) async {
    _ensureAndroid();
    final id = _validateTaskId(taskId);
    return _perform(
      () => _platform.cancelBackgroundDownload(id),
      fallbackCode: UpdateErrorCode.backgroundDownloadInvalidState,
    );
  }

  /// Removes retained task state for [taskId].
  Future<void> remove(String taskId) async {
    _ensureAndroid();
    final id = _validateTaskId(taskId);
    await _perform(
      () => _platform.removeBackgroundDownload(id),
      fallbackCode: UpdateErrorCode.backgroundDownloadInvalidState,
    );
  }

  /// Creates a local APK install action for a completed verified task.
  ///
  /// This method does not launch the installer.
  Future<InstallPackageAction> createInstallAction(String taskId) async {
    _ensureAndroid();
    final id = _validateTaskId(taskId);
    final packagePath = await _perform(
      () => _platform.prepareBackgroundDownloadInstall(id),
      fallbackCode: UpdateErrorCode.backgroundDownloadInvalidState,
    );
    final normalizedPath = packagePath.trim();
    if (normalizedPath.isEmpty) {
      throw const BackgroundDownloadException(
        code: UpdateErrorCode.backgroundDownloadInvalidState,
        message: 'The completed background download has no package path.',
      );
    }
    return InstallPackageAction(
      packagePath: normalizedPath,
      packageType: PackageType.apk,
    );
  }

  Stream<BackgroundDownloadTask> _watch(String taskId) {
    late StreamController<BackgroundDownloadTask> controller;
    StreamSubscription<BackgroundDownloadTask>? eventSubscription;
    final bufferedEvents = <BackgroundDownloadTask>[];
    var snapshotPending = true;
    var stopped = false;
    var latestRevision = -1;

    Future<void> stop() async {
      if (stopped) {
        return;
      }
      stopped = true;
      await eventSubscription?.cancel();
      if (!controller.isClosed) {
        await controller.close();
      }
    }

    void emit(BackgroundDownloadTask task) {
      if (stopped || task.revision <= latestRevision) {
        return;
      }
      latestRevision = task.revision;
      controller.add(task);
      if (task.isTerminal) {
        unawaited(stop());
      }
    }

    void reconcileInitialBatch(BackgroundDownloadTask snapshot) {
      snapshotPending = false;
      final tasksByRevision = <int, BackgroundDownloadTask>{
        snapshot.revision: snapshot,
      };
      for (final task in bufferedEvents) {
        if (task.revision >= snapshot.revision) {
          tasksByRevision[task.revision] = task;
        }
      }
      bufferedEvents.clear();

      final orderedTasks = tasksByRevision.values.toList()
        ..sort((left, right) => left.revision.compareTo(right.revision));
      final newestRevision = orderedTasks.last.revision;
      for (final task in orderedTasks) {
        if (task.isTerminal && task.revision != newestRevision) {
          continue;
        }
        emit(task);
        if (stopped) {
          return;
        }
      }
    }

    controller = StreamController<BackgroundDownloadTask>(
      onListen: () {
        eventSubscription = _backgroundDownloads.listen(
          (task) {
            if (stopped || task.id != taskId) {
              return;
            }
            if (snapshotPending) {
              bufferedEvents.add(task);
            } else {
              emit(task);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (stopped) {
              return;
            }
            controller.addError(
              _mapException(
                error,
                fallbackCode: UpdateErrorCode.backgroundDownloadUnavailable,
              ),
              stackTrace,
            );
            unawaited(stop());
          },
          onDone: () {
            if (stopped) {
              return;
            }
            controller.addError(
              const BackgroundDownloadException(
                code: UpdateErrorCode.backgroundDownloadUnavailable,
                message: 'The background download event stream closed.',
              ),
            );
            unawaited(stop());
          },
        );

        () async {
          try {
            final snapshot = await _perform(
              () => _platform.getBackgroundDownload(taskId),
              fallbackCode: UpdateErrorCode.backgroundDownloadNotFound,
            );
            if (stopped) {
              return;
            }
            reconcileInitialBatch(snapshot);
          } catch (error, stackTrace) {
            if (!stopped) {
              controller.addError(
                _mapException(
                  error,
                  fallbackCode: UpdateErrorCode.backgroundDownloadNotFound,
                ),
                stackTrace,
              );
              await stop();
            }
          }
        }();
      },
      onCancel: () async {
        await stop();
      },
    );
    return controller.stream;
  }

  Future<T> _perform<T>(
    Future<T> Function() operation, {
    required UpdateErrorCode fallbackCode,
  }) async {
    try {
      return await operation();
    } catch (error) {
      throw _mapException(error, fallbackCode: fallbackCode);
    }
  }

  BackgroundDownloadException _mapException(
    Object error, {
    required UpdateErrorCode fallbackCode,
  }) {
    if (error is BackgroundDownloadException) {
      return error;
    }
    if (error is MissingPluginException) {
      return BackgroundDownloadException(
        code: UpdateErrorCode.backgroundDownloadUnavailable,
        message:
            error.message ?? 'Android background downloads are unavailable.',
      );
    }
    if (error is PlatformException) {
      return BackgroundDownloadException(
        code: _mapPlatformCode(error.code, fallbackCode),
        message: error.message ?? error.code,
        nativeCode: error.code,
      );
    }
    return BackgroundDownloadException(
      code: fallbackCode,
      message: error.toString(),
    );
  }

  UpdateErrorCode _mapPlatformCode(
    String nativeCode,
    UpdateErrorCode fallbackCode,
  ) {
    return switch (nativeCode) {
      'BACKGROUND_DOWNLOAD_UNAVAILABLE' ||
      'PLATFORM_NOT_SUPPORTED' =>
        UpdateErrorCode.backgroundDownloadUnavailable,
      'BACKGROUND_DOWNLOAD_NOT_FOUND' =>
        UpdateErrorCode.backgroundDownloadNotFound,
      'BACKGROUND_DOWNLOAD_START_REJECTED' =>
        UpdateErrorCode.backgroundDownloadStartRejected,
      'BACKGROUND_DOWNLOAD_INVALID_STATE' =>
        UpdateErrorCode.backgroundDownloadInvalidState,
      'BACKGROUND_STORAGE_UNAVAILABLE' =>
        UpdateErrorCode.backgroundStorageUnavailable,
      'PACKAGE_TOO_LARGE' => UpdateErrorCode.packageTooLarge,
      'PACKAGE_HASH_MISMATCH' => UpdateErrorCode.packageHashMismatch,
      'PACKAGE_FILE_NOT_FOUND' => UpdateErrorCode.packageFileNotFound,
      _ => fallbackCode,
    };
  }

  void _ensureAndroid() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const BackgroundDownloadException(
        code: UpdateErrorCode.backgroundDownloadUnavailable,
        message: 'Background downloads are available only on Android.',
      );
    }
  }

  String _validateTaskId(String taskId) {
    final normalized = taskId.trim();
    if (normalized.isEmpty ||
        normalized.length > 128 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(normalized)) {
      throw ArgumentError.value(taskId, 'taskId', 'Must be a safe task ID.');
    }
    return normalized;
  }

  void _validateAction(DownloadPackageAction action) {
    if (action.packageType != PackageType.apk) {
      throw ArgumentError.value(
        action.packageType,
        'action.packageType',
        'Background downloads support APK packages only.',
      );
    }
    final size = action.packageSizeBytes;
    if (size <= 0 || size > PackageDownloader.defaultMaxDownloadBytes) {
      throw ArgumentError.value(
        size,
        'action.packageSizeBytes',
        'Must be exact, positive, and within the default download limit.',
      );
    }
    final sha256 = action.sha256.trim();
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) {
      throw ArgumentError.value(
        action.sha256,
        'action.sha256',
        'Must contain exactly 64 hexadecimal characters.',
      );
    }
    final packageUrl = action.packageUrl;
    if (packageUrl.userInfo.isNotEmpty ||
        packageUrl.hasQuery ||
        packageUrl.hasFragment ||
        !_isAllowedPackageUrl(packageUrl)) {
      throw ArgumentError(
        'Background downloads require a credential-free stable entry URL; '
            'the server may redirect to a short-lived signed URL.',
        'action.packageUrl',
      );
    }
  }

  bool _isAllowedPackageUrl(Uri uri) {
    if (!uri.hasAuthority) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') {
      return true;
    }
    if (scheme != 'http') {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == 'localhost' ||
        (InternetAddress.tryParse(host)?.isLoopback ?? false);
  }
}
