import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migration and security guides exist and are linked from README', () {
    final readme = File('README.md').readAsStringSync();
    final migration = File('doc/migration-v2-to-v3.md');
    final security = File('doc/security-model.md');

    expect(migration.existsSync(), isTrue);
    expect(security.existsSync(), isTrue);
    expect(readme, contains('doc/migration-v2-to-v3.md'));
    expect(readme, contains('doc/security-model.md'));
  });

  test('migration guide covers every breaking integration boundary', () {
    final migration = File('doc/migration-v2-to-v3.md').readAsStringSync();

    for (final contract in [
      'AppUpdater',
      'UpdateCandidate',
      'UpdatePolicy',
      'UpdateAction',
      'checkAndPrepare',
      'performRecommended',
      'UpdatePolicyLevel.required',
      'SHA-256',
    ]) {
      expect(migration, contains(contract), reason: 'Missing $contract');
    }
  });

  test('security guide covers the complete remote trust chain', () {
    final security = File('doc/security-model.md').readAsStringSync();

    for (final contract in [
      'HTTPS',
      'expectedAppId',
      'packageSizeBytes',
      'sha256',
      'Ed25519',
      'keyId',
      'package identity',
      'signing lineage',
    ]) {
      expect(security, contains(contract), reason: 'Missing $contract');
    }
    expect(
      security,
      isNot(contains('FLUTTER_APP_UPDATER_ED25519_PRIVATE_KEY_BASE64=')),
    );
  });

  test('README describes the final fail-closed commercial contract', () {
    final readme = File('README.md').readAsStringSync();

    for (final contract in [
      'publisher order',
      'UpdateDistributionPolicy.storeOnly',
      'Unknown runtime architecture',
      'limited to five',
      'same-origin',
      'exact byte size',
      'Ed25519',
      'keyId',
      'package identity',
      'signing lineage',
      'URL fingerprint',
      'operating-system lock',
      'Flutter 3.22.0',
      'verify_release_metadata.dart',
    ]) {
      expect(readme, contains(contract), reason: 'Missing $contract');
    }

    for (final staleClaim in [
      'sha256` remains optional',
      '`sha256` is optional',
      'optional-file-hash',
      '"packagePath"',
      'Play In-App Updates',
      '| OHOS |',
      'explicit remote mode',
    ]) {
      expect(readme, isNot(contains(staleClaim)), reason: staleClaim);
    }
  });

  test('example distinguishes inert simulation from explicit production use',
      () {
    final readme = File('example/README.md').readAsStringSync();

    expect(readme, contains('No external side effects'));
    expect(readme, contains('disabled by default'));
    expect(readme, contains('separate confirmation'));
    expect(readme, contains('real signed-manifest path'));
    expect(readme, isNot(contains('device suite')));
    expect(readme, isNot(contains('adb reverse')));
    expect(readme, isNot(contains('<device-id>')));
  });

  test('release and contribution docs match automated provenance policy', () {
    final changelog = File('CHANGELOG.md').readAsStringSync();
    final contributing = File('CONTRIBUTING.md').readAsStringSync();
    final security = File('SECURITY.md').readAsStringSync();

    for (final contract in [
      'strict architecture',
      'distribution policy',
      'Ed25519',
      'APK identity',
      'checkpoint',
      'production integration',
      'full quality gate',
      'release provenance',
    ]) {
      expect(changelog, contains(contract), reason: 'Missing $contract');
    }
    expect(changelog,
        isNot(contains('Make package and installer hashes optional')));
    expect(changelog, isNot(contains('explicit remote mode')));

    expect(contributing, contains('Flutter 3.22.0'));
    expect(contributing, contains('v{{version}}'));
    expect(contributing, contains('origin/main'));
    expect(contributing, contains('verify_release_metadata.dart'));

    expect(security, contains('Ed25519'));
    expect(security, contains('exact size and SHA-256'));
    expect(security, contains('package identity and signing lineage'));
    expect(security, contains('query tokens'));
  });
}
