import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const minimumFlutter = '3.22.0';

  test('minimum Flutter version is exact and agrees with pubspec', () {
    final versionFile = File('tool/ci/flutter_min_version.txt');
    expect(versionFile.existsSync(), isTrue);
    expect(versionFile.readAsStringSync().trim(), minimumFlutter);

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains("flutter: '>=$minimumFlutter'"));
  });

  test('full gate covers package example archive and every platform', () {
    final file = File('.github/workflows/full-gate.yml');
    expect(file.existsSync(), isTrue);
    final workflow = file.readAsStringSync();

    for (final required in [
      'workflow_call:',
      'quality-minimum:',
      'tool/ci/flutter_min_version.txt',
      r'flutter-version: ${{ steps.minimum-flutter.outputs.version }}',
      'quality-stable:',
      'channel: stable',
      'dart format --output=none --set-exit-if-changed .',
      'flutter analyze --no-pub',
      'flutter test --coverage --no-pub',
      'Enforce total and critical 80% coverage',
      'dart doc --dry-run',
      'flutter analyze --no-pub',
      'flutter test --no-pub',
      'bash tool/ci/publish_dry_run.sh',
      ':flutter_app_updater:testDebugUnitTest',
      ':flutter_app_updater:lintDebug',
      ':app:processDebugMainManifest',
      'flutter build apk --debug --no-pub',
      'flutter build ios --simulator --debug --no-codesign --no-pub',
      'flutter build macos --debug --no-pub',
      'flutter build windows --debug --no-pub',
      'ctest --test-dir build/windows/x64 -C Debug --output-on-failure',
      'gate:',
      'needs:',
    ]) {
      expect(workflow, contains(required), reason: required);
    }

    for (final criticalFile in [
      'manifest_fetcher',
      'manifest_schema',
      'remote_manifest_policy',
      'manifest_signature',
      'package_downloader',
      'package_download_lock',
      'update_selector',
      'install_package_executor',
      'download_and_install_package_executor',
    ]) {
      expect(workflow, contains(criticalFile), reason: criticalFile);
    }

    for (final dependency in [
      'quality-minimum',
      'quality-stable',
      'android-example',
      'ios-example',
      'macos-example',
      'windows-example',
    ]) {
      expect(
        workflow,
        contains(dependency),
        reason: 'final gate must include $dependency',
      );
    }
  });

  test('normal CI delegates to the reusable full gate', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();

    expect(workflow, contains('uses: ./.github/workflows/full-gate.yml'));
    expect(workflow, isNot(contains('flutter test')));
    expect(workflow, isNot(contains('flutter build')));
  });

  test('publish dry run validates a clean committed archive', () {
    final file = File('tool/ci/publish_dry_run.sh');
    expect(file.existsSync(), isTrue);
    final script = file.readAsStringSync();

    expect(script, contains('mktemp -d'));
    expect(script, contains('git archive HEAD'));
    expect(script, contains('flutter pub get'));
    expect(script, contains('flutter pub publish --dry-run'));
    expect(script, contains('Package has 0 warnings'));
  });
}
