import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/platform/android_market_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidMarketRegistry', () {
    test('contains Huawei registry entry', () {
      _expectMarket(
        AndroidMarketKind.huawei,
        packageName: 'com.huawei.appmarket',
      );
    });

    test('contains Honor registry entry', () {
      _expectMarket(
        AndroidMarketKind.honor,
        packageName: 'com.hihonor.appmarket',
      );
    });

    test('contains Xiaomi registry entry', () {
      _expectMarket(
        AndroidMarketKind.xiaomi,
        packageName: 'com.xiaomi.market',
      );
    });

    test('contains OPPO registry entry', () {
      _expectMarket(
        AndroidMarketKind.oppo,
        packageName: 'com.oppo.market',
      );
    });

    test('contains vivo registry entry', () {
      _expectMarket(
        AndroidMarketKind.vivo,
        packageName: 'com.bbk.appstore',
      );
    });

    test('contains Meizu registry entry', () {
      _expectMarket(
        AndroidMarketKind.meizu,
        packageName: 'com.meizu.mstore',
      );
    });

    test('contains Tencent MyApp registry entry', () {
      _expectMarket(
        AndroidMarketKind.tencentMyApp,
        packageName: 'com.tencent.android.qqdownloader',
      );
    });

    test('uses action fallback URL before descriptor fallback URL', () {
      final action = OpenAndroidMarketAction(
        market: AndroidMarketKind.xiaomi,
        targetPackageName: 'com.example.app',
        fallbackUrl: Uri.parse(
          'https://custom.example.com/apps/com.example.app',
        ),
      );

      expect(
        AndroidMarketRegistry.fallbackUrlFor(action),
        Uri.parse('https://custom.example.com/apps/com.example.app'),
      );
    });

    test('uses descriptor fallback URL when action does not provide one', () {
      const action = OpenAndroidMarketAction(
        market: AndroidMarketKind.xiaomi,
        targetPackageName: 'com.example.app',
      );

      expect(
        AndroidMarketRegistry.fallbackUrlFor(action),
        Uri.parse('https://app.mi.com/details?id=com.example.app'),
      );
    });
  });
}

void _expectMarket(
  AndroidMarketKind market, {
  required String packageName,
}) {
  final descriptor = AndroidMarketRegistry.requireDescriptor(market);

  expect(descriptor.market, market);
  expect(descriptor.marketPackageName, packageName);
  expect(descriptor.uriTemplate, contains('{targetPackageName}'));
  expect(
    descriptor.marketUriFor('com.example.app').toString(),
    contains('com.example.app'),
  );
}
