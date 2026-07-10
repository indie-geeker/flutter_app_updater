import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native plugin responds through the real method channel',
      (WidgetTester tester) async {
    final platformVersion =
        await MethodChannelFlutterAppUpdater().getPlatformVersion();

    expect(platformVersion, isNotEmpty);
  });

  testWidgets('checks and performs a v3 update action',
      (WidgetTester tester) async {
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
    final executor = _RecordingExecutor();
    final updater = AppUpdater(
      source: UpdateSource.staticManifest(
        manifest: UpdateManifest(
          schemaVersion: 3,
          appId: 'com.example.app',
          channel: 'stable',
          releases: [candidate],
        ),
      ),
      selector: const UpdateSelector(
        installedVersion: '2.0.0',
        platform: TargetPlatform.android,
        channel: 'stable',
      ),
      executors: [executor],
    );

    final result = await updater.check();

    expect(result, isA<UpdateAvailable>());
    final recommendedAction = (result as UpdateAvailable).recommendedAction;
    expect(recommendedAction, same(packageAction));

    final actionResult = await updater.perform(recommendedAction);

    expect(actionResult.isSuccess, isTrue);
    expect(executor.actions, [same(packageAction)]);
  });
}

class _RecordingExecutor implements UpdateActionExecutor {
  final actions = <UpdateAction>[];

  @override
  bool supports(UpdateAction action) => action is DownloadPackageAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    actions.add(action);
    return const UpdateActionResult.success();
  }
}
