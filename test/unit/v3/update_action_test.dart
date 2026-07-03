import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateAction', () {
    test('models official store opening with storeUrl', () {
      final action = OpenStoreAction(
        store: StoreKind.appStore,
        storeUrl: Uri.parse('https://apps.apple.com/app/id123456789'),
      );

      expect(action.store, StoreKind.appStore);
      expect(action.storeUrl.host, 'apps.apple.com');
    });

    test('models Google Play in-app updates', () {
      const action = PlayInAppUpdateAction(mode: PlayUpdateMode.immediate);

      expect(action.mode, PlayUpdateMode.immediate);
    });

    test('models Chinese Android market jumps', () {
      final action = OpenAndroidMarketAction(
        market: AndroidMarketKind.xiaomi,
        targetPackageName: 'com.example.app',
        fallbackUrl: Uri.parse(
          'https://app.mi.com/details?id=com.example.app',
        ),
      );

      expect(action.market, AndroidMarketKind.xiaomi);
      expect(action.targetPackageName, 'com.example.app');
      expect(action.fallbackUrl, isNotNull);
    });

    test('models direct package downloads with packageUrl and sha256', () {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 25600000,
        sha256: 'b' * 64,
        signature: 'package-signature',
      );

      expect(action.packageUrl.path, '/app.apk');
      expect(action.packageType, PackageType.apk);
      expect(action.packageSizeBytes, 25600000);
      expect(action.sha256, 'b' * 64);
      expect(action.signature, 'package-signature');
    });

    test('models desktop installers with installerUrl and sha256', () {
      final action = OpenInstallerAction(
        installerUrl: Uri.parse('https://example.com/app.dmg'),
        installerType: InstallerType.dmg,
        installerSizeBytes: 82000000,
        sha256: 'c' * 64,
      );

      expect(action.installerUrl.path, '/app.dmg');
      expect(action.installerType, InstallerType.dmg);
      expect(action.installerSizeBytes, 82000000);
      expect(action.sha256, 'c' * 64);
      expect(action.signature, isNull);
    });
  });
}
