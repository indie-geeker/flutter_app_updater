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
}
