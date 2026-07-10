# Flutter App Updater Example

This app demonstrates the complete v3 flow without adding UI to the package:

1. select a static or remote manifest source
2. validate the manifest application identity
3. select the release and recommended action
4. display required/optional policy and structured failures
5. stream progress, support cancellation, and handle the terminal result

## Safe preview

The default mode uses a static manifest plus `PreviewUpdateExecutor`. It emits
real `UpdateActionEvent` objects but never opens a store, downloads a file, or
starts an installer. The `.invalid` artifact URL is intentionally unreachable;
successful preview execution proves that the simulated executor was used.

## Remote manifest

Remote mode requires a manifest URL, the exact application ID expected in that
manifest, and the installed version. It uses `defaultTargetPlatform` rather
than pretending every host is Android.

```dart
final updater = AppUpdater.manifest(
  manifestUrl: Uri.parse('https://updates.example.com/manifest.json'),
  expectedAppId: 'com.example.app',
  installedVersion: '1.0.0',
  platform: defaultTargetPlatform,
  channel: 'stable',
  downloadDirectory: downloadDirectory,
);
```

Use HTTPS and publish SHA-256 plus exact artifact sizes for commercial direct
downloads. Direct installation is appropriate only when the target platform
and distribution channel permit self-hosted updates. Google Play builds should
use store actions instead of requesting package-install permission.

## Run and verify

From the package root:

```bash
cd example
flutter pub get
flutter run
flutter analyze --no-pub
flutter test --no-pub
```

The integration test includes a safe `getPlatformVersion` call through the real
native method channel. Run it on a configured device or simulator:

```bash
flutter test integration_test/plugin_integration_test.dart
```

The example Android manifest opts into `REQUEST_INSTALL_PACKAGES` only because
remote mode can demonstrate policy-compliant self-hosted APK installation. The
plugin manifest itself does not impose this permission on consuming apps.
