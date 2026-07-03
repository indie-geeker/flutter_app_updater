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
    source: UpdateSource.manifest(manifestUrl: _manifestUrl),
    selector: const UpdateSelector(
      installedVersion: '1.0.0',
      platform: TargetPlatform.android,
      architecture: 'arm64',
      channel: 'stable',
    ),
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
      DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 25600000,
        sha256: 'a' * 64,
      ),
    ],
  );

  String _status = 'Ready';
  UpdateCheckResult? _result;

  void _previewSelection() {
    const selector = UpdateSelector(
      installedVersion: '1.0.0',
      platform: TargetPlatform.android,
      architecture: 'arm64',
      channel: 'stable',
    );
    final result = selector.select([_previewCandidate]);

    setState(() {
      _result = result;
      _status = switch (result) {
        UpdateAvailable(:final candidate, :final recommendedAction) =>
          'Update ${candidate.version}: ${_labelFor(recommendedAction)}',
        UpdateNotAvailable() => 'Already current',
        UpdateCheckFailed(:final code) => 'Failed: ${code.value}',
      };
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
            Text('Manifest source: $_manifestUrl'),
            const SizedBox(height: 12),
            Text('Updater source: ${_updater.source.runtimeType}'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _previewSelection,
              child: const Text('Preview update actions'),
            ),
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
            if (_result case UpdateAvailable(:final recommendedAction)) ...[
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
      OpenInstallerAction(:final installerUrl, :final installerSizeBytes) =>
        '$installerUrl ${installerSizeBytes ?? ''} bytes',
    };
  }
}
