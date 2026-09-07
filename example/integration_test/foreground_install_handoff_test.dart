import 'dart:io';
import 'dart:isolate';
import 'package:flutter_app_updater/src/download/package_download_lock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_updater_example/production/production_app_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android native ownership excludes a second isolate',
      (tester) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/native-lock-probe.apk';
    final first = await PackageDownloadLock.tryAcquire(path);
    expect(first, isNotNull);
    try {
      final acquired = await Isolate.run(() async {
        final contender = await PackageDownloadLock.tryAcquire(path);
        await contender?.release();
        return contender != null;
      });
      expect(acquired, isFalse);
    } finally {
      await first!.release();
    }
    final next = await PackageDownloadLock.tryAcquire(path);
    expect(next, isNotNull);
    await next!.release();
  }, skip: !Platform.isAndroid);
  testWidgets('production APK directory can be read through real FileProvider',
      (tester) async {
    final metadata = await const PluginProductionRuntimeLoader().load();
    final dir = Directory(metadata.downloadDirectory);
    await dir.create(recursive: true);
    final fixture = File('${dir.path}/provider-verification.apk');
    await fixture.writeAsBytes([1, 2, 3]);
    const channel = MethodChannel('updater_example/verification');
    try {
      final uri = await channel
          .invokeMethod<String>('verifyFileProvider', {'path': fixture.path});
      expect(uri, startsWith('content://'));
      final support = await getApplicationSupportDirectory();
      final outside = File('${support.path}/provider-outside-fixture.apk');
      await outside.writeAsBytes([1]);
      try {
        await expectLater(
            channel.invokeMethod<String>(
                'verifyFileProvider', {'path': outside.path}),
            throwsA(isA<PlatformException>()
                .having((e) => e.code, 'code', 'PATH_NOT_SHAREABLE')));
      } finally {
        await outside.delete();
      }
    } finally {
      await fixture.delete();
    }
  }, skip: !Platform.isAndroid);
}
