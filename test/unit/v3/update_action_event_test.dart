import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancel token exposes one idempotent cancellation signal', () async {
    final token = UpdateActionCancelToken();
    var completions = 0;
    token.whenCanceled.then((_) => completions++);

    token.cancel();
    token.cancel();
    await token.whenCanceled;

    expect(token.isCanceled, isTrue);
    expect(completions, 1);
  });

  test('progress exposes a bounded fraction when total size is known', () {
    final action = DownloadPackageAction(
      packageUrl: Uri.parse('https://example.com/app.apk'),
      packageType: PackageType.apk,
      packageSizeBytes: 42,
      sha256: 'a' * 64,
    );

    expect(
      UpdateActionProgress(
        action: action,
        downloadedBytes: 5,
        totalBytes: 10,
      ).fraction,
      0.5,
    );
    expect(
      UpdateActionProgress(
        action: action,
        downloadedBytes: 12,
        totalBytes: 10,
      ).fraction,
      1,
    );
    expect(
      UpdateActionProgress(
        action: action,
        downloadedBytes: 5,
      ).fraction,
      isNull,
    );
  });
}
