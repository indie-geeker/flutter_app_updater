import 'dart:io';

import 'package:flutter/foundation.dart';

import '../actions/update_action.dart';
import '../download/package_downloader.dart';
import '../manifest/manifest_fetcher.dart';
import '../manifest/manifest_parser.dart';
import '../platform/android_market_executor.dart';
import '../models/update_candidate.dart';
import '../models/update_error_code.dart';
import '../platform/desktop_installer_executor.dart';
import '../platform/download_and_install_package_executor.dart';
import '../platform/download_package_executor.dart';
import '../platform/install_package_executor.dart';
import '../platform/streaming_update_action_executor.dart';
import '../platform/store_update_executor.dart';
import '../platform/update_action_cancel_token.dart';
import '../platform/update_action_executor.dart';
import '../platform/update_action_event.dart';
import '../utils/retry_strategy.dart';
import 'update_selector.dart';
import 'update_source.dart';

class AppUpdater {
  final UpdateSource source;
  final UpdateSelector? selector;
  final ManifestFetcher manifestFetcher;
  final List<UpdateActionExecutor>? executors;
  final String? downloadDirectory;
  final TargetPlatform? platform;
  final String? expectedAppId;
  final int maxDownloadBytes;
  final RetryStrategy downloadRetryStrategy;

  const AppUpdater({
    required this.source,
    this.selector,
    this.manifestFetcher = const IoManifestFetcher(),
    this.executors,
    this.downloadDirectory,
    this.platform,
    this.expectedAppId,
    this.maxDownloadBytes = PackageDownloader.defaultMaxDownloadBytes,
    this.downloadRetryStrategy = RetryStrategy.standard,
  });

  factory AppUpdater.manifest({
    required Uri manifestUrl,
    required String expectedAppId,
    Map<String, String>? headers,
    required String installedVersion,
    String? installedBuildNumber,
    required TargetPlatform platform,
    String? architecture,
    required String channel,
    String? downloadDirectory,
    ManifestFetcher manifestFetcher = const IoManifestFetcher(),
    List<UpdateActionExecutor>? executors,
    int maxDownloadBytes = PackageDownloader.defaultMaxDownloadBytes,
    RetryStrategy downloadRetryStrategy = RetryStrategy.standard,
  }) {
    return AppUpdater(
      source: UpdateSource.manifest(
        manifestUrl: manifestUrl,
        headers: headers,
      ),
      selector: UpdateSelector(
        installedVersion: installedVersion,
        installedBuildNumber: installedBuildNumber,
        platform: platform,
        architecture: architecture,
        channel: channel,
      ),
      manifestFetcher: manifestFetcher,
      executors: executors,
      downloadDirectory: downloadDirectory,
      platform: platform,
      expectedAppId: expectedAppId,
      maxDownloadBytes: maxDownloadBytes,
      downloadRetryStrategy: downloadRetryStrategy,
    );
  }

  Future<UpdateCheckResult> check({
    UpdateSelector? selector,
  }) async {
    final effectiveSelector = selector ?? this.selector;
    if (effectiveSelector == null) {
      return const UpdateCheckFailed(
        code: UpdateErrorCode.manifestInvalid,
        message: 'UpdateSelector is required before checking updates.',
      );
    }

    return switch (source) {
      StaticManifestUpdateSource(:final manifest) =>
        _selectManifest(manifest, effectiveSelector),
      ManifestUpdateSource manifestSource =>
        _checkRemoteManifest(manifestSource, effectiveSelector),
    };
  }

  Future<UpdateFlowResult> checkAndPrepare({
    UpdateSelector? selector,
  }) async {
    final result = await check(selector: selector);
    return switch (result) {
      UpdateAvailable(
        :final candidate,
        :final recommendedAction,
        :final isRequired,
      ) =>
        PreparedUpdateAvailable(
          candidate: candidate,
          recommendedAction: recommendedAction,
          actions: candidate.actions,
          isRequired: isRequired,
        ),
      UpdateNotAvailable() => const PreparedUpdateNotAvailable(),
      UpdateCheckFailed(:final code, :final message) =>
        PreparedUpdateCheckFailed(code: code, message: message),
    };
  }

  Future<UpdateCheckResult> _checkRemoteManifest(
    ManifestUpdateSource manifestSource,
    UpdateSelector effectiveSelector,
  ) async {
    try {
      final json = await manifestFetcher.fetch(manifestSource);
      final manifest = const ManifestParser().parse(json);
      return _selectManifest(manifest, effectiveSelector);
    } on FormatException catch (error) {
      return UpdateCheckFailed(
        code: UpdateErrorCode.manifestInvalid,
        message: error.message,
      );
    } on ManifestParseException catch (error) {
      return UpdateCheckFailed(
        code: error.code,
        message: error.message,
      );
    } on ManifestFetchException catch (error) {
      return UpdateCheckFailed(
        code: UpdateErrorCode.manifestFetchFailed,
        message: error.message,
      );
    } catch (error) {
      return UpdateCheckFailed(
        code: UpdateErrorCode.manifestFetchFailed,
        message: 'Failed to fetch update manifest: $error',
      );
    }
  }

  UpdateCheckResult _selectManifest(
    UpdateManifest manifest,
    UpdateSelector effectiveSelector,
  ) {
    final configuredAppId = expectedAppId;
    final requiredAppId = configuredAppId?.trim();
    if (configuredAppId != null && requiredAppId!.isEmpty) {
      return const UpdateCheckFailed(
        code: UpdateErrorCode.manifestInvalid,
        message: 'expectedAppId must not be blank.',
      );
    }
    if (requiredAppId != null && manifest.appId != requiredAppId) {
      return UpdateCheckFailed(
        code: UpdateErrorCode.appIdMismatch,
        message: 'Manifest appId ${manifest.appId} does not match '
            'expected appId $requiredAppId.',
      );
    }
    return effectiveSelector.select(manifest.releases);
  }

  Future<UpdateActionResult> perform(UpdateAction action) async {
    await for (final event in performStream(action)) {
      if (event case UpdateActionCompleted(:final result)) {
        return result;
      }
    }
    return const UpdateActionResult.failure(
      code: UpdateErrorCode.actionFailed,
      message: 'Update action ended without a result.',
    );
  }

  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) async* {
    for (final executor in executors ?? _defaultExecutors()) {
      if (!executor.supports(action)) {
        continue;
      }
      yield UpdateActionStarted(action);
      try {
        if (executor is StreamingUpdateActionExecutor) {
          await for (final event in executor.performStream(
            action,
            cancelToken: cancelToken,
          )) {
            switch (event) {
              case UpdateActionStarted():
                break;
              case UpdateActionProgress():
                yield event;
              case UpdateActionCompleted():
                yield event;
                return;
            }
          }
          yield const UpdateActionCompleted(
            UpdateActionResult.failure(
              code: UpdateErrorCode.actionFailed,
              message: 'Update action ended without a terminal result.',
            ),
          );
          return;
        }

        final result = await executor.perform(action);
        yield UpdateActionCompleted(result);
      } catch (error) {
        yield UpdateActionCompleted(
          UpdateActionResult.failure(
            code: UpdateErrorCode.actionFailed,
            message: 'Update action failed: $error',
          ),
        );
      }
      return;
    }

    yield UpdateActionStarted(action);
    yield const UpdateActionCompleted(
      UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'No executor supports this update action.',
      ),
    );
  }

  Future<UpdateActionResult> performRecommended(
    PreparedUpdateAvailable update,
  ) {
    return perform(update.recommendedAction);
  }

  Stream<UpdateActionEvent> performRecommendedStream(
    PreparedUpdateAvailable update, {
    UpdateActionCancelToken? cancelToken,
  }) {
    return performStream(
      update.recommendedAction,
      cancelToken: cancelToken,
    );
  }

  List<UpdateActionExecutor> _defaultExecutors() {
    final effectiveDownloadDirectory =
        downloadDirectory ?? Directory.systemTemp.path;
    final effectivePlatform =
        platform ?? selector?.platform ?? defaultTargetPlatform;
    final downloader = PackageDownloader(
      maxDownloadBytes: maxDownloadBytes,
      retryStrategy: downloadRetryStrategy,
    );
    return [
      StoreUpdateExecutor(),
      AndroidMarketExecutor(),
      DownloadPackageExecutor(
        downloadDirectory: effectiveDownloadDirectory,
        downloader: downloader,
      ),
      InstallPackageExecutor(),
      DownloadAndInstallPackageExecutor(
        downloadDirectory: effectiveDownloadDirectory,
        downloader: downloader,
      ),
      DesktopInstallerExecutor(
        platform: effectivePlatform,
        downloader: downloader,
        downloadDirectory: Directory(effectiveDownloadDirectory),
      ),
    ];
  }
}

sealed class UpdateFlowResult {
  const UpdateFlowResult();
}

class PreparedUpdateAvailable extends UpdateFlowResult {
  final UpdateCandidate candidate;
  final UpdateAction recommendedAction;
  final List<UpdateAction> actions;
  final bool isRequired;

  const PreparedUpdateAvailable({
    required this.candidate,
    required this.recommendedAction,
    required this.actions,
    required this.isRequired,
  });
}

class PreparedUpdateNotAvailable extends UpdateFlowResult {
  const PreparedUpdateNotAvailable();
}

class PreparedUpdateCheckFailed extends UpdateFlowResult {
  final UpdateErrorCode code;
  final String message;

  const PreparedUpdateCheckFailed({
    required this.code,
    required this.message,
  });
}
