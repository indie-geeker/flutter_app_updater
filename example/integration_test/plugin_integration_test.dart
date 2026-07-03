import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('selects a v3 update action', (WidgetTester tester) async {
    final packageAction = DownloadPackageAction(
      packageUrl: Uri.parse('https://example.com/app.apk'),
      packageType: PackageType.apk,
      sha256: 'a' * 64,
    );
    final candidate = UpdateCandidate(
      version: '3.0.0',
      channel: 'stable',
      platform: TargetPlatform.android,
      releaseNotes: 'v3',
      policy: const UpdatePolicy(level: UpdatePolicyLevel.required),
      actions: [packageAction],
    );
    const selector = UpdateSelector(
      installedVersion: '2.0.0',
      platform: TargetPlatform.android,
      channel: 'stable',
    );

    final result = selector.select([candidate]);

    expect(result, isA<UpdateAvailable>());
    expect(
      (result as UpdateAvailable).recommendedAction,
      same(packageAction),
    );
  });
}
