import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _normalizeWhitespace(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

void _expectNormalizedContains(
  String document,
  String contract, {
  String? reason,
}) {
  expect(
    _normalizeWhitespace(document),
    contains(_normalizeWhitespace(contract)),
    reason: reason ?? contract,
  );
}

void _expectMarkdownFieldStatus(
  String document,
  String field,
  String status,
) {
  final row = RegExp(
    '^\\|\\s*`${RegExp.escape(field)}`\\s*\\|\\s*'
    '${RegExp.escape(status)}\\s*\\|',
    multiLine: true,
  );
  expect(
    document,
    matches(row),
    reason: 'Expected `$field` to be documented as $status',
  );
}

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

  test('English and Chinese READMEs document manifest delivery contracts', () {
    final english = File('README.md').readAsStringSync();
    final chinese = File('README.zh-CN.md').readAsStringSync();

    expect(english, contains('[简体中文](README.zh-CN.md)'));
    expect(english, contains('Static JSON file'));
    expect(english, contains('RESTful API'));
    expect(english, contains('Manifest fields: required and optional'));

    expect(chinese, contains('[English](README.md)'));
    expect(chinese, contains('静态 JSON 文件'));
    expect(chinese, contains('RESTful 接口'));
    expect(chinese, contains('必填'));
    expect(chinese, contains('选填'));
    expect(chinese, contains('Manifest 字段：必填与选填'));

    for (final readme in [english, chinese]) {
      for (final field in [
        'schemaVersion',
        'appId',
        'channel',
        'releases',
        'version',
        'platform',
        'releaseNotes',
        'actions',
        'buildNumber',
        'architecture',
        'releasedAt',
        'policy',
        'storeUrl',
        'packageUrl',
        'installerUrl',
        'packageSizeBytes',
        'installerSizeBytes',
        'sha256',
      ]) {
        expect(readme, contains('`$field`'), reason: 'Missing $field');
      }
    }
  });

  test('bilingual schema tables classify required and optional fields', () {
    final english = File('README.md').readAsStringSync();
    final chinese = File('README.zh-CN.md').readAsStringSync();

    for (final field in [
      'schemaVersion',
      'appId',
      'channel',
      'releases',
      'version',
      'platform',
      'releaseNotes',
      'actions',
      'format',
      'keyId',
      'issuedAt',
      'expiresAt',
      'payload',
      'signature',
    ]) {
      _expectMarkdownFieldStatus(english, field, 'Yes');
      _expectMarkdownFieldStatus(chinese, field, '必填');
    }

    for (final field in [
      'buildNumber',
      'channel',
      'architecture',
      'releasedAt',
      'policy',
      'level',
      'minSupportedVersion',
    ]) {
      _expectMarkdownFieldStatus(english, field, 'No');
      _expectMarkdownFieldStatus(chinese, field, '选填');
    }
  });

  test('bilingual READMEs define the fail-closed manifest semantics', () {
    final english = File('README.md').readAsStringSync();
    final chinese = File('README.zh-CN.md').readAsStringSync();

    for (final contract in [
      'Every action object requires a non-empty `type` discriminator.',
      '`buildNumber` is optional. When present it must be a non-negative ASCII decimal integer string',
      'Leading zeroes are allowed and the value is parsed as an integer.',
      'Any other value rejects the entire response.',
      '`minSupportedVersion`, when present, must be less than or equal to that release\'s `version`.',
      'Manifest v3 is an exact allowlist at every object boundary',
      'There is no `extensions` escape hatch.',
      'The signed envelope also rejects extra fields.',
      'Adding a field requires a new schema version.',
    ]) {
      _expectNormalizedContains(english, contract);
    }

    for (final contract in [
      '每个 action 对象都必须包含非空的 `type` 判别字段。',
      '`buildNumber` 是选填字段；提供时必须是非负 ASCII 十进制整数字符串',
      '允许前导零，并按整数解析。',
      '其他值会导致整个响应被拒绝。',
      '`minSupportedVersion` 提供时不得大于同一 release 的 `version`。',
      'Manifest v3 在每个对象边界都使用精确白名单',
      '不存在 `extensions` 逃生口。',
      '签名 envelope 也会拒绝多余字段。',
      '新增字段必须升级 schema version。',
    ]) {
      _expectNormalizedContains(chinese, contract);
    }
  });

  test('optional signatures permit only store and Android-market manifests',
      () {
    final english = File('README.md').readAsStringSync();
    final chinese = File('README.zh-CN.md').readAsStringSync();
    final model = File('doc/security-model.md').readAsStringSync();
    final signatureApi =
        File('lib/src/manifest/manifest_signature.dart').readAsStringSync();

    _expectNormalizedContains(
      english,
      'a bare response is accepted only for official-store or Android-market actions when `ManifestSignaturePolicy.optional` is used. Self-hosted package or installer actions require a valid Ed25519 envelope.',
    );
    _expectNormalizedContains(
      chinese,
      '只有在使用 `ManifestSignaturePolicy.optional` 且清单仅包含官方商店或 Android 市场动作时，才允许返回裸清单。自托管包或桌面安装器必须使用有效的 Ed25519 envelope。',
    );
    _expectNormalizedContains(
      model,
      'Optional policy permits a bare manifest containing only official-store or Android-market actions over trusted transport, but never permits a bare self-hosted artifact.',
    );
    _expectNormalizedContains(
      signatureApi,
      'Allows bare official-store and Android-market manifests but authenticates envelopes if used.',
    );

    for (final document in [english, model]) {
      expect(
        document,
        isNot(contains('official-store-only')),
        reason: 'Android-market-only manifests are also allowed by policy',
      );
    }
  });

  test('docs distinguish foreground and durable URL credential boundaries', () {
    final english = File('README.md').readAsStringSync();
    final chinese = File('README.zh-CN.md').readAsStringSync();
    final policy = File('SECURITY.md').readAsStringSync();
    final model = File('doc/security-model.md').readAsStringSync();

    for (final contract in [
      'Foreground downloads and Android durable downloads have different URL persistence contracts.',
      'The foreground action flow may use an HTTPS artifact URL with short-lived query credentials.',
      'The foreground checkpoint stores only a SHA-256 URL fingerprint, never the raw URL or query token.',
      'Android durable `start()` accepts only a stable, credential-free entry URL with no userinfo, query, or fragment.',
      'The signed redirect target exists only as the current process\'s in-memory transport target and is never persisted.',
      'stable entry endpoint to return an HTTPS redirect to a short-lived signed URL',
      'Durable task state is stored under Android `noBackupFilesDir`',
      'APK and partial artifacts are stored under the app-private `filesDir`',
      'pre-release single-root layout are reset instead of migrated',
    ]) {
      _expectNormalizedContains(english, contract);
    }

    for (final contract in [
      '前台下载与 Android 持久下载使用不同的 URL 持久化契约。',
      '前台 action 流可以使用带短期 query 凭证的 HTTPS 文件 URL。',
      '前台 checkpoint 只保存 SHA-256 URL 指纹，不保存原始 URL 或 query token。',
      'Android 持久下载的 `start()` 只接受不含 userinfo、query 或 fragment 的稳定、无凭证入口 URL。',
      '带签名的重定向目标只存在于当前进程内存中的传输上下文，绝不会持久化。',
      '稳定入口返回到短期签名 URL 的 HTTPS 重定向',
      '持久任务状态存放在 Android `noBackupFilesDir`',
      'APK 和部分下载文件存放在应用私有 `filesDir`',
      '预发布 single-root 布局中的旧任务和文件会被重置而不是迁移',
    ]) {
      _expectNormalizedContains(chinese, contract);
    }

    for (final document in [policy, model]) {
      for (final contract in [
        'foreground checkpoint',
        'stable entry URL',
        'no userinfo, query, or fragment',
        'in-memory transport target',
        'never persisted',
      ]) {
        _expectNormalizedContains(document, contract);
      }
    }
  });

  test('security and release docs record strict schema and storage migration',
      () {
    final security = File('doc/security-model.md').readAsStringSync();
    final changelog = File('CHANGELOG.md').readAsStringSync();
    final release300 = changelog.split('## 3.0.0').last.split('## 2.1.0').first;

    for (final contract in [
      'exact allowlist',
      'unknown fields',
      '`extensions`',
      'new schema version',
      '`buildNumber`',
      '`minSupportedVersion`',
      'Every action object requires `type`',
      'signed envelope rejects extra fields',
    ]) {
      _expectNormalizedContains(security, contract);
    }

    for (final contract in [
      'credential-free stable entry URL',
      'pre-release single-root background tasks',
      'strict manifest and signed-envelope allowlists',
      'pure-Dart manifest CLI',
    ]) {
      _expectNormalizedContains(release300, contract);
    }
    expect(release300, isNot(contains('No changes yet.')));
  });

  test('public documentation does not leak local or internal work paths', () {
    final documents = [
      'README.md',
      'README.zh-CN.md',
      'SECURITY.md',
      'doc/security-model.md',
      'CHANGELOG.md',
    ];

    for (final path in documents) {
      final contents = File(path).readAsStringSync();
      expect(contents, isNot(matches(RegExp(r'/(Users|home)/'))), reason: path);
      expect(contents, isNot(contains(r'C:\Users\')), reason: path);
      expect(contents, isNot(contains('.config/superpowers/worktrees')),
          reason: path);
      expect(contents, isNot(contains('commercial-hardening-followup')),
          reason: path);
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
