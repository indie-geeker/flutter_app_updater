import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateActionEvent', () {
    test('progress exposes a fraction when total bytes are known', () {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
      );

      final progress = UpdateActionProgress(
        action: action,
        downloadedBytes: 5,
        totalBytes: 10,
      );

      expect(progress.fraction, 0.5);
    });

    test('progress fraction is null when total bytes are unknown', () {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
      );

      final progress = UpdateActionProgress(
        action: action,
        downloadedBytes: 5,
      );

      expect(progress.fraction, isNull);
    });
  });
}
