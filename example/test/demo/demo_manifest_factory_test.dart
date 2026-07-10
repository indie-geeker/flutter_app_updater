import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater_example/demo/demo_manifest_factory.dart';
import 'package:flutter_app_updater_example/demo/demo_scenario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemoManifestFactory', () {
    test('maps a required Android package scenario into a v3 manifest', () {
      final scenario = DemoScenario.defaults().copyWith(
        platform: TargetPlatform.android,
        policyLevel: UpdatePolicyLevel.required,
        delivery: DemoDelivery.androidPackage,
      );

      final manifest = const DemoManifestFactory().build(scenario);

      expect(manifest.schemaVersion, 3);
      expect(manifest.appId, DemoManifestFactory.appId);
      expect(manifest.releases.single.policy.level, UpdatePolicyLevel.required);
      expect(
        manifest.releases.single.actions.single,
        isA<DownloadAndInstallPackageAction>(),
      );
    });

    test('no-update scenario still exercises selector comparison', () async {
      final scenario = DemoScenario.defaults().copyWith(updateAvailable: false);
      final manifest = const DemoManifestFactory().build(scenario);
      final updater = AppUpdater(
        source: UpdateSource.staticManifest(manifest: manifest),
        expectedAppId: DemoManifestFactory.appId,
        selector: scenario.toSelector(),
        executors: const [],
      );

      expect(
          await updater.checkAndPrepare(), isA<PreparedUpdateNotAvailable>());
    });

    test('maps official stores for supported mobile and Apple platforms', () {
      final cases = <TargetPlatform, StoreKind>{
        TargetPlatform.android: StoreKind.googlePlay,
        TargetPlatform.iOS: StoreKind.appStore,
        TargetPlatform.macOS: StoreKind.macAppStore,
      };

      for (final MapEntry(key: platform, value: store) in cases.entries) {
        final scenario = DemoScenario.defaults().copyWith(
          platform: platform,
          architecture: platform == TargetPlatform.android ? 'arm64' : 'x64',
          delivery: DemoDelivery.officialStore,
        );

        final action = const DemoManifestFactory()
            .build(scenario)
            .releases
            .single
            .actions
            .single;

        expect(action, isA<OpenStoreAction>());
        expect((action as OpenStoreAction).store, store);
      }
    });

    test('maps a Chinese Android market action', () {
      final scenario = DemoScenario.defaults().copyWith(
        delivery: DemoDelivery.androidMarket,
      );

      final action = const DemoManifestFactory()
          .build(scenario)
          .releases
          .single
          .actions
          .single;

      expect(action, isA<OpenAndroidMarketAction>());
      expect(
          (action as OpenAndroidMarketAction).market, AndroidMarketKind.xiaomi);
    });

    test('maps platform-specific desktop installers', () {
      final macScenario = DemoScenario.defaults().copyWith(
        platform: TargetPlatform.macOS,
        architecture: 'arm64',
        delivery: DemoDelivery.desktopInstaller,
      );
      final windowsScenario = macScenario.copyWith(
        platform: TargetPlatform.windows,
        architecture: 'x64',
      );

      final macAction = const DemoManifestFactory()
          .build(macScenario)
          .releases
          .single
          .actions
          .single as OpenInstallerAction;
      final windowsAction = const DemoManifestFactory()
          .build(windowsScenario)
          .releases
          .single
          .actions
          .single as OpenInstallerAction;

      expect(macAction.installerType, InstallerType.dmg);
      expect(windowsAction.installerType, InstallerType.msix);
    });

    test('preserves minimum supported version in update policy', () {
      final scenario = DemoScenario.defaults().copyWith(
        minSupportedVersion: '1.5.0',
      );

      final policy =
          const DemoManifestFactory().build(scenario).releases.single.policy;

      expect(policy.minSupportedVersion, '1.5.0');
    });

    test('rejects delivery types that contradict the selected platform', () {
      final scenario = DemoScenario.defaults().copyWith(
        platform: TargetPlatform.iOS,
        delivery: DemoDelivery.androidPackage,
      );

      expect(
        () => const DemoManifestFactory().build(scenario),
        throwsArgumentError,
      );
    });
  });

  group('DemoScenario', () {
    test('reports only delivery types supported by the simulated platform', () {
      expect(
        DemoScenario.allowedDeliveries(TargetPlatform.iOS),
        [DemoDelivery.officialStore],
      );
      expect(
        DemoScenario.allowedDeliveries(TargetPlatform.windows),
        [DemoDelivery.desktopInstaller],
      );
      expect(
        DemoScenario.allowedDeliveries(TargetPlatform.android),
        containsAll([
          DemoDelivery.officialStore,
          DemoDelivery.androidMarket,
          DemoDelivery.androidPackage,
        ]),
      );
    });
  });
}
