import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static final _manifestUrl = Uri.parse(
    'https://example.com/app-updates.json',
  );

  late final AppUpdater _updater = AppUpdater(
    source: UpdateSource.staticManifest(manifest: _previewManifest),
    selector: const UpdateSelector(
      installedVersion: '1.0.0',
      platform: TargetPlatform.android,
      architecture: 'arm64',
      channel: 'stable',
    ),
    downloadDirectory: Directory.systemTemp.path,
  );

  late final UpdateManifest _previewManifest = UpdateManifest(
    schemaVersion: 3,
    appId: 'com.example.app',
    channel: 'stable',
    releases: [_previewCandidate],
  );

  late final UpdateCandidate _previewCandidate = UpdateCandidate(
    version: '2.0.0',
    buildNumber: '42',
    channel: 'stable',
    platform: TargetPlatform.android,
    architecture: 'arm64',
    releaseNotes: 'Bug fixes and performance improvements',
    releasedAt: DateTime.utc(2026, 7, 3, 10),
    policy: const UpdatePolicy(level: UpdatePolicyLevel.recommended),
    actions: [
      DownloadAndInstallPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 25600000,
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
        fallbackUrl: Uri.parse('https://app.mi.com/details?id=com.example.app'),
      ),
    ],
  );

  String _status = 'Ready';
  UpdateFlowResult? _result;

  Future<void> _checkForUpdate() async {
    setState(() {
      _status = 'Checking for updates';
    });

    final result = await _updater.checkAndPrepare();

    setState(() {
      _result = result;
      _status = switch (result) {
        PreparedUpdateAvailable(:final candidate, :final recommendedAction) =>
          'Update ${candidate.version}: ${_labelFor(recommendedAction)}',
        PreparedUpdateNotAvailable() => 'Already current',
        PreparedUpdateCheckFailed(:final code) => 'Failed: ${code.value}',
      };
    });
  }

  Future<void> _performRecommendedAction() async {
    final result = _result;
    if (result is! PreparedUpdateAvailable) {
      return;
    }

    final recommendedAction = result.recommendedAction;
    setState(() {
      _status = 'Running ${_labelFor(recommendedAction)}';
    });

    final actionResult = await _updater.performRecommended(result);

    setState(() {
      _status = actionResult.isSuccess
          ? 'Action completed'
          : 'Action failed: ${actionResult.code?.value ?? actionResult.message}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter App Updater v3'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Remote manifest source: $_manifestUrl'),
            const SizedBox(height: 12),
            Text('Updater source: ${_updater.source.runtimeType}'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _checkForUpdate,
              child: const Text('Check for updates'),
            ),
            if (_result case PreparedUpdateAvailable()) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _performRecommendedAction,
                child: const Text('Perform recommended action'),
              ),
            ],
            const SizedBox(height: 12),
            Text(_status),
            const SizedBox(height: 24),
            const Text('Candidate actions'),
            const SizedBox(height: 8),
            for (final action in _previewCandidate.actions)
              ListTile(
                title: Text(_labelFor(action)),
                subtitle: Text(_descriptionFor(action)),
              ),
            if (_result
                case PreparedUpdateAvailable(:final recommendedAction)) ...[
              const Divider(),
              ListTile(
                title: const Text('Recommended action'),
                subtitle: Text(_descriptionFor(recommendedAction)),
              ),
            ],
          ],
        ),
      ),
    );
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
        '$targetPackageName ${fallbackUrl ?? ''}',
      DownloadPackageAction(:final packageUrl, :final packageSizeBytes) =>
        '$packageUrl ${packageSizeBytes ?? ''} bytes',
      InstallPackageAction(:final packagePath) => packagePath,
      DownloadAndInstallPackageAction(
        :final packageUrl,
        :final packageSizeBytes,
      ) =>
        '$packageUrl ${packageSizeBytes ?? ''} bytes',
      OpenInstallerAction(:final installerUrl, :final installerSizeBytes) =>
        '$installerUrl ${installerSizeBytes ?? ''} bytes',
    };
  }
}
