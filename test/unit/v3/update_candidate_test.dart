import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateCandidate', () {
    test('captures v3 release metadata with direct field names', () {
      final releasedAt = DateTime.utc(2026, 7, 3, 10);
      const policy = UpdatePolicy(
        level: UpdatePolicyLevel.required,
        minSupportedVersion: '1.5.0',
      );
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 25600000,
        sha256: 'a' * 64,
      );

      final candidate = UpdateCandidate(
        version: '2.0.0',
        buildNumber: '42',
        channel: 'stable',
        platform: TargetPlatform.android,
        architecture: 'arm64',
        releaseNotes: 'Bug fixes',
        releasedAt: releasedAt,
        policy: policy,
        actions: [action],
      );

      expect(candidate.version, '2.0.0');
      expect(candidate.buildNumber, '42');
      expect(candidate.channel, 'stable');
      expect(candidate.platform, TargetPlatform.android);
      expect(candidate.architecture, 'arm64');
      expect(candidate.releaseNotes, 'Bug fixes');
      expect(candidate.releasedAt, releasedAt);
      expect(candidate.policy.level, UpdatePolicyLevel.required);
      expect(candidate.actions.single, same(action));
    });

    test('supports optional update policy defaults', () {
      const policy = UpdatePolicy();

      expect(policy.level, UpdatePolicyLevel.optional);
      expect(policy.minSupportedVersion, isNull);
    });
  });
}
