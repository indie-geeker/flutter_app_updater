import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public library exports documented integration types', () {
    final updater = FlutterAppUpdater(currentVersion: '1.0.0');
    final updateInfo = UpdateInfo(
      newVersion: '2.0.0',
      downloadUrl: 'https://example.com/app.apk',
      changelog: 'Bug fixes',
    );
    const error = UpdateError(code: 'TEST', message: 'test');
    const progress = UpdateProgress(downloaded: 1, total: 2);
    const retryStrategy = RetryStrategy.disabled;

    expect(updater.controller, isA<UpdateController>());
    expect(updateInfo.newVersion, '2.0.0');
    expect(error.code, 'TEST');
    expect(progress.progressPercentage, 50);
    expect(retryStrategy.maxAttempts, 0);
    expect(UpdateStatus.idle.name, 'idle');
    expect(VersionComparator.hasUpdate('1.0.0', '2.0.0'), isTrue);
  });
}
