import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/manifest/manifest_document.dart';
import 'package:flutter_app_updater/src/manifest/remote_action_policy.dart';
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

    test('primitive store policy accepts package-owned store kinds', () {
      expect(
        () => const RemoteActionPolicy().validateStore(
          store: ManifestStoreKind.googlePlay,
          storeUrl: Uri.parse('https://play.google.com/store/apps/details'),
        ),
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

    test('document and runtime wrappers share every remote action rule', () {
      final cases = <({
        ManifestDocument document,
        UpdateManifest runtime,
        bool isSigned,
      })>[
        (
          document: _document([
            ManifestDownloadPackageAction(
              packageUrl: Uri.parse('https://cdn.example.com/app.apk'),
              packageType: ManifestPackageType.apk,
              packageSizeBytes: 42,
              sha256: 'a' * 64,
            ),
          ]),
          runtime: _manifest([
            DownloadPackageAction(
              packageUrl: Uri.parse('https://cdn.example.com/app.apk'),
              packageType: PackageType.apk,
              packageSizeBytes: 42,
              sha256: 'a' * 64,
            ),
          ]),
          isSigned: false,
        ),
        (
          document: _document([
            ManifestDownloadPackageAction(
              packageUrl: Uri.parse('http://cdn.example.com/app.apk'),
              packageType: ManifestPackageType.apk,
              packageSizeBytes: 42,
              sha256: 'a' * 64,
            ),
          ]),
          runtime: _manifest([
            DownloadPackageAction(
              packageUrl: Uri.parse('http://cdn.example.com/app.apk'),
              packageType: PackageType.apk,
              packageSizeBytes: 42,
              sha256: 'a' * 64,
            ),
          ]),
          isSigned: true,
        ),
        (
          document: _document([
            ManifestDownloadPackageAction(
              packageUrl: Uri.parse(
                'https://user:password@cdn.example.com/app.apk',
              ),
              packageType: ManifestPackageType.apk,
              packageSizeBytes: 42,
              sha256: 'a' * 64,
            ),
          ]),
          runtime: _manifest([
            DownloadPackageAction(
              packageUrl: Uri.parse(
                'https://user:password@cdn.example.com/app.apk',
              ),
              packageType: PackageType.apk,
              packageSizeBytes: 42,
              sha256: 'a' * 64,
            ),
          ]),
          isSigned: true,
        ),
        (
          document: _document([
            ManifestDownloadPackageAction(
              packageUrl: Uri.parse('https://cdn.example.com/app.apk'),
              packageType: ManifestPackageType.apk,
              packageSizeBytes: 0,
              sha256: 'a' * 64,
            ),
          ]),
          runtime: _manifest([
            DownloadPackageAction(
              packageUrl: Uri.parse('https://cdn.example.com/app.apk'),
              packageType: PackageType.apk,
              packageSizeBytes: 0,
              sha256: 'a' * 64,
            ),
          ]),
          isSigned: true,
        ),
        (
          document: _document([
            ManifestDownloadPackageAction(
              packageUrl: Uri.parse('https://cdn.example.com/app.apk'),
              packageType: ManifestPackageType.apk,
              packageSizeBytes: 42,
              sha256: 'not-a-digest',
            ),
          ]),
          runtime: _manifest([
            DownloadPackageAction(
              packageUrl: Uri.parse('https://cdn.example.com/app.apk'),
              packageType: PackageType.apk,
              packageSizeBytes: 42,
              sha256: 'not-a-digest',
            ),
          ]),
          isSigned: true,
        ),
        (
          document: _document([
            ManifestOpenStoreAction(
              store: ManifestStoreKind.googlePlay,
              storeUrl: Uri.parse('https://evil.example.com/google-play'),
            ),
          ]),
          runtime: _manifest([
            OpenStoreAction(
              store: StoreKind.googlePlay,
              storeUrl: Uri.parse('https://evil.example.com/google-play'),
            ),
          ]),
          isSigned: true,
        ),
        (
          document: _document([
            const ManifestOpenAndroidMarketAction(
              market: ManifestAndroidMarketKind.huawei,
              targetPackageName: 'com.example.other',
            ),
          ]),
          runtime: _manifest([
            const OpenAndroidMarketAction(
              market: AndroidMarketKind.huawei,
              targetPackageName: 'com.example.other',
            ),
          ]),
          isSigned: true,
        ),
        (
          document: _document([
            ManifestOpenAndroidMarketAction(
              market: ManifestAndroidMarketKind.huawei,
              targetPackageName: 'com.example.app',
              fallbackUrl: Uri.parse('http://appgallery.example.com/app'),
            ),
          ]),
          runtime: _manifest([
            OpenAndroidMarketAction(
              market: AndroidMarketKind.huawei,
              targetPackageName: 'com.example.app',
              fallbackUrl: Uri.parse('http://appgallery.example.com/app'),
            ),
          ]),
          isSigned: true,
        ),
        (
          document: _document([
            const ManifestInstallPackageAction(
              packagePath: '/tmp/app.apk',
              packageType: ManifestPackageType.apk,
            ),
          ]),
          runtime: _manifest([
            const InstallPackageAction(packagePath: '/tmp/app.apk'),
          ]),
          isSigned: true,
        ),
      ];

      for (final policyCase in cases) {
        final documentError = _capturePolicyFailure(
          () => const RemoteActionPolicy().validateDocument(
            policyCase.document,
            isSigned: policyCase.isSigned,
          ),
        );
        final runtimeError = _capturePolicyFailure(
          () => const RemoteManifestPolicy().validate(
            policyCase.runtime,
            isSigned: policyCase.isSigned,
          ),
        );

        expect(documentError.code, runtimeError.code);
        expect(documentError.message, runtimeError.message);
      }
    });

    test('installer adapters accept the same valid signed action', () {
      _expectPolicyParitySuccess(
        documentAction: ManifestOpenInstallerAction(
          installerUrl: Uri.parse('https://cdn.example.com/app.dmg'),
          installerType: ManifestInstallerType.dmg,
          installerSizeBytes: 42,
          sha256: 'a' * 64,
        ),
        runtimeAction: OpenInstallerAction(
          installerUrl: Uri.parse('https://cdn.example.com/app.dmg'),
          installerType: InstallerType.dmg,
          installerSizeBytes: 42,
          sha256: 'a' * 64,
        ),
      );
    });

    test('installer adapters preserve exact policy failures', () {
      final cases = <({
        String name,
        String url,
        int size,
        String sha256,
        bool isSigned,
        UpdateErrorCode code,
        String message,
      })>[
        (
          name: 'signature priority',
          url: 'http://cdn.example.com/app.dmg',
          size: 0,
          sha256: 'not-a-digest',
          isSigned: false,
          code: UpdateErrorCode.manifestSignatureRequired,
          message: 'Self-hosted update actions require a signed manifest.',
        ),
        (
          name: 'untrusted URL',
          url: 'http://cdn.example.com/app.dmg',
          size: 42,
          sha256: 'a' * 64,
          isSigned: true,
          code: UpdateErrorCode.manifestInvalid,
          message: 'must use HTTPS; insecure HTTP is allowed only for '
              'explicitly enabled loopback development URLs',
        ),
        (
          name: 'invalid size',
          url: 'https://cdn.example.com/app.dmg',
          size: 0,
          sha256: 'a' * 64,
          isSigned: true,
          code: UpdateErrorCode.missingRequiredField,
          message: 'installerUrl requires a positive exact size.',
        ),
        (
          name: 'invalid digest',
          url: 'https://cdn.example.com/app.dmg',
          size: 42,
          sha256: 'not-a-digest',
          isSigned: true,
          code: UpdateErrorCode.missingRequiredField,
          message: 'installerUrl requires a 64-character SHA-256.',
        ),
      ];

      for (final testCase in cases) {
        _expectPolicyParityFailure(
          name: testCase.name,
          documentAction: ManifestOpenInstallerAction(
            installerUrl: Uri.parse(testCase.url),
            installerType: ManifestInstallerType.dmg,
            installerSizeBytes: testCase.size,
            sha256: testCase.sha256,
          ),
          runtimeAction: OpenInstallerAction(
            installerUrl: Uri.parse(testCase.url),
            installerType: InstallerType.dmg,
            installerSizeBytes: testCase.size,
            sha256: testCase.sha256,
          ),
          isSigned: testCase.isSigned,
          code: testCase.code,
          message: testCase.message,
        );
      }
    });

    test('combined package adapters preserve success and key failures', () {
      _expectPolicyParitySuccess(
        documentAction: ManifestDownloadAndInstallPackageAction(
          packageUrl: Uri.parse('https://cdn.example.com/app.apk'),
          packageType: ManifestPackageType.apk,
          packageSizeBytes: 42,
          sha256: 'a' * 64,
        ),
        runtimeAction: DownloadAndInstallPackageAction(
          packageUrl: Uri.parse('https://cdn.example.com/app.apk'),
          packageType: PackageType.apk,
          packageSizeBytes: 42,
          sha256: 'a' * 64,
        ),
      );

      final cases = <({
        String name,
        String url,
        int size,
        String sha256,
        bool isSigned,
        UpdateErrorCode code,
        String message,
      })>[
        (
          name: 'signature priority',
          url: 'http://cdn.example.com/app.apk',
          size: 0,
          sha256: 'not-a-digest',
          isSigned: false,
          code: UpdateErrorCode.manifestSignatureRequired,
          message: 'Self-hosted update actions require a signed manifest.',
        ),
        (
          name: 'userinfo URL',
          url: 'https://user:password@cdn.example.com/app.apk',
          size: 42,
          sha256: 'a' * 64,
          isSigned: true,
          code: UpdateErrorCode.manifestInvalid,
          message: 'must not contain user information',
        ),
        (
          name: 'invalid size',
          url: 'https://cdn.example.com/app.apk',
          size: 0,
          sha256: 'a' * 64,
          isSigned: true,
          code: UpdateErrorCode.missingRequiredField,
          message: 'packageUrl requires a positive exact size.',
        ),
        (
          name: 'invalid digest',
          url: 'https://cdn.example.com/app.apk',
          size: 42,
          sha256: 'not-a-digest',
          isSigned: true,
          code: UpdateErrorCode.missingRequiredField,
          message: 'packageUrl requires a 64-character SHA-256.',
        ),
      ];

      for (final testCase in cases) {
        _expectPolicyParityFailure(
          name: testCase.name,
          documentAction: ManifestDownloadAndInstallPackageAction(
            packageUrl: Uri.parse(testCase.url),
            packageType: ManifestPackageType.apk,
            packageSizeBytes: testCase.size,
            sha256: testCase.sha256,
          ),
          runtimeAction: DownloadAndInstallPackageAction(
            packageUrl: Uri.parse(testCase.url),
            packageType: PackageType.apk,
            packageSizeBytes: testCase.size,
            sha256: testCase.sha256,
          ),
          isSigned: testCase.isSigned,
          code: testCase.code,
          message: testCase.message,
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

ManifestDocument _document(List<ManifestAction> actions) {
  return ManifestDocument(
    schemaVersion: 3,
    appId: 'com.example.app',
    channel: 'stable',
    releases: [
      ManifestReleaseDocument(
        version: '2.0.0',
        channel: 'stable',
        platform: ManifestPlatform.android,
        releaseNotes: 'Bug fixes',
        policy: const ManifestPolicyDocument(),
        actions: actions,
      ),
    ],
  );
}

RemoteManifestPolicyException _capturePolicyFailure(void Function() validate) {
  try {
    validate();
  } on RemoteManifestPolicyException catch (error) {
    return error;
  }
  fail('Expected RemoteManifestPolicyException.');
}

void _expectPolicyParitySuccess({
  required ManifestAction documentAction,
  required UpdateAction runtimeAction,
}) {
  expect(
    () => const RemoteActionPolicy().validateDocument(
      _document([documentAction]),
    ),
    returnsNormally,
  );
  expect(
    () => const RemoteManifestPolicy().validate(_manifest([runtimeAction])),
    returnsNormally,
  );
}

void _expectPolicyParityFailure({
  required String name,
  required ManifestAction documentAction,
  required UpdateAction runtimeAction,
  required bool isSigned,
  required UpdateErrorCode code,
  required String message,
}) {
  final documentError = _capturePolicyFailure(
    () => const RemoteActionPolicy().validateDocument(
      _document([documentAction]),
      isSigned: isSigned,
    ),
  );
  final runtimeError = _capturePolicyFailure(
    () => const RemoteManifestPolicy().validate(
      _manifest([runtimeAction]),
      isSigned: isSigned,
    ),
  );

  expect(documentError.code, code, reason: name);
  expect(documentError.message, message, reason: name);
  expect(runtimeError.code, code, reason: name);
  expect(runtimeError.message, message, reason: name);
}
