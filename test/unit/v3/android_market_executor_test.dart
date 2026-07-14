import 'package:flutter/services.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_method_channel.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AndroidMarketExecutor', () {
    test('reports support only on Android', () {
      const action = OpenAndroidMarketAction(
        market: AndroidMarketKind.xiaomi,
        targetPackageName: 'com.example.app',
      );

      expect(
        AndroidMarketExecutor(targetPlatform: TargetPlatform.android)
            .supports(action),
        isTrue,
      );
      expect(
        AndroidMarketExecutor(targetPlatform: TargetPlatform.iOS)
            .supports(action),
        isFalse,
      );
    });

    test('supports only OpenAndroidMarketAction', () {
      final executor = AndroidMarketExecutor(
        platform: _FakeMarketPlatform(),
        targetPlatform: TargetPlatform.android,
      );

      expect(
        executor.supports(
          const OpenAndroidMarketAction(
            market: AndroidMarketKind.xiaomi,
            targetPackageName: 'com.example.app',
          ),
        ),
        isTrue,
      );
      expect(
        executor.supports(
          OpenStoreAction(
            store: StoreKind.googlePlay,
            storeUrl: Uri.parse(
              'https://play.google.com/store/apps/details?id=com.example.app',
            ),
          ),
        ),
        isFalse,
      );
    });

    test('builds market descriptor URI and fallback URL', () async {
      final platform = _FakeMarketPlatform();
      final executor = AndroidMarketExecutor(
        platform: platform,
        targetPlatform: TargetPlatform.android,
      );
      const action = OpenAndroidMarketAction(
        market: AndroidMarketKind.xiaomi,
        targetPackageName: 'com.example.app',
      );

      final result = await executor.perform(action);

      expect(result.isSuccess, isTrue);
      expect(platform.calls, [
        (
          marketPackageName: 'com.xiaomi.market',
          marketUri: 'market://details?id=com.example.app',
          targetPackageName: 'com.example.app',
          fallbackUrl: 'https://app.mi.com/details?id=com.example.app',
        ),
      ]);
    });

    test('uses action fallback URL before registry fallback URL', () async {
      final platform = _FakeMarketPlatform();
      final executor = AndroidMarketExecutor(
        platform: platform,
        targetPlatform: TargetPlatform.android,
      );
      final action = OpenAndroidMarketAction(
        market: AndroidMarketKind.xiaomi,
        targetPackageName: 'com.example.app',
        fallbackUrl: Uri.parse('https://example.com/custom'),
      );

      await executor.perform(action);

      expect(platform.calls.single.fallbackUrl, 'https://example.com/custom');
    });

    test('maps MARKET_NOT_AVAILABLE to marketNotAvailable', () async {
      final executor = AndroidMarketExecutor(
        platform: _FakeMarketPlatform(
          failure: PlatformException(
            code: 'MARKET_NOT_AVAILABLE',
            message: 'No market app.',
          ),
        ),
        targetPlatform: TargetPlatform.android,
      );
      const action = OpenAndroidMarketAction(
        market: AndroidMarketKind.xiaomi,
        targetPackageName: 'com.example.app',
      );

      final result = await executor.perform(action);

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.marketNotAvailable);
    });

    test('rejects blank target package names', () async {
      final platform = _FakeMarketPlatform();
      final executor = AndroidMarketExecutor(
        platform: platform,
        targetPlatform: TargetPlatform.android,
      );
      const action = OpenAndroidMarketAction(
        market: AndroidMarketKind.xiaomi,
        targetPackageName: ' ',
      );

      final result = await executor.perform(action);

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.missingRequiredField);
      expect(platform.calls, isEmpty);
    });
  });

  group('MethodChannelFlutterAppUpdater.openAndroidMarket', () {
    const channel = MethodChannel('flutter_app_updater');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('invokes openAndroidMarket with descriptor arguments', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      await MethodChannelFlutterAppUpdater().openAndroidMarket(
        marketPackageName: 'com.xiaomi.market',
        marketUri: 'market://details?id=com.example.app',
        targetPackageName: 'com.example.app',
        fallbackUrl: 'https://app.mi.com/details?id=com.example.app',
      );

      expect(calls.single.method, 'openAndroidMarket');
      expect(calls.single.arguments, {
        'marketPackageName': 'com.xiaomi.market',
        'marketUri': 'market://details?id=com.example.app',
        'targetPackageName': 'com.example.app',
        'fallbackUrl': 'https://app.mi.com/details?id=com.example.app',
      });
    });
  });
}

class _FakeMarketPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements FlutterAppUpdaterPlatform {
  final PlatformException? failure;
  final calls = <({
    String marketPackageName,
    String marketUri,
    String targetPackageName,
    String? fallbackUrl,
  })>[];

  _FakeMarketPlatform({
    this.failure,
  });

  @override
  Future<void> openAndroidMarket({
    required String marketPackageName,
    required String marketUri,
    required String targetPackageName,
    String? fallbackUrl,
  }) async {
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    calls.add((
      marketPackageName: marketPackageName,
      marketUri: marketUri,
      targetPackageName: targetPackageName,
      fallbackUrl: fallbackUrl,
    ));
  }
}
