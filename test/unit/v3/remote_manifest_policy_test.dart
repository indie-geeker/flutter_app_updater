import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/manifest/remote_manifest_policy.dart';
import 'package:flutter_app_updater/src/manifest/update_manifest.dart';
import 'package:flutter_app_updater/src/models/update_candidate.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_app_updater/src/models/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteManifestPolicy', () {
    test('accepts trusted artifact and official store actions', () {
      final manifest = _manifest([
        DownloadPackageAction(
          packageUrl: Uri.parse('https://cdn.example.com/app.apk'),
          packageType: PackageType.apk,
          packageSizeBytes: 42,
          sha256: 'a' * 64,
        ),
        OpenStoreAction(
          store: StoreKind.googlePlay,
          storeUrl: Uri.parse(
            'https://play.google.com/store/apps/details?id=com.example.app',
          ),
        ),
      ]);

      expect(
        () => const RemoteManifestPolicy().validate(manifest),
        returnsNormally,
      );
    });

    test(
        'unsigned manifests allow store actions but require signatures for artifacts',
        () {
      final storeManifest = _manifest([
        OpenStoreAction(
          store: StoreKind.googlePlay,
          storeUrl: Uri.parse(
            'https://play.google.com/store/apps/details?id=com.example.app',
          ),
        ),
      ]);
      final artifactManifest = _manifest([
        DownloadPackageAction(
          packageUrl: Uri.parse('https://cdn.example.com/app.apk'),
          packageType: PackageType.apk,
          packageSizeBytes: 42,
          sha256: 'a' * 64,
        ),
      ]);

      expect(
        () => const RemoteManifestPolicy().validate(
          storeManifest,
          isSigned: false,
        ),
        returnsNormally,
      );
      expect(
        () => const RemoteManifestPolicy().validate(
          artifactManifest,
          isSigned: false,
        ),
        _policyFailure(UpdateErrorCode.manifestSignatureRequired),
      );
    });

    test('rejects remote installPackage actions', () {
      expect(
        () => const RemoteManifestPolicy().validate(
          _manifest([
            const InstallPackageAction(packagePath: '/tmp/app.apk'),
          ]),
        ),
        _policyFailure(UpdateErrorCode.unsupportedActionType),
      );
    });

    test('rejects untrusted artifact URLs', () {
      for (final url in [
        'http://cdn.example.com/app.apk',
        'https://user:password@cdn.example.com/app.apk',
      ]) {
        expect(
          () => const RemoteManifestPolicy().validate(
            _manifest([
              DownloadPackageAction(
                packageUrl: Uri.parse(url),
                packageType: PackageType.apk,
                packageSizeBytes: 42,
                sha256: 'a' * 64,
              ),
            ]),
          ),
          _policyFailure(UpdateErrorCode.manifestInvalid),
        );
      }
    });

    test('requires Android market package name to equal manifest appId', () {
      expect(
        () => const RemoteManifestPolicy().validate(
          _manifest([
            const OpenAndroidMarketAction(
              market: AndroidMarketKind.huawei,
              targetPackageName: 'com.example.other',
            ),
          ]),
        ),
        _policyFailure(UpdateErrorCode.appIdMismatch),
      );
    });

    test('requires trusted HTTPS market fallback URLs', () {
      expect(
        () => const RemoteManifestPolicy().validate(
          _manifest([
            OpenAndroidMarketAction(
              market: AndroidMarketKind.huawei,
              targetPackageName: 'com.example.app',
              fallbackUrl: Uri.parse('http://appgallery.example.com/app'),
            ),
          ]),
        ),
        _policyFailure(UpdateErrorCode.manifestInvalid),
      );
    });

    test('requires official store hosts', () {
      final cases = [
        OpenStoreAction(
          store: StoreKind.googlePlay,
          storeUrl: Uri.parse('https://evil.example.com/google-play'),
        ),
        OpenStoreAction(
          store: StoreKind.appStore,
          storeUrl: Uri.parse('https://evil.example.com/app-store'),
        ),
        OpenStoreAction(
          store: StoreKind.macAppStore,
          storeUrl: Uri.parse('https://evil.example.com/mac-app-store'),
        ),
      ];

      for (final action in cases) {
        expect(
          () => const RemoteManifestPolicy().validate(_manifest([action])),
          _policyFailure(UpdateErrorCode.manifestInvalid),
        );
      }
    });
  });
}

Matcher _policyFailure(UpdateErrorCode code) {
  return throwsA(
    isA<RemoteManifestPolicyException>().having(
      (error) => error.code,
      'code',
      code,
    ),
  );
}

UpdateManifest _manifest(List<UpdateAction> actions) {
  return UpdateManifest(
    schemaVersion: 3,
    appId: 'com.example.app',
    channel: 'stable',
    releases: [
      UpdateCandidate(
        version: '2.0.0',
        channel: 'stable',
        platform: TargetPlatform.android,
        releaseNotes: 'Bug fixes',
        policy: const UpdatePolicy(),
        actions: actions,
      ),
    ],
  );
}
