import 'dart:io';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('UPDATER_NETWORK_TEST_URL');
  testWidgets('sandbox permits a real bounded HTTPS fetch', (tester) async {
    final fetched =
        await const IoManifestFetcher(retryStrategy: RetryStrategy.disabled)
            .fetch(ManifestUpdateSource(
                manifestUrl: Uri.parse(endpoint),
                expectedAppId: 'verification.transport'));
    expect(fetched.bodyBytes, isNotEmpty);
    expect(fetched.finalUri.scheme, 'https');
  }, skip: !Platform.isMacOS || endpoint.isEmpty);
}
