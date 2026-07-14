import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

import 'production_app_metadata.dart';
import 'production_update_configuration.dart';

enum ProductionPhase {
  disabled,
  idle,
  checking,
  updateAvailable,
  upToDate,
  failed,
  executing,
  succeeded,
}

abstract interface class ProductionUpdaterFactory {
  AppUpdater create({
    required ProductionUpdateConfiguration configuration,
    required ProductionAppMetadata metadata,
  });
}

/// Constructs the package's real signed-manifest update flow.
final class DefaultProductionUpdaterFactory
    implements ProductionUpdaterFactory {
  final ManifestFetcher manifestFetcher;
  final List<UpdateActionExecutor>? executors;
  final TargetPlatform? targetPlatform;

  const DefaultProductionUpdaterFactory({
    this.manifestFetcher = const IoManifestFetcher(),
    this.executors,
    this.targetPlatform,
  });

  @override
  AppUpdater create({
    required ProductionUpdateConfiguration configuration,
    required ProductionAppMetadata metadata,
  }) {
    final platform = targetPlatform ?? defaultTargetPlatform;
    return AppUpdater.manifest(
      manifestUrl: configuration.manifestUrl!,
      expectedAppId: configuration.expectedAppId,
      installedVersion: metadata.version,
      installedBuildNumber: metadata.buildNumber,
      platform: platform,
      architecture: configuration.architecture,
      channel: configuration.channel,
      downloadDirectory: metadata.downloadDirectory,
      manifestFetcher: manifestFetcher,
      executors: executors,
      distributionPolicy: configuration.distributionPolicy,
      signaturePolicy: ManifestSignaturePolicy.required(
        trustedPublicKeys: configuration.trustedPublicKeys,
      ),
    );
  }
}

/// Owns the production example's explicit check, consent, and action states.
final class ProductionUpdateController extends ChangeNotifier {
  final ProductionUpdateConfiguration configuration;
  final ProductionRuntimeLoader runtimeLoader;
  final ProductionUpdaterFactory updaterFactory;

  late ProductionPhase phase;
  PreparedUpdateAvailable? preparedUpdate;
  UpdateErrorCode? errorCode;
  String? message;
  AppUpdater? _updater;

  ProductionUpdateController({
    required this.configuration,
    required this.runtimeLoader,
    required this.updaterFactory,
  }) {
    phase =
        configuration.enabled ? ProductionPhase.idle : ProductionPhase.disabled;
  }

  bool get isBusy =>
      phase == ProductionPhase.checking || phase == ProductionPhase.executing;

  Future<void> checkForUpdate() async {
    if (!configuration.enabled) {
      phase = ProductionPhase.disabled;
      notifyListeners();
      return;
    }
    if (configuration.validationError case final validationError?) {
      _fail(UpdateErrorCode.configurationInvalid, validationError);
      return;
    }

    phase = ProductionPhase.checking;
    preparedUpdate = null;
    errorCode = null;
    message = null;
    _updater = null;
    notifyListeners();

    try {
      final metadata = await runtimeLoader.load();
      if (metadata.appId.trim() != configuration.expectedAppId) {
        _fail(
          UpdateErrorCode.configurationInvalid,
          'Configured app ID does not match the runtime package '
          '${metadata.appId}.',
        );
        return;
      }
      final updater = updaterFactory.create(
        configuration: configuration,
        metadata: metadata,
      );
      _updater = updater;
      final result = await updater.checkAndPrepare();
      switch (result) {
        case PreparedUpdateAvailable():
          preparedUpdate = result;
          phase = ProductionPhase.updateAvailable;
          message = 'Review the recommended action before execution.';
        case PreparedUpdateNotAvailable():
          phase = ProductionPhase.upToDate;
          message = 'The installed application is up to date.';
        case PreparedUpdateCheckFailed(:final code, :final message):
          _fail(code, message, notify: false);
      }
      notifyListeners();
    } catch (error) {
      _fail(
        UpdateErrorCode.configurationInvalid,
        'Unable to initialize production update boundaries: $error',
      );
    }
  }

  void declineRecommendedAction() {
    if (phase != ProductionPhase.updateAvailable) {
      return;
    }
    message = 'Update action was not executed.';
    notifyListeners();
  }

  Future<void> performRecommended() async {
    final updater = _updater;
    final update = preparedUpdate;
    if (phase != ProductionPhase.updateAvailable ||
        updater == null ||
        update == null) {
      return;
    }
    phase = ProductionPhase.executing;
    notifyListeners();
    try {
      final result = await updater.performRecommended(update);
      if (result.isSuccess) {
        phase = ProductionPhase.succeeded;
        errorCode = null;
        message = 'The recommended action completed successfully.';
      } else {
        _fail(
          result.code ?? UpdateErrorCode.actionFailed,
          result.message ?? 'Update action failed.',
          notify: false,
        );
      }
      notifyListeners();
    } catch (error) {
      _fail(
        UpdateErrorCode.actionFailed,
        'Update action failed: $error',
      );
    }
  }

  void _fail(
    UpdateErrorCode code,
    String failureMessage, {
    bool notify = true,
  }) {
    phase = ProductionPhase.failed;
    errorCode = code;
    message = failureMessage;
    if (notify) {
      notifyListeners();
    }
  }
}
