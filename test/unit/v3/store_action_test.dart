import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_platform_interface.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_app_updater/src/platform/store_update_executor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  late FlutterAppUpdaterPlatform previousPlatform;
  late _FakeStorePlatform fakePlatform;

  setUp(() {
    previousPlatform = FlutterAppUpdaterPlatform.instance;
    fakePlatform = _FakeStorePlatform();
    FlutterAppUpdaterPlatform.instance = fakePlatform;
  });

  tearDown(() {
    FlutterAppUpdaterPlatform.instance = previousPlatform;
  });

  group('StoreUpdateExecutor', () {
    test('OpenStoreAction delegates to the platform executor', () async {
      final action = OpenStoreAction(
        store: StoreKind.googlePlay,
        storeUrl: Uri.parse(
          'https://play.google.com/store/apps/details?id=com.example.app',
        ),
      );

      final result = await StoreUpdateExecutor().perform(action);

      expect(result.isSuccess, isTrue);
      expect(fakePlatform.openedStores, [
        (
          store: StoreKind.googlePlay.name,
          storeUrl:
              'https://play.google.com/store/apps/details?id=com.example.app',
        ),
      ]);
    });

    test('PlayInAppUpdateAction delegates to the platform executor', () async {
      const action = PlayInAppUpdateAction(mode: PlayUpdateMode.immediate);

      final result = await StoreUpdateExecutor().perform(action);

      expect(result.isSuccess, isTrue);
      expect(fakePlatform.startedPlayModes, [PlayUpdateMode.immediate.name]);
    });

    test('invalid store URL returns structured failure', () async {
      final action = OpenStoreAction(
        store: StoreKind.appStore,
        storeUrl: Uri(),
      );

      final result = await StoreUpdateExecutor().perform(action);

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.manifestInvalid);
      expect(fakePlatform.openedStores, isEmpty);
    });

    test('non-store action is rejected by store executor', () async {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        sha256: 'a' * 64,
      );

      final result = await StoreUpdateExecutor().perform(action);

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.noSupportedAction);
    });
  });
}

class _FakeStorePlatform extends Fake
    with MockPlatformInterfaceMixin
    implements FlutterAppUpdaterPlatform {
  final openedStores = <({String store, String storeUrl})>[];
  final startedPlayModes = <String>[];

  @override
  Future<void> openStore({
    required String store,
    required String storeUrl,
  }) async {
    openedStores.add((store: store, storeUrl: storeUrl));
  }

  @override
  Future<void> startPlayInAppUpdate({
    required String mode,
  }) async {
    startedPlayModes.add(mode);
  }
}
