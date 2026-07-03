# Flutter App Updater v3 Commercial Quality Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Raise `flutter_app_updater` to a 9/10+ commercial-quality foundation library for the approved stable scope.

**Architecture:** Keep the UI-free v3 model, but make the default path simple enough for independent developers. Add explicit install and download-then-install actions, make hash verification optional, align default executors with the documented platform promise, and make docs/CI/release hygiene enforce the same standard.

**Tech Stack:** Dart 3 sealed classes, Flutter plugin method channels, `dart:io` streaming downloads, existing native Android/iOS/macOS/Windows plugin methods, Flutter unit/widget tests, GitHub Actions.

---

## Constraints

- Stable scope: Android store/market/APK download/install, iOS App Store, macOS/Windows installer download/open.
- Planned only: Play In-App Updates, OHOS, Linux.
- Keep core package UI-free.
- Breaking v3 API changes are allowed.
- Do not require HTTPS.
- Do not require SHA-256.
- Do not promise signature verification unless implemented.
- Use TDD for behavior changes.
- Do not stage the pre-existing untracked `doc/plans/2026-07-03-v3-quality-hardening-implementation.md` unless the user explicitly asks.

## Verification Gate

Run before claiming completion:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
dart doc --dry-run
flutter pub publish --dry-run
flutter analyze example
(cd example && flutter test)
(cd example && flutter build apk --debug)
```

Also inspect `flutter pub publish --dry-run` output to confirm the archive excludes `doc/plans/` and `docs/plans/`.

---

### Task 1: Make SHA-256 Optional in Manifest and Action Models

**Files:**
- Modify: `lib/src/actions/update_action.dart`
- Modify: `lib/src/manifest/manifest_schema.dart`
- Modify: `lib/src/manifest/manifest_parser.dart`
- Modify: `lib/src/platform/desktop_installer_executor.dart`
- Modify: `lib/src/platform/download_package_executor.dart`
- Test: `test/unit/v3/manifest_validator_test.dart`
- Test: `test/unit/v3/manifest_parser_test.dart`
- Test: `test/unit/v3/update_action_test.dart`

**Step 1: Write failing tests**

Add tests:

```dart
test('allows package actions without sha256', () {
  final manifest = validManifestWithAction({
    'type': 'downloadPackage',
    'packageUrl': 'https://example.com/app.apk',
    'packageType': 'apk',
  });

  expect(() => const ManifestValidator().validate(manifest), returnsNormally);
});

test('allows installer actions without sha256', () {
  final manifest = validManifestWithAction({
    'type': 'openInstaller',
    'installerUrl': 'https://example.com/app.msi',
    'installerType': 'msi',
  });

  expect(() => const ManifestValidator().validate(manifest), returnsNormally);
});

test('parses optional package and installer hashes', () {
  final manifest = const ManifestParser().parse(validManifest);

  final package = manifest.releases.single.actions
      .whereType<DownloadPackageAction>()
      .single;
  final installer = manifest.releases.single.actions
      .whereType<OpenInstallerAction>()
      .single;

  expect(package.sha256, isNull);
  expect(installer.sha256, isNull);
});
```

Update `update_action_test.dart` to verify `sha256` can be omitted and no public `signature` field is required.

**Step 2: Verify red**

Run:

```bash
flutter test test/unit/v3/manifest_validator_test.dart test/unit/v3/manifest_parser_test.dart test/unit/v3/update_action_test.dart
```

Expected: FAIL because `sha256` is currently required and action constructors require non-null strings.

**Step 3: Implement minimal model/schema change**

Change:

```dart
class DownloadPackageAction extends UpdateAction {
  final String? sha256;

  const DownloadPackageAction({
    required this.packageUrl,
    required this.packageType,
    this.packageSizeBytes,
    this.sha256,
  });
}
```

Change `OpenInstallerAction` similarly.

Remove `signature` from public action constructors unless a later task implements it.

In `ManifestSchema`, remove required `sha256` checks for `downloadPackage` and `openInstaller`.

In `ManifestParser`, parse `sha256` with `_optionalString()`.

Update any code that assumes `action.sha256` is non-null.

**Step 4: Verify green**

Run:

```bash
flutter test test/unit/v3/manifest_validator_test.dart test/unit/v3/manifest_parser_test.dart test/unit/v3/update_action_test.dart
```

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/src/actions/update_action.dart lib/src/manifest/manifest_schema.dart lib/src/manifest/manifest_parser.dart lib/src/platform/desktop_installer_executor.dart lib/src/platform/download_package_executor.dart test/unit/v3/manifest_validator_test.dart test/unit/v3/manifest_parser_test.dart test/unit/v3/update_action_test.dart
git commit -m "feat: allow updater actions without hashes"
```

---

### Task 2: Make Package Download Hash Verification Conditional

**Files:**
- Modify: `lib/src/download/package_downloader.dart`
- Modify: `lib/src/download/package_download_result.dart`
- Test: `test/unit/v3/package_downloader_test.dart`
- Test: `test/unit/v3/download_package_executor_test.dart`

**Step 1: Write failing tests**

Add tests:

```dart
test('downloads packages without sha256', () async {
  final bytes = utf8.encode('package bytes');
  final result = await PackageDownloader(client: client).download(
    action: DownloadPackageAction(
      packageUrl: Uri.parse('https://example.com/app.apk'),
      packageType: PackageType.apk,
    ),
    savePath: '${tempDir.path}/app.apk',
  );

  expect(result.isSuccess, isTrue);
  expect(await result.file!.readAsBytes(), bytes);
  expect(result.sha256, isNull);
});

test('checks hash mismatch only when sha256 is provided', () async {
  final result = await PackageDownloader(client: client).download(
    action: DownloadPackageAction(
      packageUrl: Uri.parse('https://example.com/app.apk'),
      packageType: PackageType.apk,
      sha256: 'a' * 64,
    ),
    savePath: '${tempDir.path}/app.apk',
  );

  expect(result.code, UpdateErrorCode.packageHashMismatch);
});
```

**Step 2: Verify red**

Run:

```bash
flutter test test/unit/v3/package_downloader_test.dart test/unit/v3/download_package_executor_test.dart
```

Expected: FAIL because downloader currently rejects empty hash and assumes non-null hash for fallback filenames.

**Step 3: Implement conditional hash verification**

Add helper:

```dart
String? _normalizedSha256(String? value) {
  final trimmed = value?.trim().toLowerCase();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
```

Only calculate and compare file hash when normalized hash is not null.

When hash is absent, return `PackageDownloadResult.success(file: ..., downloadedBytes: ..., sha256: null)`.

For fallback filenames without a hash, derive a safe deterministic name from the URL basename, or use `package.${action.packageType.name}` when no safe basename exists.

**Step 4: Verify green**

Run:

```bash
flutter test test/unit/v3/package_downloader_test.dart test/unit/v3/download_package_executor_test.dart
```

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/src/download/package_downloader.dart lib/src/download/package_download_result.dart test/unit/v3/package_downloader_test.dart test/unit/v3/download_package_executor_test.dart
git commit -m "feat: verify package hashes only when provided"
```

---

### Task 3: Add Explicit Package Install and Download-Then-Install Actions

**Files:**
- Modify: `lib/src/actions/update_action.dart`
- Modify: `lib/src/models/update_error_code.dart`
- Modify: `lib/src/channel/flutter_app_updater_platform_interface.dart`
- Modify: `lib/src/channel/flutter_app_updater_method_channel.dart`
- Create: `lib/src/platform/install_package_executor.dart`
- Create: `lib/src/platform/download_and_install_package_executor.dart`
- Modify: `lib/flutter_app_updater.dart`
- Test: `test/unit/v3/package_install_executor_test.dart`
- Test: `test/unit/v3/download_and_install_package_executor_test.dart`

**Step 1: Write failing tests**

Add tests for `InstallPackageExecutor`:

```dart
test('installs an existing package through the platform channel', () async {
  final platform = _FakeInstallPlatform();
  final action = InstallPackageAction(
    packagePath: '/tmp/app.apk',
    packageType: PackageType.apk,
  );

  final result = await InstallPackageExecutor(platform: platform)
      .perform(action);

  expect(result.isSuccess, isTrue);
  expect(platform.installedPaths, ['/tmp/app.apk']);
});

test('maps install permission failures', () async {
  final platform = _FailingInstallPlatform('INSTALL_PERMISSION_REQUIRED');

  final result = await InstallPackageExecutor(platform: platform)
      .perform(InstallPackageAction(packagePath: '/tmp/app.apk'));

  expect(result.code, UpdateErrorCode.packageInstallPermissionRequired);
});
```

Add tests for `DownloadAndInstallPackageExecutor`:

```dart
test('downloads and installs package actions', () async {
  final result = await DownloadAndInstallPackageExecutor(
    downloadDirectory: tempDir.path,
    downloader: fakeDownloader,
    installer: fakeInstaller,
  ).perform(action);

  expect(result.isSuccess, isTrue);
  expect(fakeInstaller.installedPaths.single, endsWith('app.apk'));
});

test('does not install when download fails', () async {
  final result = await executor.perform(actionReturningDownloadFailure);

  expect(result.code, UpdateErrorCode.packageDownloadFailed);
  expect(fakeInstaller.installedPaths, isEmpty);
});
```

**Step 2: Verify red**

Run:

```bash
flutter test test/unit/v3/package_install_executor_test.dart test/unit/v3/download_and_install_package_executor_test.dart
```

Expected: FAIL because action and executors do not exist.

**Step 3: Implement actions and executors**

Add actions:

```dart
class InstallPackageAction extends UpdateAction {
  final String packagePath;
  final PackageType packageType;

  const InstallPackageAction({
    required this.packagePath,
    this.packageType = PackageType.apk,
  });
}

class DownloadAndInstallPackageAction extends UpdateAction {
  final Uri packageUrl;
  final PackageType packageType;
  final int? packageSizeBytes;
  final String? sha256;

  const DownloadAndInstallPackageAction({
    required this.packageUrl,
    required this.packageType,
    this.packageSizeBytes,
    this.sha256,
  });
}
```

Add error codes:

- `packageInstallPermissionRequired`
- `packageFileNotFound`
- `packageInstallFailed`

`InstallPackageExecutor` calls `FlutterAppUpdaterPlatform.installApp(path: action.packagePath)` and maps platform error codes.

`DownloadAndInstallPackageExecutor` downloads with `PackageDownloader`, then passes the resulting file path to `InstallPackageExecutor`.

Export both executors from the public barrel.

**Step 4: Verify green**

Run:

```bash
flutter test test/unit/v3/package_install_executor_test.dart test/unit/v3/download_and_install_package_executor_test.dart
```

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/src/actions/update_action.dart lib/src/models/update_error_code.dart lib/src/channel lib/src/platform/install_package_executor.dart lib/src/platform/download_and_install_package_executor.dart lib/flutter_app_updater.dart test/unit/v3/package_install_executor_test.dart test/unit/v3/download_and_install_package_executor_test.dart
git commit -m "feat: add package install update actions"
```

---

### Task 4: Parse New Actions and Update Selection Recommendations

**Files:**
- Modify: `lib/src/manifest/manifest_schema.dart`
- Modify: `lib/src/manifest/manifest_parser.dart`
- Modify: `lib/src/core/update_selector.dart`
- Modify: `lib/src/cli/manifest_command.dart`
- Test: `test/unit/v3/manifest_validator_test.dart`
- Test: `test/unit/v3/manifest_parser_test.dart`
- Test: `test/unit/v3/update_selector_test.dart`
- Test: `test/unit/v3/cli_manifest_test.dart`

**Step 1: Write failing tests**

Add schema/parser tests for:

- `installPackage`
- `downloadAndInstallPackage`
- `downloadAndInstallPackage` with no `sha256`
- CLI verify accepts new action shape

Add selector tests:

```dart
test('required Android updates prefer download and install actions', () {
  final result = const UpdateSelector(
    installedVersion: '1.0.0',
    platform: TargetPlatform.android,
    channel: 'stable',
  ).select([
    candidate(
      version: '2.0.0',
      policyLevel: UpdatePolicyLevel.required,
      actions: [
        openStoreAction,
        downloadAndInstallAction,
      ],
    ),
  ]);

  expect((result as UpdateAvailable).recommendedAction,
      isA<DownloadAndInstallPackageAction>());
});

test('minSupportedVersion makes an update required when installed version is below minimum', () {
  final result = selector(installedVersion: '1.4.0').select([
    candidate(
      version: '2.0.0',
      policy: const UpdatePolicy(
        level: UpdatePolicyLevel.recommended,
        minSupportedVersion: '1.5.0',
      ),
    ),
  ]);

  expect((result as UpdateAvailable).isRequired, isTrue);
});
```

**Step 2: Verify red**

Run:

```bash
flutter test test/unit/v3/manifest_validator_test.dart test/unit/v3/manifest_parser_test.dart test/unit/v3/update_selector_test.dart test/unit/v3/cli_manifest_test.dart
```

Expected: FAIL because schema/parser/selector do not support the new actions and required state.

**Step 3: Implement parser, schema, CLI, and selection behavior**

Add action schema cases:

- `installPackage` requires `packagePath`
- `downloadAndInstallPackage` requires `packageUrl` and `packageType`, optional `packageSizeBytes` and `sha256`

Parse the new actions in `ManifestParser`.

Update `ManifestCommand.generate()` to use the recommended `downloadAndInstallPackage` example.

Add `bool isRequired` to `UpdateAvailable`.

Selection rules:

- `policy.level == required` => required.
- `minSupportedVersion != null && installedVersion < minSupportedVersion` => required.
- For required updates, prefer `DownloadAndInstallPackageAction`, then `DownloadPackageAction`, then `OpenInstallerAction`, then first action.
- For optional/recommended updates, use first action unless future docs specify otherwise.

**Step 4: Verify green**

Run:

```bash
flutter test test/unit/v3/manifest_validator_test.dart test/unit/v3/manifest_parser_test.dart test/unit/v3/update_selector_test.dart test/unit/v3/cli_manifest_test.dart
```

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/src/manifest lib/src/core/update_selector.dart lib/src/cli/manifest_command.dart test/unit/v3/manifest_validator_test.dart test/unit/v3/manifest_parser_test.dart test/unit/v3/update_selector_test.dart test/unit/v3/cli_manifest_test.dart
git commit -m "feat: parse install actions in v3 manifests"
```

---

### Task 5: Add Default Commercial Executors and Convenience Flow API

**Files:**
- Modify: `lib/src/core/app_updater.dart`
- Modify: `lib/src/core/update_selector.dart`
- Modify: `lib/flutter_app_updater.dart`
- Test: `test/unit/v3/app_updater_perform_test.dart`
- Test: `test/unit/v3/app_updater_flow_test.dart`
- Test: `test/unit/v3/public_api_test.dart`

**Step 1: Write failing tests**

Add tests:

```dart
test('default executors support stable commercial actions', () async {
  final updater = AppUpdater(
    source: UpdateSource.staticManifest(manifest: manifest),
    selector: selector,
    downloadDirectory: tempDir.path,
  );

  expect(await updater.perform(openStoreAction), isSuccess);
  expect(await updater.perform(openAndroidMarketAction), isSuccess);
  expect(await updater.perform(downloadPackageAction), isSuccess);
  expect(await updater.perform(installPackageAction), isSuccess);
  expect(await updater.perform(downloadAndInstallPackageAction), isSuccess);
});

test('manifest factory builds a checkable updater with default stable executors', () async {
  final updater = AppUpdater.manifest(
    manifestUrl: Uri.parse('https://example.com/update.json'),
    installedVersion: '1.0.0',
    platform: TargetPlatform.android,
    channel: 'stable',
    downloadDirectory: tempDir.path,
    manifestFetcher: fakeFetcher,
  );

  final result = await updater.checkAndPrepare();

  expect(result, isA<PreparedUpdateAvailable>());
  expect((result as PreparedUpdateAvailable).actions, isNotEmpty);
});
```

Use fake platform/executors where native channels would otherwise be required.

**Step 2: Verify red**

Run:

```bash
flutter test test/unit/v3/app_updater_perform_test.dart test/unit/v3/app_updater_flow_test.dart test/unit/v3/public_api_test.dart
```

Expected: FAIL because factory/flow types/default executors do not exist or do not include all stable actions.

**Step 3: Implement convenience API**

Add optional constructor fields to `AppUpdater`:

- `String? downloadDirectory`
- `TargetPlatform? platform`
- `FlutterAppUpdaterPlatform? platformChannel` if needed for testable defaults

Add factory:

```dart
factory AppUpdater.manifest({
  required Uri manifestUrl,
  Map<String, String>? headers,
  required String installedVersion,
  String? installedBuildNumber,
  required TargetPlatform platform,
  String? architecture,
  required String channel,
  String? downloadDirectory,
  ManifestFetcher manifestFetcher = const IoManifestFetcher(),
  List<UpdateActionExecutor>? executors,
})
```

Add flow result classes:

- `UpdateFlowResult`
- `PreparedUpdateAvailable`
- `PreparedUpdateNotAvailable`
- `PreparedUpdateCheckFailed`

Add:

```dart
Future<UpdateFlowResult> checkAndPrepare({UpdateSelector? selector});
Future<UpdateActionResult> performRecommended(PreparedUpdateAvailable update);
```

Default executors should include the stable promise. Use `downloadDirectory ?? Directory.systemTemp.path`.

**Step 4: Verify green**

Run:

```bash
flutter test test/unit/v3/app_updater_perform_test.dart test/unit/v3/app_updater_flow_test.dart test/unit/v3/public_api_test.dart
```

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/src/core/app_updater.dart lib/src/core/update_selector.dart lib/flutter_app_updater.dart test/unit/v3/app_updater_perform_test.dart test/unit/v3/app_updater_flow_test.dart test/unit/v3/public_api_test.dart
git commit -m "feat: add default commercial update flow"
```

---

### Task 6: Rewrite Example, README, and Public Release Surface

**Files:**
- Modify: `README.md`
- Modify: `example/README.md`
- Modify: `example/lib/main.dart`
- Modify: `example/test/widget_test.dart`
- Modify: `CHANGELOG.md`
- Create: `.pubignore`
- Test: `test/unit/v3/public_api_test.dart`
- Test: `example/test/widget_test.dart`

**Step 1: Write failing tests**

Update public API/readme tests to assert:

- README quick start uses `AppUpdater.manifest`.
- README includes `checkAndPrepare`.
- README includes `downloadAndInstallPackage`.
- README platform matrix marks OHOS/Linux/Play In-App Updates as planned or unsupported.
- README does not claim mandatory SHA-256.
- README does not mention public `signature` support.
- `.pubignore` excludes `doc/plans/` and `docs/plans/`.

Update example widget test:

```dart
testWidgets('shows v3 update flow controls', (tester) async {
  await tester.pumpWidget(const MyApp());

  expect(find.text('Flutter App Updater v3'), findsOneWidget);
  expect(find.text('Check for updates'), findsOneWidget);

  await tester.tap(find.text('Check for updates'));
  await tester.pumpAndSettle();

  expect(find.textContaining('Update 2.0.0'), findsOneWidget);
  expect(find.text('Perform recommended action'), findsOneWidget);
});
```

**Step 2: Verify red**

Run:

```bash
flutter test test/unit/v3/public_api_test.dart
(cd example && flutter test)
```

Expected: FAIL because docs and example still use old copy or failing template assertions.

**Step 3: Rewrite docs and example**

README first screen should be copyable:

```dart
final updater = AppUpdater.manifest(
  manifestUrl: Uri.parse('https://example.com/app-updates.json'),
  installedVersion: '1.0.0',
  platform: defaultTargetPlatform,
  channel: 'stable',
  downloadDirectory: downloadDirectory,
);

final result = await updater.checkAndPrepare();
```

Add recipes for:

- official store
- Chinese Android market
- self-hosted Android APK
- iOS App Store
- macOS/Windows installer

Rewrite example to exercise the convenience flow and stable action labels.

Create `.pubignore`:

```text
doc/plans/
docs/plans/
```

Update `CHANGELOG.md` for the commercial quality hardening changes.

**Step 4: Verify green**

Run:

```bash
flutter test test/unit/v3/public_api_test.dart
(cd example && flutter test)
```

Expected: PASS.

**Step 5: Commit**

```bash
git add README.md example/README.md example/lib/main.dart example/test/widget_test.dart CHANGELOG.md .pubignore test/unit/v3/public_api_test.dart
git commit -m "docs: document stable v3 integration flow"
```

---

### Task 7: Harden CI and Publish Workflow

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/publish.yml`

**Step 1: Write config review notes**

This is configuration-only. No production code should change here.

Target CI commands:

```yaml
- name: Check formatting
  run: dart format --output=none --set-exit-if-changed .

- name: Generate docs dry-run
  run: dart doc --dry-run

- name: Test example
  working-directory: example
  run: flutter test
```

Keep existing analyze/test/build/publish dry-run steps.

Publish workflow should use the same `subosito/flutter-action@v2` stable channel as CI unless a specific tested version is required.

**Step 2: Modify CI**

Add format/doc/example-test gates to CI.

Use stable channel consistently in publish workflow.

Keep dry-run before publish.

**Step 3: Verify YAML and workflow content**

Run:

```bash
rg -n "dart format|dart doc --dry-run|flutter test|flutter pub publish --dry-run|channel: stable" .github/workflows
```

Expected: All required gates are present.

**Step 4: Commit**

```bash
git add .github/workflows/ci.yml .github/workflows/publish.yml
git commit -m "ci: enforce package release gates"
```

---

### Task 8: Final Verification and Scoring

**Files:**
- Modify only if verification exposes issues.

**Step 1: Run full verification gate**

Run:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
dart doc --dry-run
flutter pub publish --dry-run
flutter analyze example
(cd example && flutter test)
(cd example && flutter build apk --debug)
```

Expected: all commands exit 0.

**Step 2: Inspect publish archive output**

Check `flutter pub publish --dry-run` output.

Expected:

- 0 warnings.
- No `doc/plans/`.
- No `docs/plans/`.

**Step 3: Re-score dimensions**

Score each dimension:

- Functionality
- Architecture
- Integration
- Platform execution
- Reliability
- Testing
- Open-source release hygiene
- Documentation

Expected: each is 9/10 or higher. If any dimension is below 9, add a small follow-up task and repeat verification.

**Step 4: Commit any final fixes**

Only if files changed:

```bash
git add <intentional files>
git commit -m "chore: finalize v3 commercial quality gates"
```
