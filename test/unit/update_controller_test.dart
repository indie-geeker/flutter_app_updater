import 'package:flutter_app_updater/src/controller/update_controller.dart';
import 'package:flutter_app_updater/src/models/update_check_result.dart';
import 'package:flutter_app_updater/src/models/update_error.dart';
import 'package:flutter_app_updater/src/models/update_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateController', () {
    test('checkForUpdateResult returns available result', () async {
      final controller = UpdateController(
        currentVersion: '1.0.0',
        onCheckUpdate: () async => {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
        },
      );

      final result = await controller.checkForUpdateResult();

      expect(result.outcome, UpdateCheckOutcome.available);
      expect(result.updateInfo?.newVersion, '2.0.0');
      expect(result.error, isNull);
      expect(controller.status, UpdateStatus.available);
    });

    test('checkForUpdateResult distinguishes not available from failed',
        () async {
      final controller = UpdateController(
        currentVersion: '2.0.0',
        onCheckUpdate: () async => {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
        },
      );

      final result = await controller.checkForUpdateResult();

      expect(result.outcome, UpdateCheckOutcome.notAvailable);
      expect(result.updateInfo, isNull);
      expect(result.error, isNull);
      expect(controller.status, UpdateStatus.notAvailable);
    });

    test('checkForUpdateResult returns failed result with error details',
        () async {
      final controller = UpdateController(
        currentVersion: '1.0.0',
        onCheckUpdate: () async => {
          'version': 'invalid version',
          'downloadUrl': 'https://example.com/app.apk',
        },
      );

      final result = await controller.checkForUpdateResult();

      expect(result.outcome, UpdateCheckOutcome.failed);
      expect(result.updateInfo, isNull);
      expect(result.error?.code, 'INVALID_VERSION');
      expect(controller.error?.code, 'INVALID_VERSION');
      expect(controller.status, UpdateStatus.error);
    });

    test('legacy checkForUpdate returns null on failure while storing error',
        () async {
      final controller = UpdateController(
        currentVersion: '1.0.0',
        onCheckUpdate: () async => throw const UpdateError(
          code: 'CUSTOM_ERROR',
          message: 'Custom failure',
        ),
      );

      final updateInfo = await controller.checkForUpdate();

      expect(updateInfo, isNull);
      expect(controller.error?.code, 'CUSTOM_ERROR');
      expect(controller.status, UpdateStatus.error);
    });
  });
}
