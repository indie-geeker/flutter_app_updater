import 'dart:async';

import '../core/app_updater.dart';
import '../models/update_error_code.dart';
import '../platform/update_action_event.dart';
import '../platform/update_action_executor.dart';

enum UpdateFlowPhase {
  idle,
  running,
  downloading,
  installing,
  permissionRequired,
  completed,
  failed,
  canceled,
}

class UpdateFlowState {
  final PreparedUpdateAvailable update;
  final UpdateFlowPhase phase;
  final int? receivedBytes;
  final int? totalBytes;
  final String? packagePath;
  final UpdateActionResult? result;

  const UpdateFlowState({
    required this.update,
    required this.phase,
    this.receivedBytes,
    this.totalBytes,
    this.packagePath,
    this.result,
  });

  factory UpdateFlowState.initial(PreparedUpdateAvailable update) {
    return UpdateFlowState(
      update: update,
      phase: UpdateFlowPhase.idle,
    );
  }

  double? get progress {
    final received = receivedBytes;
    final total = totalBytes;
    if (received == null || total == null || total <= 0) {
      return null;
    }
    return received / total;
  }

  bool get hasProgress => receivedBytes != null;

  bool get isRunning {
    return switch (phase) {
      UpdateFlowPhase.running ||
      UpdateFlowPhase.downloading ||
      UpdateFlowPhase.installing =>
        true,
      _ => false,
    };
  }

  bool get isTerminal {
    return switch (phase) {
      UpdateFlowPhase.completed ||
      UpdateFlowPhase.failed ||
      UpdateFlowPhase.canceled =>
        true,
      _ => false,
    };
  }

  String get statusLabel {
    return switch (phase) {
      UpdateFlowPhase.idle => 'Ready',
      UpdateFlowPhase.running => 'Starting',
      UpdateFlowPhase.downloading => 'Downloading',
      UpdateFlowPhase.installing => 'Installing',
      UpdateFlowPhase.permissionRequired => 'Permission required',
      UpdateFlowPhase.completed => 'Completed',
      UpdateFlowPhase.failed => 'Failed',
      UpdateFlowPhase.canceled => 'Canceled',
    };
  }

  UpdateFlowState copyWith({
    UpdateFlowPhase? phase,
    int? receivedBytes,
    int? totalBytes,
    bool clearProgress = false,
    String? packagePath,
    bool clearPackagePath = false,
    UpdateActionResult? result,
    bool clearResult = false,
  }) {
    return UpdateFlowState(
      update: update,
      phase: phase ?? this.phase,
      receivedBytes: clearProgress ? null : receivedBytes ?? this.receivedBytes,
      totalBytes: clearProgress ? null : totalBytes ?? this.totalBytes,
      packagePath: clearPackagePath ? null : packagePath ?? this.packagePath,
      result: clearResult ? null : result ?? this.result,
    );
  }
}

class UpdateFlowController {
  final AppUpdater updater;
  final PreparedUpdateAvailable update;
  final _changes = StreamController<UpdateFlowState>.broadcast(sync: true);

  StreamSubscription<UpdateActionEvent>? _subscription;
  late UpdateFlowState _state = UpdateFlowState.initial(update);
  var _isDisposed = false;

  UpdateFlowController({
    required this.updater,
    required this.update,
  });

  UpdateFlowState get state => _state;

  Stream<UpdateFlowState> get changes => _changes.stream;

  Future<void> start() async {
    if (_subscription != null || _isDisposed) {
      return;
    }
    _setState(
      UpdateFlowState.initial(update).copyWith(
        phase: UpdateFlowPhase.running,
      ),
    );
    _subscription = updater.performStream(update.recommendedAction).listen(
      _handleEvent,
      onError: _handleError,
      onDone: () {
        _subscription = null;
      },
    );
  }

  Future<void> retry() async {
    await _subscription?.cancel();
    _subscription = null;
    _setState(UpdateFlowState.initial(update));
    await start();
  }

  Future<void> cancel() async {
    await _subscription?.cancel();
    _subscription = null;
    _setState(
      UpdateFlowState.initial(update).copyWith(
        phase: UpdateFlowPhase.canceled,
      ),
    );
  }

  void dispose() {
    _isDisposed = true;
    unawaited(_subscription?.cancel());
    unawaited(_changes.close());
  }

  void _handleEvent(UpdateActionEvent event) {
    switch (event) {
      case UpdateActionStarted():
        _setState(
          _state.copyWith(
            phase: UpdateFlowPhase.running,
            clearResult: true,
          ),
        );
      case UpdateDownloadProgress(:final receivedBytes, :final totalBytes):
        _setState(
          _state.copyWith(
            phase: UpdateFlowPhase.downloading,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            clearResult: true,
          ),
        );
      case UpdateDownloadCompleted(:final result):
        _setState(
          _state.copyWith(
            phase: UpdateFlowPhase.downloading,
            result: result,
          ),
        );
      case UpdateInstallStarted(:final packagePath):
        _setState(
          _state.copyWith(
            phase: UpdateFlowPhase.installing,
            packagePath: packagePath,
          ),
        );
      case UpdateInstallPermissionRequired(:final packagePath):
        _setState(
          _state.copyWith(
            phase: UpdateFlowPhase.permissionRequired,
            packagePath: packagePath,
          ),
        );
      case UpdateActionCompleted(:final result):
        _setState(
          _state.copyWith(
            phase: UpdateFlowPhase.completed,
            result: result,
          ),
        );
      case UpdateActionFailed(:final result):
        _setState(
          _state.copyWith(
            phase: UpdateFlowPhase.failed,
            result: result,
          ),
        );
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    _setState(
      _state.copyWith(
        phase: UpdateFlowPhase.failed,
        result: UpdateActionResult.failure(
          code: UpdateErrorCode.packageDownloadFailed,
          message: error.toString(),
        ),
      ),
    );
  }

  void _setState(UpdateFlowState state) {
    if (_isDisposed) {
      return;
    }
    _state = state;
    _changes.add(state);
  }
}
