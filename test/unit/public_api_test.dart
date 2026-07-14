import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public library exports v3 core model types', () {
    final signaturePolicy = ManifestSignaturePolicy.required(
      trustedPublicKeys: const {'release-key': 'public-key'},
    );
    final source = UpdateSource.manifest(
      manifestUrl: Uri.parse('https://example.com/app-updates.json'),
      expectedAppId: 'com.example.app',
      signaturePolicy: signaturePolicy,
    );
    final fetched = FetchedManifest(
      bodyBytes: Uint8List(0),
      finalUri: Uri.parse('https://example.com/app-updates.json'),
      responseHeaders: const {},
    );
    final updater = AppUpdater(source: source);
    const policy = UpdatePolicy(
      level: UpdatePolicyLevel.recommended,
      minSupportedVersion: '1.5.0',
    );
    final storeAction = OpenStoreAction(
      store: StoreKind.googlePlay,
      storeUrl: Uri.parse(
        'https://play.google.com/store/apps/details?id=com.example.app',
      ),
    );
    final marketAction = OpenAndroidMarketAction(
      market: AndroidMarketKind.huawei,
      targetPackageName: 'com.example.app',
      fallbackUrl: Uri.parse('https://appgallery.huawei.com/app/example'),
    );
    final packageAction = DownloadPackageAction(
      packageUrl: Uri.parse('https://example.com/app.apk'),
      packageType: PackageType.apk,
      packageSizeBytes: 42,
      sha256: 'a' * 64,
    );
    final installerAction = OpenInstallerAction(
      installerUrl: Uri.parse('https://example.com/app.msi'),
      installerType: InstallerType.msi,
      installerSizeBytes: 42,
      sha256: 'b' * 64,
    );
    final candidate = UpdateCandidate(
      version: '2.0.0',
      channel: 'stable',
      platform: TargetPlatform.android,
      releaseNotes: 'Bug fixes',
      policy: policy,
      actions: [
        storeAction,
        marketAction,
        packageAction,
        installerAction,
      ],
    );

    expect(updater.source, same(source));
    expect(
      (source as ManifestUpdateSource).expectedAppId,
      'com.example.app',
    );
    expect(source.signaturePolicy, same(signaturePolicy));
    expect(fetched.bodyBytes, isEmpty);
    expect(candidate.policy, same(policy));
    expect(candidate.actions, [
      storeAction,
      marketAction,
      packageAction,
      installerAction,
    ]);
  });
}
