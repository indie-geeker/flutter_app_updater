import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

UpdateCandidate release(String version, List<UpdateAction> actions,
        {TargetPlatform platform = TargetPlatform.android,
        UpdatePolicy policy = const UpdatePolicy()}) =>
    UpdateCandidate(
      version: version,
      channel: 'stable',
      platform: platform,
      releaseNotes: 'audit',
      policy: policy,
      actions: actions,
    );
AppUpdater updater(
  List<UpdateCandidate> releases, {
  TargetPlatform platform = TargetPlatform.android,
  UpdateDistributionPolicy policy = UpdateDistributionPolicy.any,
  List<UpdateActionExecutor>? executors,
  UpdateSelectionPolicy selectionPolicy = UpdateSelectionPolicy.latestRelease,
}) =>
    AppUpdater(
      source: UpdateSource.staticManifest(
          manifest: UpdateManifest(
        schemaVersion: 3,
        appId: 'com.example.app',
        channel: 'stable',
        releases: releases,
      )),
      selector: UpdateSelector(
          installedVersion: '1.0.0', platform: platform, channel: 'stable'),
      platform: platform,
      distributionPolicy: policy,
      executors: executors,
      selectionPolicy: selectionPolicy,
    );
DownloadPackageAction artifact(
        {String hash =
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'}) =>
    DownloadPackageAction(
      packageUrl: Uri.parse('https://example.com/app.apk'),
      packageType: PackageType.apk,
      packageSizeBytes: 3,
      sha256: hash,
    );

class Recorder implements UpdateActionExecutor {
  int calls = 0;
  @override
  bool supports(UpdateAction action) => true;
  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    calls++;
    return const UpdateActionResult.success();
  }
}

void main() {
  final store = OpenStoreAction(
      store: StoreKind.googlePlay,
      storeUrl: Uri.parse(
          'https://play.google.com/store/apps/details?id=com.example.app'));
  test('explicit latestExecutable selects the older allowed update', () async {
    final result = await updater([
      release('3.0.0', [artifact()]),
      release('2.0.0', [store])
    ],
            policy: UpdateDistributionPolicy.storeOnly,
            selectionPolicy: UpdateSelectionPolicy.latestExecutable)
        .check();
    expect(result, isA<UpdateAvailable>());
    expect((result as UpdateAvailable).candidate.version, '2.0.0');
  });
  for (final policy in [
    const UpdatePolicy(level: UpdatePolicyLevel.required),
    const UpdatePolicy(minSupportedVersion: '2.0.0')
  ]) {
    test('fallback does not bypass support policy $policy', () async {
      final result = await updater([
        release('3.0.0', [artifact()], policy: policy),
        release('2.0.0', [store])
      ],
              policy: UpdateDistributionPolicy.storeOnly,
              selectionPolicy: UpdateSelectionPolicy.latestExecutable)
          .check();
      expect((result as UpdateCheckFailed).code,
          UpdateErrorCode.noSupportedAction);
    });
  }
  test('default selection retains latest release behavior', () async {
    final result = await updater([
      release('3.0.0', [artifact()]),
      release('2.0.0', [store])
    ], policy: UpdateDistributionPolicy.storeOnly)
        .check();
    expect(
        (result as UpdateCheckFailed).code, UpdateErrorCode.noSupportedAction);
  });
  test('prepared actions and candidates are immutable snapshots', () async {
    final input = <UpdateAction>[store];
    final result = await updater([release('2.0.0', input)]).checkAndPrepare()
        as PreparedUpdateAvailable;
    input[0] = artifact();
    expect(result.candidate.actions.single, same(store));
    expect(() => result.actions[0] = artifact(), throwsUnsupportedError);
    expect(
        () => result.candidate.actions[0] = artifact(), throwsUnsupportedError);
  });
  test('canceling on Started prevents regular executor handoff', () async {
    final recorder = Recorder();
    final token = UpdateActionCancelToken();
    final events = <UpdateActionEvent>[];
    await for (final event in updater([], executors: [recorder])
        .performStream(store, cancelToken: token)) {
      events.add(event);
      if (event is UpdateActionStarted) token.cancel();
    }
    expect(recorder.calls, 0);
    expect((events.last as UpdateActionCompleted).result.code,
        UpdateErrorCode.actionCanceled);
  });

  test('per-check selector cannot change the execution platform', () async {
    final result = await updater([]).check(
        selector: const UpdateSelector(
            installedVersion: '1.0.0',
            platform: TargetPlatform.iOS,
            channel: 'stable'));
    expect((result as UpdateCheckFailed).code,
        UpdateErrorCode.configurationInvalid);
  });
  test('iOS default capability rejects APK download', () async {
    final result = await updater([
      release('2.0.0', [artifact()], platform: TargetPlatform.iOS)
    ], platform: TargetPlatform.iOS)
        .check();
    expect(result, isA<UpdateCheckFailed>());
    expect(
        (result as UpdateCheckFailed).code, UpdateErrorCode.noSupportedAction);
  });
  test('pre-canceled non-streaming action does not execute', () async {
    final recorder = Recorder();
    final instance = updater([], executors: [recorder]);
    final events = await instance
        .performStream(artifact(),
            cancelToken: UpdateActionCancelToken()..cancel())
        .toList();
    expect(recorder.calls, 0);
    expect((events.last as UpdateActionCompleted).result.code,
        UpdateErrorCode.actionCanceled);
  });
}
