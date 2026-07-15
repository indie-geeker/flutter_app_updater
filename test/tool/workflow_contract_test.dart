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
      'dart run tool/ci/verify_cli_executable.dart',
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
      'remote_action_policy',
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

    final minimumJob = workflow.substring(
      workflow.indexOf('  quality-minimum:'),
      workflow.indexOf('  quality-stable:'),
    );
    expect(
      minimumJob,
      contains('dart run tool/ci/verify_cli_executable.dart'),
    );
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

  test('publish proves tag provenance and depends on the full gate', () {
    final workflow = File('.github/workflows/publish.yml').readAsStringSync();

    for (final required in [
      'fetch-depth: 0',
      'dart run tool/ci/verify_release_metadata.dart',
      r'tag_commit="$(git rev-list -n 1 "$GITHUB_REF_NAME")"',
      'git fetch origin main',
      r'git merge-base --is-ancestor "$tag_commit" origin/main',
      'full-gate:',
      'uses: ./.github/workflows/full-gate.yml',
      'release-metadata:',
      'needs: [full-gate, release-metadata]',
      'id-token: write',
      'environment: pub.dev',
    ]) {
      expect(workflow, contains(required), reason: required);
    }
  });

  test('third-party actions and downloaded build inputs are immutable', () {
    final workflows = [
      File('.github/workflows/full-gate.yml').readAsStringSync(),
      File('.github/workflows/publish.yml').readAsStringSync(),
    ];
    final actionPattern =
        RegExp(r'^\s*-?\s*uses:\s*([^\s#]+)', multiLine: true);
    for (final workflow in workflows) {
      for (final match in actionPattern.allMatches(workflow)) {
        final action = match.group(1)!;
        if (action.startsWith('./')) {
          continue;
        }
        expect(
          action,
          matches(RegExp(r'@[0-9a-f]{40}$')),
          reason: action,
        );
      }
    }

    expect(
      File('android/gradle/wrapper/gradle-wrapper.properties')
          .readAsStringSync(),
      contains(
        'distributionSha256Sum='
        'bd71102213493060956ec229d946beee57158dbd89d0e62b91bca0fa2c5f3531',
      ),
    );
    expect(
      File('example/android/gradle/wrapper/gradle-wrapper.properties')
          .readAsStringSync(),
      contains(
        'distributionSha256Sum='
        'ed1a8d686605fd7c23bdf62c7fc7add1c5b23b2bbc3721e661934ef4a4911d7c',
      ),
    );
    expect(
      File('windows/CMakeLists.txt').readAsStringSync(),
      contains(
        'URL_HASH SHA256='
        '353571c2440176ded91c2de6d6cd88ddd41401d14692ec1f99e35d013feda55a',
      ),
    );
  });

  test('Dependabot covers both Android Gradle projects', () {
    final dependabot = File('.github/dependabot.yml').readAsStringSync();

    expect(dependabot, contains('package-ecosystem: gradle'));
    expect(dependabot, contains('directory: /android'));
    expect(dependabot, contains('directory: /example/android'));
  });
}
