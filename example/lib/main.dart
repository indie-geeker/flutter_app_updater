import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

void main() {
  runApp(const MyApp());
}

enum DemoMode { preview, remote }

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _manifestUrlController = TextEditingController();
  final _expectedAppIdController = TextEditingController();
  final _installedVersionController = TextEditingController(text: '1.0.0');

  late final UpdateCandidate _previewCandidate = UpdateCandidate(
    version: '2.0.0',
    buildNumber: '42',
    channel: 'stable',
    platform: defaultTargetPlatform,
    releaseNotes: 'Demonstrates required policy, progress, and cancellation.',
    releasedAt: DateTime.utc(2026, 7, 3, 10),
    policy: const UpdatePolicy(level: UpdatePolicyLevel.required),
    actions: [
      DownloadAndInstallPackageAction(
        packageUrl: Uri.parse('https://downloads.example.invalid/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 100,
      ),
      OpenStoreAction(
        store: StoreKind.googlePlay,
        storeUrl: Uri.parse(
          'https://play.google.com/store/apps/details?id=com.example.app',
        ),
      ),
      OpenAndroidMarketAction(
        market: AndroidMarketKind.xiaomi,
        targetPackageName: 'com.example.app',
        fallbackUrl: Uri.parse(
          'https://app.mi.com/details?id=com.example.app',
        ),
      ),
    ],
  );

  late final AppUpdater _previewUpdater = AppUpdater(
    source: UpdateSource.staticManifest(
      manifest: UpdateManifest(
        schemaVersion: 3,
        appId: 'com.example.app',
        channel: 'stable',
        releases: [_previewCandidate],
      ),
    ),
    expectedAppId: 'com.example.app',
    selector: UpdateSelector(
      installedVersion: '1.0.0',
      platform: defaultTargetPlatform,
      channel: 'stable',
    ),
    executors: [const PreviewUpdateExecutor()],
  );

  DemoMode _mode = DemoMode.preview;
  String _status = 'Ready';
  UpdateFlowResult? _result;
  AppUpdater? _activeUpdater;
  UpdateActionCancelToken? _cancelToken;
  double? _progress;
  bool _isRunning = false;
  bool _directInstallAcknowledged = false;

  @override
  void dispose() {
    _cancelToken?.cancel();
    _manifestUrlController.dispose();
    _expectedAppIdController.dispose();
    _installedVersionController.dispose();
    super.dispose();
  }

  void _selectMode(DemoMode mode) {
    setState(() {
      _mode = mode;
      _status = 'Ready';
      _result = null;
      _activeUpdater = null;
      _progress = null;
      _directInstallAcknowledged = false;
    });
  }

  Future<void> _checkForUpdate() async {
    final updater =
        _mode == DemoMode.preview ? _previewUpdater : _remoteUpdater();
    if (updater == null) {
      return;
    }

    setState(() {
      _status = 'Checking for updates';
      _result = null;
      _activeUpdater = updater;
      _progress = null;
    });

    final result = await updater.checkAndPrepare();
    if (!mounted) {
      return;
    }
    setState(() {
      _result = result;
      _status = switch (result) {
        PreparedUpdateAvailable(:final candidate) =>
          'Update ${candidate.version} is available',
        PreparedUpdateNotAvailable() => 'Already current',
        PreparedUpdateCheckFailed(:final code, :final message) =>
          'Failed: ${code.value} — $message',
      };
    });
  }

  AppUpdater? _remoteUpdater() {
    final manifestUrl = Uri.tryParse(_manifestUrlController.text.trim());
    final expectedAppId = _expectedAppIdController.text.trim();
    final installedVersion = _installedVersionController.text.trim();
    if (manifestUrl == null ||
        (manifestUrl.scheme != 'https' && manifestUrl.scheme != 'http') ||
        !manifestUrl.hasAuthority ||
        expectedAppId.isEmpty ||
        installedVersion.isEmpty) {
      setState(() {
        _status = 'Configuration error: enter an HTTP(S) manifest URL, '
            'expected app ID, and installed version.';
      });
      return null;
    }

    return AppUpdater.manifest(
      manifestUrl: manifestUrl,
      expectedAppId: expectedAppId,
      installedVersion: installedVersion,
      platform: defaultTargetPlatform,
      channel: 'stable',
      downloadDirectory: Directory.systemTemp.path,
    );
  }

  Future<void> _performRecommendedAction() async {
    final result = _result;
    final updater = _activeUpdater;
    if (result is! PreparedUpdateAvailable || updater == null) {
      return;
    }

    final cancelToken = UpdateActionCancelToken();
    setState(() {
      _cancelToken = cancelToken;
      _isRunning = true;
      _progress = null;
      _status = 'Running ${_labelFor(result.recommendedAction)}';
    });

    await for (final event in updater.performRecommendedStream(
      result,
      cancelToken: cancelToken,
    )) {
      if (!mounted) {
        return;
      }
      switch (event) {
        case UpdateActionStarted():
          break;
        case UpdateActionProgress(:final fraction):
          setState(() {
            _progress = fraction;
            _status = fraction == null
                ? 'Downloading update'
                : 'Downloading ${(fraction * 100).round()}%';
          });
        case UpdateActionCompleted(:final result):
          setState(() {
            _isRunning = false;
            _cancelToken = null;
            _progress = null;
            _status = result.code == UpdateErrorCode.actionCanceled
                ? 'Canceled: ${result.code!.value}'
                : result.isSuccess
                    ? _mode == DemoMode.preview
                        ? 'Preview completed safely'
                        : 'Action completed'
                    : 'Failed: ${result.code?.value ?? 'UNKNOWN'} — '
                        '${result.message ?? 'No details'}';
          });
      }
    }
  }

  void _cancelAction() {
    _cancelToken?.cancel();
    setState(() {
      _status = 'Cancel requested';
    });
  }

  @override
  Widget build(BuildContext context) {
    final available = _result is PreparedUpdateAvailable
        ? _result! as PreparedUpdateAvailable
        : null;
    final recommendedAction = available?.recommendedAction;
    final requiresAcknowledgement = _mode == DemoMode.remote &&
        recommendedAction != null &&
        _isDirectArtifactAction(recommendedAction);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Flutter App Updater v3')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ToggleButtons(
              isSelected: [
                _mode == DemoMode.preview,
                _mode == DemoMode.remote,
              ],
              onPressed: _isRunning
                  ? null
                  : (index) => _selectMode(DemoMode.values[index]),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Safe preview'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Remote manifest'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_mode == DemoMode.preview)
              const _NoticeCard(
                icon: Icons.shield_outlined,
                text: 'Preview mode never downloads or installs anything. '
                    'A simulated executor demonstrates the complete flow.',
              )
            else ...[
              TextField(
                key: const Key('manifest-url-field'),
                controller: _manifestUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Manifest URL',
                  hintText: 'https://updates.example.com/manifest.json',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('expected-app-id-field'),
                controller: _expectedAppIdController,
                decoration: const InputDecoration(
                  labelText: 'Expected app ID',
                  hintText: 'com.example.app',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('installed-version-field'),
                controller: _installedVersionController,
                decoration: const InputDecoration(
                  labelText: 'Installed version',
                ),
              ),
              const SizedBox(height: 12),
              const _NoticeCard(
                icon: Icons.warning_amber_rounded,
                text: 'Direct install requires an HTTPS artifact, explicit '
                    'user consent, and a distribution channel whose policy '
                    'permits self-hosted updates.',
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isRunning ? null : _checkForUpdate,
              icon: const Icon(Icons.system_update_alt),
              label: const Text('Check for updates'),
            ),
            const SizedBox(height: 12),
            Text(
              _status,
              key: const Key('status-text'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_isRunning) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _cancelAction,
                child: const Text('Cancel action'),
              ),
            ],
            if (available != null) ...[
              const SizedBox(height: 20),
              Text(
                'Policy: ${available.isRequired ? 'Required' : 'Optional'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(available.candidate.releaseNotes),
              const SizedBox(height: 12),
              Text(
                'Recommended: ${_labelFor(available.recommendedAction)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (requiresAcknowledgement)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _directInstallAcknowledged,
                  onChanged: _isRunning
                      ? null
                      : (value) => setState(() {
                            _directInstallAcknowledged = value ?? false;
                          }),
                  title: const Text(
                    'I understand the platform and distribution requirements',
                  ),
                ),
              FilledButton(
                onPressed: _isRunning ||
                        (requiresAcknowledgement && !_directInstallAcknowledged)
                    ? null
                    : _performRecommendedAction,
                child: Text(
                  _mode == DemoMode.preview
                      ? 'Run simulated action'
                      : 'Perform recommended action',
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Candidate actions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final action in available.actions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_labelFor(action)),
                  subtitle: Text(_descriptionFor(action)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isDirectArtifactAction(UpdateAction action) {
    return action is DownloadPackageAction ||
        action is InstallPackageAction ||
        action is DownloadAndInstallPackageAction ||
        action is OpenInstallerAction;
  }

  String _labelFor(UpdateAction action) {
    return switch (action) {
      OpenStoreAction(:final store) => 'Open ${store.name}',
      PlayInAppUpdateAction(:final mode) => 'Play in-app ${mode.name}',
      OpenAndroidMarketAction(:final market) => 'Open ${market.name}',
      DownloadPackageAction(:final packageType) =>
        'Download ${packageType.name}',
      InstallPackageAction(:final packageType) => 'Install ${packageType.name}',
      DownloadAndInstallPackageAction(:final packageType) =>
        'Download and install ${packageType.name}',
      OpenInstallerAction(:final installerType) =>
        'Open ${installerType.name} installer',
    };
  }

  String _descriptionFor(UpdateAction action) {
    return switch (action) {
      OpenStoreAction(:final storeUrl) => storeUrl.toString(),
      PlayInAppUpdateAction(:final mode) => 'Mode: ${mode.name}',
      OpenAndroidMarketAction(:final targetPackageName, :final fallbackUrl) =>
        '$targetPackageName${fallbackUrl == null ? '' : ' — $fallbackUrl'}',
      DownloadPackageAction(:final packageUrl, :final packageSizeBytes) =>
        '$packageUrl${_sizeLabel(packageSizeBytes)}',
      InstallPackageAction(:final packagePath) => packagePath,
      DownloadAndInstallPackageAction(
        :final packageUrl,
        :final packageSizeBytes,
      ) =>
        '$packageUrl${_sizeLabel(packageSizeBytes)}',
      OpenInstallerAction(:final installerUrl, :final installerSizeBytes) =>
        '$installerUrl${_sizeLabel(installerSizeBytes)}',
    };
  }

  String _sizeLabel(int? size) => size == null ? '' : ' — $size bytes';
}

class PreviewUpdateExecutor implements StreamingUpdateActionExecutor {
  const PreviewUpdateExecutor();

  @override
  bool supports(UpdateAction action) => true;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    return const UpdateActionResult.success();
  }

  @override
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) async* {
    yield UpdateActionStarted(action);
    for (final downloadedBytes in const [25, 50, 75, 100]) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (cancelToken?.isCanceled ?? false) {
        yield const UpdateActionCompleted(
          UpdateActionResult.failure(
            code: UpdateErrorCode.actionCanceled,
            message: 'Preview action canceled.',
          ),
        );
        return;
      }
      yield UpdateActionProgress(
        action: action,
        downloadedBytes: downloadedBytes,
        totalBytes: 100,
      );
    }
    yield const UpdateActionCompleted(UpdateActionResult.success());
  }
}

class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _NoticeCard({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
