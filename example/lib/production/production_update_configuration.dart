import 'dart:convert';

import 'package:flutter_app_updater/flutter_app_updater.dart';

/// Validated compile-time configuration for the opt-in production example.
final class ProductionUpdateConfiguration {
  final bool enabled;
  final Uri? manifestUrl;
  final String expectedAppId;
  final String channel;
  final String? architecture;
  final Map<String, String> trustedPublicKeys;
  final UpdateDistributionPolicy distributionPolicy;
  final String? validationError;

  const ProductionUpdateConfiguration._({
    required this.enabled,
    required this.manifestUrl,
    required this.expectedAppId,
    required this.channel,
    required this.architecture,
    required this.trustedPublicKeys,
    required this.distributionPolicy,
    this.validationError,
  });

  /// Reads the documented `--dart-define` values without starting any work.
  factory ProductionUpdateConfiguration.fromEnvironment() {
    try {
      return ProductionUpdateConfiguration.parse(
        enabled: const bool.fromEnvironment(
          'ENABLE_PRODUCTION_UPDATE_EXAMPLE',
        ),
        manifestUrl: const String.fromEnvironment('UPDATE_MANIFEST_URL'),
        expectedAppId: const String.fromEnvironment('UPDATE_EXPECTED_APP_ID'),
        channel: const String.fromEnvironment(
          'UPDATE_CHANNEL',
          defaultValue: 'stable',
        ),
        architecture: const String.fromEnvironment('UPDATE_ARCHITECTURE'),
        publicKeysJson: const String.fromEnvironment(
          'UPDATE_MANIFEST_PUBLIC_KEYS',
        ),
      );
    } on FormatException catch (error) {
      return ProductionUpdateConfiguration.invalid(error.message);
    }
  }

  /// Parses and validates configuration supplied by tests or the environment.
  factory ProductionUpdateConfiguration.parse({
    bool enabled = false,
    String manifestUrl = '',
    String expectedAppId = '',
    String channel = 'stable',
    String architecture = '',
    String publicKeysJson = '',
  }) {
    if (!enabled) {
      return const ProductionUpdateConfiguration._(
        enabled: false,
        manifestUrl: null,
        expectedAppId: '',
        channel: 'stable',
        architecture: null,
        trustedPublicKeys: {},
        distributionPolicy: UpdateDistributionPolicy.any,
      );
    }

    final parsedUrl = Uri.tryParse(manifestUrl.trim());
    if (parsedUrl == null ||
        parsedUrl.scheme != 'https' ||
        !parsedUrl.hasAuthority ||
        parsedUrl.host.isEmpty ||
        parsedUrl.userInfo.isNotEmpty) {
      throw const FormatException(
        'UPDATE_MANIFEST_URL must be an absolute HTTPS URL without user info.',
      );
    }
    final appId = expectedAppId.trim();
    if (appId.isEmpty) {
      throw const FormatException('UPDATE_EXPECTED_APP_ID must not be blank.');
    }
    final releaseChannel = channel.trim();
    if (releaseChannel.isEmpty) {
      throw const FormatException('UPDATE_CHANNEL must not be blank.');
    }

    final Map<String, String> publicKeys;
    try {
      final decoded = jsonDecode(publicKeysJson);
      if (decoded is! Map) {
        throw const FormatException(
          'UPDATE_MANIFEST_PUBLIC_KEYS must be a JSON object.',
        );
      }
      publicKeys = decoded.map((key, value) {
        if (key is! String || key.trim().isEmpty || value is! String) {
          throw const FormatException(
            'Manifest public keys require non-blank string IDs and values.',
          );
        }
        final bytes = base64.decode(value);
        if (bytes.length != 32) {
          throw const FormatException(
            'Each manifest public key must decode to exactly 32 bytes.',
          );
        }
        return MapEntry(key.trim(), value);
      });
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException(
        'UPDATE_MANIFEST_PUBLIC_KEYS is invalid: $error',
      );
    }
    if (publicKeys.isEmpty) {
      throw const FormatException(
        'UPDATE_MANIFEST_PUBLIC_KEYS must contain at least one public key.',
      );
    }

    final normalizedArchitecture = architecture.trim();
    return ProductionUpdateConfiguration._(
      enabled: true,
      manifestUrl: parsedUrl,
      expectedAppId: appId,
      channel: releaseChannel,
      architecture:
          normalizedArchitecture.isEmpty ? null : normalizedArchitecture,
      trustedPublicKeys: Map.unmodifiable(publicKeys),
      distributionPolicy: UpdateDistributionPolicy.any,
    );
  }

  /// Preserves a startup validation failure for structured in-app rendering.
  factory ProductionUpdateConfiguration.invalid(String message) {
    return ProductionUpdateConfiguration._(
      enabled: true,
      manifestUrl: null,
      expectedAppId: '',
      channel: 'stable',
      architecture: null,
      trustedPublicKeys: const {},
      distributionPolicy: UpdateDistributionPolicy.any,
      validationError: message,
    );
  }
}
