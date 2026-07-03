import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/core/app_updater.dart';
import 'package:flutter_app_updater/src/core/update_selector.dart';
import 'package:flutter_app_updater/src/core/update_source.dart';
import 'package:flutter_app_updater/src/manifest/update_manifest.dart';
import 'package:flutter_app_updater/src/models/update_candidate.dart';
import 'package:flutter_app_updater/src/models/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateSelector', () {
    test('ignores releases for other platforms', () {
      final result = _selector(platform: TargetPlatform.android).select([
        _candidate(version: '3.0.0', platform: TargetPlatform.iOS),
        _candidate(version: '2.0.0', platform: TargetPlatform.android),
      ]);

      expect(result, isA<UpdateAvailable>());
      expect((result as UpdateAvailable).candidate.version, '2.0.0');
    });

    test('ignores releases for other architectures', () {
      final result = _selector(architecture: 'arm64').select([
        _candidate(version: '3.0.0', architecture: 'x64'),
        _candidate(version: '2.0.0', architecture: 'arm64'),
      ]);

      expect(result, isA<UpdateAvailable>());
      expect((result as UpdateAvailable).candidate.architecture, 'arm64');
    });

    test('respects configured channel', () {
      final result = _selector(channel: 'stable').select([
        _candidate(version: '3.0.0', channel: 'beta'),
        _candidate(version: '2.0.0', channel: 'stable'),
      ]);

      expect(result, isA<UpdateAvailable>());
      expect((result as UpdateAvailable).candidate.channel, 'stable');
    });

    test('selects the highest version greater than installed version', () {
      final result = _selector(installedVersion: '1.0.0').select([
        _candidate(version: '2.0.0'),
        _candidate(version: '2.1.0'),
        _candidate(version: '1.5.0'),
      ]);

      expect(result, isA<UpdateAvailable>());
      expect((result as UpdateAvailable).candidate.version, '2.1.0');
    });

    test('returns no update when installed version is current', () {
      final result = _selector(installedVersion: '2.0.0').select([
        _candidate(version: '2.0.0'),
        _candidate(version: '1.9.0'),
      ]);

      expect(result, isA<UpdateNotAvailable>());
    });

    test('prioritizes direct actions for required updates', () {
      final packageAction = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        sha256: 'a' * 64,
      );
      final result = _selector().select([
        _candidate(
          version: '2.0.0',
          policyLevel: UpdatePolicyLevel.required,
          actions: [
            OpenStoreAction(
              store: StoreKind.googlePlay,
              storeUrl: Uri.parse(
                'https://play.google.com/store/apps/details?id=com.example.app',
              ),
            ),
            packageAction,
          ],
        ),
      ]);

      expect(result, isA<UpdateAvailable>());
      expect(
          (result as UpdateAvailable).recommendedAction, same(packageAction));
    });
  });

  group('AppUpdater', () {
    test('check returns a structured result for static manifests', () async {
      final updater = AppUpdater(
        source: UpdateSource.staticManifest(
          manifest: UpdateManifest(
            schemaVersion: 3,
            appId: 'com.example.app',
            channel: 'stable',
            releases: [_candidate(version: '2.0.0')],
          ),
        ),
      );

      final result = await updater.check(selector: _selector());

      expect(result, isA<UpdateAvailable>());
    });
  });
}

UpdateSelector _selector({
  String installedVersion = '1.0.0',
  String? installedBuildNumber,
  TargetPlatform platform = TargetPlatform.android,
  String? architecture = 'arm64',
  String channel = 'stable',
}) {
  return UpdateSelector(
    installedVersion: installedVersion,
    installedBuildNumber: installedBuildNumber,
    platform: platform,
    architecture: architecture,
    channel: channel,
  );
}

UpdateCandidate _candidate({
  required String version,
  TargetPlatform platform = TargetPlatform.android,
  String? architecture = 'arm64',
  String channel = 'stable',
  UpdatePolicyLevel policyLevel = UpdatePolicyLevel.optional,
  List<UpdateAction>? actions,
}) {
  return UpdateCandidate(
    version: version,
    channel: channel,
    platform: platform,
    architecture: architecture,
    releaseNotes: 'Bug fixes',
    policy: UpdatePolicy(level: policyLevel),
    actions: actions ??
        [
          DownloadPackageAction(
            packageUrl: Uri.parse('https://example.com/app.apk'),
            packageType: PackageType.apk,
            sha256: 'a' * 64,
          ),
        ],
  );
}
