import 'dart:convert';

import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater_example/production/production_update_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production integration is disabled by default', () {
    final configuration = ProductionUpdateConfiguration.parse();

    expect(configuration.enabled, isFalse);
    expect(configuration.manifestUrl, isNull);
    expect(configuration.distributionPolicy, UpdateDistributionPolicy.any);
  });

  test('enabled integration requires HTTPS URL and expected app ID', () {
    for (final values in [
      (
        manifestUrl: '',
        expectedAppId: 'com.example.app',
      ),
      (
        manifestUrl: 'http://updates.example.com/manifest.json',
        expectedAppId: 'com.example.app',
      ),
      (
        manifestUrl: 'https://updates.example.com/manifest.json',
        expectedAppId: ' ',
      ),
    ]) {
      expect(
        () => ProductionUpdateConfiguration.parse(
          enabled: true,
          manifestUrl: values.manifestUrl,
          expectedAppId: values.expectedAppId,
          publicKeysJson: _validKeys,
        ),
        throwsFormatException,
      );
    }
  });

  test('enabled integration rejects malformed public-key configuration', () {
    for (final value in [
      '',
      'not-json',
      '[]',
      '{"release-1":"not-base64"}',
      '{"":"${base64.encode(List<int>.filled(32, 1))}"}',
      '{"release-1":"${base64.encode(List<int>.filled(31, 1))}"}',
    ]) {
      expect(
        () => ProductionUpdateConfiguration.parse(
          enabled: true,
          manifestUrl: 'https://updates.example.com/manifest.json',
          expectedAppId: 'com.example.app',
          publicKeysJson: value,
        ),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test('parses valid production configuration and optional architecture', () {
    final configuration = ProductionUpdateConfiguration.parse(
      enabled: true,
      manifestUrl: 'https://updates.example.com/manifest.json',
      expectedAppId: ' com.example.app ',
      channel: 'beta',
      architecture: ' arm64 ',
      publicKeysJson: _validKeys,
    );

    expect(configuration.enabled, isTrue);
    expect(configuration.manifestUrl?.scheme, 'https');
    expect(configuration.expectedAppId, 'com.example.app');
    expect(configuration.channel, 'beta');
    expect(configuration.architecture, 'arm64');
    expect(configuration.trustedPublicKeys, hasLength(1));
  });
}

final _validKeys = jsonEncode({
  'release-1': base64.encode(List<int>.generate(32, (index) => index)),
});
