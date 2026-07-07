import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app_updater/flutter_app_updater_ui.dart';
import 'package:flutter_app_updater/src/ui/update_flow_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'default dialog shows progress and disables dismiss for required updates',
    (tester) async {
      final updater = _FakeStreamingUpdater();
      final update = _preparedUpdate(isRequired: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showUpdateFlowDialog(
                  context: context,
                  updater: updater,
                  update: update,
                );
              },
              child: const Text('update'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('update'));
      await tester.pumpAndSettle();
      await updater.ready;

      updater.emit(
        const UpdateDownloadProgress(receivedBytes: 50, totalBytes: 100),
      );
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('50'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    },
  );

  testWidgets('optional updates show cancel action', (tester) async {
    final updater = _FakeStreamingUpdater();
    final update = _preparedUpdate(isRequired: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              showUpdateFlowDialog(
                context: context,
                updater: updater,
                update: update,
              );
            },
            child: const Text('update'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('update'));
    await tester.pumpAndSettle();
    await updater.ready;

    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(updater.wasCanceled, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('dialog can render deterministic controller state',
      (tester) async {
    final updater = _FakeStreamingUpdater();
    final update = _preparedUpdate(isRequired: false);
    final controller = UpdateFlowController(
      updater: updater,
      update: update,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UpdateFlowDialog(
          controller: controller,
          builder: (context, state) {
            final percent = ((state.progress ?? 0) * 100).round();
            return Text('progress:$percent');
          },
        ),
      ),
    );

    updater.emit(
      const UpdateDownloadProgress(receivedBytes: 25, totalBytes: 100),
    );
    await tester.pump();

    expect(find.text('progress:25'), findsOneWidget);
  });
}

PreparedUpdateAvailable _preparedUpdate({required bool isRequired}) {
  return PreparedUpdateAvailable(
    candidate: UpdateCandidate(
      version: '2.0.0',
      channel: 'stable',
      platform: TargetPlatform.android,
      releaseNotes: 'Bug fixes',
      policy: const UpdatePolicy(level: UpdatePolicyLevel.recommended),
      actions: [
        DownloadPackageAction(
          packageUrl: Uri.parse('https://example.com/app.apk'),
          packageType: PackageType.apk,
          packageSizeBytes: 100,
        ),
      ],
    ),
    recommendedAction: DownloadPackageAction(
      packageUrl: Uri.parse('https://example.com/app.apk'),
      packageType: PackageType.apk,
      packageSizeBytes: 100,
    ),
    actions: [
      DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 100,
      ),
    ],
    isRequired: isRequired,
  );
}

class _FakeStreamingUpdater extends AppUpdater {
  late final StreamController<UpdateActionEvent> _events;
  final _ready = Completer<void>();
  var wasCanceled = false;

  _FakeStreamingUpdater()
      : super(
          source: const UpdateSource.staticManifest(
            manifest: UpdateManifest(
              schemaVersion: 3,
              appId: 'com.example.app',
              channel: 'stable',
              releases: [],
            ),
          ),
        ) {
    _events = StreamController<UpdateActionEvent>(
      sync: true,
      onListen: () {
        if (!_ready.isCompleted) {
          _ready.complete();
        }
      },
      onCancel: () {
        wasCanceled = true;
      },
    );
  }

  Future<void> get ready => _ready.future;

  void emit(UpdateActionEvent event) {
    _events.add(event);
  }

  @override
  Stream<UpdateActionEvent> performStream(UpdateAction action) {
    return _events.stream;
  }
}
