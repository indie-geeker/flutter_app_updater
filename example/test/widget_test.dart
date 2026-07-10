import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app_updater_example/main.dart';

void main() {
  testWidgets('preview demonstrates a required update without network access',
      (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Safe preview'), findsOneWidget);
    expect(find.textContaining('never downloads or installs'), findsOneWidget);

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.text('Policy: Required'), findsOneWidget);
    expect(find.textContaining('Download and install apk'), findsWidgets);
    expect(find.text('Run simulated action'), findsOneWidget);

    await tester.tap(find.text('Run simulated action'));
    await tester.pump(const Duration(milliseconds: 45));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Cancel action'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Preview completed safely'), findsOneWidget);
  });

  testWidgets('remote mode requires explicit manifest and application identity',
      (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Remote manifest'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manifest-url-field')), findsOneWidget);
    expect(find.byKey(const Key('expected-app-id-field')), findsOneWidget);
    expect(find.byKey(const Key('installed-version-field')), findsOneWidget);
    expect(find.textContaining('Direct install requires'), findsOneWidget);
  });

  testWidgets('preview action can be canceled with a structured result',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run simulated action'));
    await tester.pump(const Duration(milliseconds: 45));

    await tester.tap(find.text('Cancel action'));
    await tester.pumpAndSettle();

    expect(find.text('Canceled: ACTION_CANCELED'), findsOneWidget);
  });
}
