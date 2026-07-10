import 'package:flutter_app_updater/src/channel/flutter_app_updater_method_channel.dart';
import 'package:flutter_app_updater_example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native plugin responds through the real method channel',
      (tester) async {
    final platformVersion =
        await MethodChannelFlutterAppUpdater().getPlatformVersion();

    expect(platformVersion, isNotEmpty);
  });

  testWidgets('safe update simulator launches without external effects',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Update Simulator'), findsWidgets);
    expect(find.text('SAFE SIMULATION'), findsOneWidget);
    expect(find.text('Check for update'), findsOneWidget);
  });
}
