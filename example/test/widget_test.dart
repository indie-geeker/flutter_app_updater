import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app_updater_example/main.dart';

void main() {
  testWidgets('shows the v3 update flow', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Flutter App Updater v3'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Update 2.0.0'), findsOneWidget);
    expect(find.text('Perform recommended action'), findsOneWidget);
  });
}
