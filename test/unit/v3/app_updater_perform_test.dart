import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdater.perform', () {
    test('delegates OpenStoreAction to a supporting executor', () async {
      final executor = _RecordingExecutor(
        supportsAction: (action) => action is OpenStoreAction,
      );
      final action = OpenStoreAction(
        store: StoreKind.googlePlay,
        storeUrl: Uri.parse(
          'https://play.google.com/store/apps/details?id=com.example.app',
        ),
      );
      final updater = _updater(executors: [executor]);

      final result = await updater.perform(action);

      expect(result.isSuccess, isTrue);
      expect(executor.performedActions, [same(action)]);
    });

    test('delegates DownloadPackageAction to a supporting executor', () async {
      final executor = _RecordingExecutor(
        supportsAction: (action) => action is DownloadPackageAction,
      );
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        sha256: 'a' * 64,
      );
      final updater = _updater(executors: [executor]);

      final result = await updater.perform(action);

      expect(result.isSuccess, isTrue);
      expect(executor.performedActions, [same(action)]);
    });

    test('returns structured failure for unsupported actions', () async {
      const action = OpenAndroidMarketAction(
        market: AndroidMarketKind.huawei,
        targetPackageName: 'com.example.app',
      );
      final updater = _updater(executors: const []);

      final result = await updater.perform(action);

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.noSupportedAction);
    });

    test('public barrel exports executor API', () async {
      final executor = _RecordingExecutor(
        supportsAction: (action) => action is OpenStoreAction,
      );

      expect(executor, isA<UpdateActionExecutor>());
      expect(const UpdateActionResult.success().isSuccess, isTrue);
    });
  });
}

AppUpdater _updater({
  required List<UpdateActionExecutor> executors,
}) {
  return AppUpdater(
    source: UpdateSource.manifest(
      manifestUrl: Uri.parse('https://example.com/update.json'),
    ),
    executors: executors,
  );
}

class _RecordingExecutor implements UpdateActionExecutor {
  final bool Function(UpdateAction action) supportsAction;
  final performedActions = <UpdateAction>[];

  _RecordingExecutor({
    required this.supportsAction,
  });

  @override
  bool supports(UpdateAction action) => supportsAction(action);

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    performedActions.add(action);
    return const UpdateActionResult.success();
  }
}
