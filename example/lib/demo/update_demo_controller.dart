import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

import 'demo_manifest_factory.dart';
import 'demo_scenario.dart';
import 'simulated_update_executor.dart';

enum DemoPhase {
  idle,
  checking,
  updateAvailable,
  upToDate,
  checkFailed,
  executing,
  succeeded,
  failed,
  canceled,
}

class UpdateDemoController extends ChangeNotifier {
  DemoScenario _scenario;
  DemoPhase _phase = DemoPhase.idle;
  PreparedUpdateAvailable? _preparedUpdate;
  UpdateErrorCode? _errorCode;
  String? _message;
  double? _progress;
  int? _downloadedBytes;
  int? _totalBytes;
  AppUpdater? _activeUpdater;
  UpdateActionCancelToken? _cancelToken;
  int _operationGeneration = 0;
  bool _disposed = false;

  UpdateDemoController({DemoScenario? scenario})
      : _scenario = scenario ?? DemoScenario.defaults();

  DemoScenario get scenario => _scenario;
  DemoPhase get phase => _phase;
  PreparedUpdateAvailable? get preparedUpdate => _preparedUpdate;
  UpdateErrorCode? get errorCode => _errorCode;
  String? get message => _message;
  double? get progress => _progress;
  int? get downloadedBytes => _downloadedBytes;
  int? get totalBytes => _totalBytes;

  bool get isBusy =>
      _phase == DemoPhase.checking || _phase == DemoPhase.executing;

  void updateScenario(DemoScenario value) {
    if (isBusy) {
      return;
    }
    _operationGeneration++;
    _scenario = value;
    _clearFlow();
    _phase = DemoPhase.idle;
    _notify();
  }

  Future<void> checkForUpdate() async {
    final generation = ++_operationGeneration;
    _clearFlow();
    _phase = DemoPhase.checking;
    _message = 'Checking the simulated release.';
    _notify();

    try {
      final manifest = const DemoManifestFactory().build(_scenario);
      final updater = AppUpdater(
        source: UpdateSource.staticManifest(manifest: manifest),
        selector: _scenario.toSelector(),
        executors: [
          SimulatedUpdateExecutor(
            outcome: _scenario.outcome,
            duration: _scenario.executionDuration,
            totalBytes: _scenario.packageSizeBytes,
            succeedOnRetry: _scenario.succeedOnRetry,
          ),
        ],
      );
      final result = await updater.checkAndPrepare();
      if (!_isCurrent(generation)) {
        return;
      }

      switch (result) {
        case PreparedUpdateAvailable():
          _activeUpdater = updater;
          _preparedUpdate = result;
          _phase = DemoPhase.updateAvailable;
          _message = 'Update ${result.candidate.version} is available.';
        case PreparedUpdateNotAvailable():
          _phase = DemoPhase.upToDate;
          _message = _scenario.runtimeChannel != _scenario.releaseChannel
              ? 'No release selected: runtime channel '
                  '${_scenario.runtimeChannel} does not match release channel '
                  '${_scenario.releaseChannel}.'
              : 'The installed version is up to date.';
        case PreparedUpdateCheckFailed(:final code, :final message):
          _phase = DemoPhase.checkFailed;
          _errorCode = code;
          _message = code == UpdateErrorCode.noMatchingRelease &&
                  _scenario.runtimeArchitecture != _scenario.releaseArchitecture
              ? 'No release selected: runtime architecture '
                  '${_scenario.runtimeArchitecture} does not match release '
                  'architecture ${_scenario.releaseArchitecture}.'
              : message;
      }
    } on ArgumentError catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      _phase = DemoPhase.checkFailed;
      _errorCode = UpdateErrorCode.manifestInvalid;
      _message = error.message?.toString() ?? error.toString();
    } on FormatException catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      _phase = DemoPhase.checkFailed;
      _errorCode = UpdateErrorCode.manifestInvalid;
      _message = error.message;
    }
    _notify();
  }

  Future<void> performRecommended() async {
    final updater = _activeUpdater;
    final update = _preparedUpdate;
    if (updater == null || update == null || isBusy) {
      return;
    }

    final generation = ++_operationGeneration;
    final cancelToken = UpdateActionCancelToken();
    _cancelToken = cancelToken;
    _phase = DemoPhase.executing;
    _errorCode = null;
    _message = 'Running the simulated update.';
    _progress = null;
    if (_isDownloadRelated(update.recommendedAction)) {
      _downloadedBytes = 0;
      _totalBytes = _scenario.packageSizeBytes;
    } else {
      _downloadedBytes = null;
      _totalBytes = null;
    }
    _notify();

    await for (final event in updater.performRecommendedStream(
      update,
      cancelToken: cancelToken,
    )) {
      if (!_isCurrent(generation)) {
        return;
      }
      switch (event) {
        case UpdateActionStarted():
          _message = 'Preparing the simulated update.';
        case UpdateActionProgress(
            :final fraction,
            :final downloadedBytes,
            :final totalBytes,
          ):
          _progress = fraction;
          _downloadedBytes = downloadedBytes;
          _totalBytes = totalBytes;
          _message = fraction == null
              ? 'Simulating update transfer.'
              : 'Simulating update transfer ${(fraction * 100).round()}%.';
        case UpdateActionCompleted(:final result):
          _cancelToken = null;
          _errorCode = result.code;
          _message = result.message;
          if (result.isSuccess) {
            _phase = DemoPhase.succeeded;
            _message = 'The update action completed in simulation.';
          } else if (result.code == UpdateErrorCode.actionCanceled) {
            _phase = DemoPhase.canceled;
          } else {
            _phase = DemoPhase.failed;
          }
      }
      _notify();
    }
  }

  void cancel() {
    if (_phase != DemoPhase.executing) {
      return;
    }
    _cancelToken?.cancel();
    _message = 'Cancel requested.';
    _notify();
  }

  void deferUpdate() {
    if (_preparedUpdate?.isRequired ?? false) {
      return;
    }
    _operationGeneration++;
    _clearFlow();
    _phase = DemoPhase.idle;
    _message = 'The optional update was deferred.';
    _notify();
  }

  void reset() {
    _operationGeneration++;
    _cancelToken?.cancel();
    _scenario = DemoScenario.defaults();
    _clearFlow();
    _phase = DemoPhase.idle;
    _notify();
  }

  void simulateOpenSettings() {
    _message = 'Settings recovery was simulated; no system setting changed.';
    _notify();
  }

  bool _isDownloadRelated(UpdateAction action) {
    return action is DownloadPackageAction ||
        action is DownloadAndInstallPackageAction ||
        action is OpenInstallerAction;
  }

  void _clearFlow() {
    _preparedUpdate = null;
    _errorCode = null;
    _message = null;
    _progress = null;
    _downloadedBytes = null;
    _totalBytes = null;
    _activeUpdater = null;
    _cancelToken = null;
  }

  bool _isCurrent(int generation) {
    return !_disposed && generation == _operationGeneration;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _operationGeneration++;
    _cancelToken?.cancel();
    super.dispose();
  }
}
