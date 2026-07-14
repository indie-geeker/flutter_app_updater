import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater_example/production/production_app_metadata.dart';
import 'package:flutter_app_updater_example/production/production_update_configuration.dart';
import 'package:flutter_app_updater_example/production/production_update_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled configuration never loads metadata or constructs updater',
      () async {
    final loader = _FakeRuntimeLoader(_metadata());
    final factory = _CountingFactory();
    final controller = ProductionUpdateController(
      configuration: ProductionUpdateConfiguration.parse(),
      runtimeLoader: loader,
      updaterFactory: factory,
    );
    addTearDown(controller.dispose);

    await controller.checkForUpdate();

    expect(controller.phase, ProductionPhase.disabled);
    expect(loader.calls, 0);
    expect(factory.calls, 0);
  });

  test('signed manifest exercises fetch verify parse select and prepare',
      () async {
    final fixture = await _fixture();
    final controller = fixture.controller;
    addTearDown(controller.dispose);

    await controller.checkForUpdate();

    expect(controller.phase, ProductionPhase.updateAvailable);
    expect(controller.preparedUpdate?.candidate.version, '2.0.0');
    expect(
      controller.preparedUpdate?.recommendedAction,
      isA<OpenStoreAction>(),
    );
    expect(fixture.fetcher.calls, 1);
    expect(fixture.executor.performCalls, 0);
  });

  test('declining confirmation executes nothing', () async {
    final fixture = await _fixture();
    final controller = fixture.controller;
    addTearDown(controller.dispose);
    await controller.checkForUpdate();

    controller.declineRecommendedAction();

    expect(controller.phase, ProductionPhase.updateAvailable);
    expect(fixture.executor.performCalls, 0);
  });

  test('confirming executes exactly one recommended action', () async {
    final fixture = await _fixture();
    final controller = fixture.controller;
    addTearDown(controller.dispose);
    await controller.checkForUpdate();

    await controller.performRecommended();

    expect(controller.phase, ProductionPhase.succeeded);
    expect(fixture.executor.performCalls, 1);
    expect(fixture.executor.actions.single, isA<OpenStoreAction>());
  });

  test('runtime package mismatch becomes a structured failure', () async {
    final loader = _FakeRuntimeLoader(
      _metadata(appId: 'com.example.other'),
    );
    final factory = _CountingFactory();
    final controller = ProductionUpdateController(
      configuration: _configuration(),
      runtimeLoader: loader,
      updaterFactory: factory,
    );
    addTearDown(controller.dispose);

    await controller.checkForUpdate();

    expect(controller.phase, ProductionPhase.failed);
    expect(controller.errorCode, UpdateErrorCode.configurationInvalid);
    expect(controller.message, contains('runtime package'));
    expect(factory.calls, 0);
  });
}

Future<_Fixture> _fixture() async {
  final envelope = await _signedManifest();
  final fetcher = _FakeManifestFetcher(envelope);
  final executor = _RecordingExecutor();
  final factory = DefaultProductionUpdaterFactory(
    manifestFetcher: fetcher,
    executors: [executor],
    targetPlatform: TargetPlatform.android,
  );
  final controller = ProductionUpdateController(
    configuration: _configuration(),
    runtimeLoader: _FakeRuntimeLoader(_metadata()),
    updaterFactory: factory,
  );
  return _Fixture(controller, fetcher, executor);
}

ProductionUpdateConfiguration _configuration() {
  return ProductionUpdateConfiguration.parse(
    enabled: true,
    manifestUrl: 'https://updates.example.com/manifest.json',
    expectedAppId: 'com.example.app',
    channel: 'stable',
    architecture: 'arm64',
    publicKeysJson: jsonEncode({'release-rfc': _publicKeyBase64}),
  );
}

ProductionAppMetadata _metadata({
  String appId = 'com.example.app',
}) {
  return ProductionAppMetadata(
    version: '1.0.0',
    buildNumber: '10',
    appId: appId,
    downloadDirectory: '/simulated/application-support/updates',
  );
}

Future<Uint8List> _signedManifest() {
  final now = DateTime.now().toUtc();
  final payload = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'schemaVersion': 3,
        'appId': 'com.example.app',
        'channel': 'stable',
        'releases': [
          {
            'version': '2.0.0',
            'buildNumber': '20',
            'platform': 'android',
            'architecture': 'arm64',
            'releaseNotes': 'Production integration fixture.',
            'policy': {'level': 'recommended'},
            'actions': [
              {
                'type': 'openStore',
                'store': 'googlePlay',
                'storeUrl':
                    'https://play.google.com/store/apps/details?id=com.example.app',
              },
            ],
          },
        ],
      }),
    ),
  );
  return ManifestSignatureSigner().sign(
    payloadBytes: payload,
    keyId: 'release-rfc',
    issuedAt: now.subtract(const Duration(minutes: 1)).toIso8601String(),
    expiresAt: now.add(const Duration(hours: 1)).toIso8601String(),
    privateKeyBase64: _seedBase64,
  );
}

final _seedBase64 = base64.encode(
  _hex(
    '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
  ),
);
final _publicKeyBase64 = base64.encode(
  _hex(
    'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
  ),
);

List<int> _hex(String value) {
  return [
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ];
}

final class _Fixture {
  final ProductionUpdateController controller;
  final _FakeManifestFetcher fetcher;
  final _RecordingExecutor executor;

  const _Fixture(this.controller, this.fetcher, this.executor);
}

final class _FakeRuntimeLoader implements ProductionRuntimeLoader {
  final ProductionAppMetadata metadata;
  int calls = 0;

  _FakeRuntimeLoader(this.metadata);

  @override
  Future<ProductionAppMetadata> load() async {
    calls++;
    return metadata;
  }
}

final class _CountingFactory implements ProductionUpdaterFactory {
  int calls = 0;

  @override
  AppUpdater create({
    required ProductionUpdateConfiguration configuration,
    required ProductionAppMetadata metadata,
  }) {
    calls++;
    throw StateError('The updater factory should not have been called.');
  }
}

final class _FakeManifestFetcher implements ManifestFetcher {
  final Uint8List body;
  int calls = 0;

  _FakeManifestFetcher(this.body);

  @override
  Future<FetchedManifest> fetch(ManifestUpdateSource source) async {
    calls++;
    return FetchedManifest(
      bodyBytes: body,
      finalUri: source.manifestUrl,
      responseHeaders: const {},
    );
  }
}

final class _RecordingExecutor implements UpdateActionExecutor {
  int performCalls = 0;
  final actions = <UpdateAction>[];

  @override
  bool supports(UpdateAction action) => action is OpenStoreAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    performCalls++;
    actions.add(action);
    return const UpdateActionResult.success();
  }
}
