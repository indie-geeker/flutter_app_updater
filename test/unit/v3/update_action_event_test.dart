import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateActionEvent', () {
    test('download progress exposes received and optional total bytes', () {
      const event = UpdateDownloadProgress(
        receivedBytes: 512,
        totalBytes: 1024,
      );

      expect(event.receivedBytes, 512);
      expect(event.totalBytes, 1024);
      expect(event.progress, 0.5);
    });

    test('download progress is null when total bytes are unknown', () {
      const event = UpdateDownloadProgress(
        receivedBytes: 512,
        totalBytes: null,
      );

      expect(event.progress, isNull);
    });

    test('cancel token invokes registered callbacks once', () {
      final token = UpdateActionCancelToken();
      var calls = 0;
      token.onCancel(() => calls++);

      token.cancel();
      token.cancel();

      expect(token.isCanceled, isTrue);
      expect(calls, 1);
    });
  });
}
