import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/update_error_code.dart';

final class ManifestSignaturePolicy {
  final bool requireSignature;
  final Map<String, String> trustedPublicKeys;
  final Duration maxClockSkew;
  final Duration maxValidity;

  ManifestSignaturePolicy.required({
    required Map<String, String> trustedPublicKeys,
    this.maxClockSkew = const Duration(minutes: 5),
    this.maxValidity = const Duration(days: 7),
  })  : requireSignature = true,
        trustedPublicKeys = Map.unmodifiable(trustedPublicKeys);

  ManifestSignaturePolicy.optional({
    Map<String, String> trustedPublicKeys = const {},
    this.maxClockSkew = const Duration(minutes: 5),
    this.maxValidity = const Duration(days: 7),
  })  : requireSignature = false,
        trustedPublicKeys = Map.unmodifiable(trustedPublicKeys);
}

final class ManifestSignatureException implements Exception {
  final UpdateErrorCode code;
  final String message;

  const ManifestSignatureException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => '${code.value}: $message';
}

final class VerifiedManifestPayload {
  final Uint8List payloadBytes;
  final bool isSigned;
  final String? keyId;

  const VerifiedManifestPayload({
    required this.payloadBytes,
    required this.isSigned,
    this.keyId,
  });
}

final class ManifestSignatureVerifier {
  static const format = 'flutter_app_updater.ed25519.v1';

  final ManifestSignaturePolicy policy;
  final DateTime Function() clock;
  final SignatureAlgorithm algorithm;

  ManifestSignatureVerifier({
    required this.policy,
    DateTime Function()? clock,
    SignatureAlgorithm? algorithm,
  })  : clock = clock ?? DateTime.now,
        algorithm = algorithm ?? Ed25519();

  Future<VerifiedManifestPayload> verify(Uint8List bodyBytes) async {
    final Map<String, Object?> outer;
    try {
      outer = _decodeObject(bodyBytes);
    } on ManifestSignatureException {
      if (policy.requireSignature) {
        throw const ManifestSignatureException(
          code: UpdateErrorCode.manifestSignatureRequired,
          message: 'A signed manifest envelope is required.',
        );
      }
      return VerifiedManifestPayload(
        payloadBytes: bodyBytes,
        isSigned: false,
      );
    }
    final envelopeFormat = outer['format'];
    if (envelopeFormat == null) {
      if (policy.requireSignature) {
        throw const ManifestSignatureException(
          code: UpdateErrorCode.manifestSignatureRequired,
          message: 'A signed manifest envelope is required.',
        );
      }
      return VerifiedManifestPayload(
        payloadBytes: bodyBytes,
        isSigned: false,
      );
    }
    if (envelopeFormat != format) {
      throw const ManifestSignatureException(
        code: UpdateErrorCode.manifestSignatureInvalid,
        message: 'Unsupported signed manifest format.',
      );
    }

    try {
      final keyId = _requiredString(outer, 'keyId');
      final issuedAtText = _requiredString(outer, 'issuedAt');
      final expiresAtText = _requiredString(outer, 'expiresAt');
      final payloadBytes = Uint8List.fromList(
        base64.decode(_requiredString(outer, 'payload')),
      );
      final signatureBytes = base64.decode(
        _requiredString(outer, 'signature'),
      );
      final publicKeyText = policy.trustedPublicKeys[keyId];
      if (publicKeyText == null) {
        throw const FormatException('Unknown manifest signing key.');
      }
      final publicKeyBytes = base64.decode(publicKeyText);
      if (publicKeyBytes.length != 32 || signatureBytes.length != 64) {
        throw const FormatException('Invalid Ed25519 key or signature size.');
      }

      final issuedAt = DateTime.tryParse(issuedAtText);
      final expiresAt = DateTime.tryParse(expiresAtText);
      if (issuedAt == null || expiresAt == null) {
        throw const FormatException('Invalid envelope validity timestamp.');
      }
      final publicKey = SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      );
      final isValid = await algorithm.verify(
        signatureInput(
          keyId: keyId,
          issuedAt: issuedAtText,
          expiresAt: expiresAtText,
          payloadBytes: payloadBytes,
        ),
        signature: Signature(signatureBytes, publicKey: publicKey),
      );
      if (!isValid) {
        throw const FormatException('Ed25519 signature verification failed.');
      }

      final validity = expiresAt.difference(issuedAt);
      if (validity <= Duration.zero || validity > policy.maxValidity) {
        throw const FormatException('Invalid envelope validity range.');
      }

      final now = clock();
      if (now.add(policy.maxClockSkew).isBefore(issuedAt) ||
          now.subtract(policy.maxClockSkew).isAfter(expiresAt)) {
        throw const FormatException('Envelope is outside its validity window.');
      }

      return VerifiedManifestPayload(
        payloadBytes: payloadBytes,
        isSigned: true,
        keyId: keyId,
      );
    } on ManifestSignatureException {
      rethrow;
    } catch (error) {
      throw ManifestSignatureException(
        code: UpdateErrorCode.manifestSignatureInvalid,
        message: 'Invalid signed manifest envelope: $error',
      );
    }
  }

  static Uint8List signatureInput({
    required String keyId,
    required String issuedAt,
    required String expiresAt,
    required Uint8List payloadBytes,
  }) {
    return Uint8List.fromList([
      ...utf8.encode('$format\u0000'),
      ...utf8.encode('$keyId\u0000$issuedAt\u0000$expiresAt\u0000'),
      ...payloadBytes,
    ]);
  }

  Map<String, Object?> _decodeObject(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException('Manifest root must be an object.');
      }
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } catch (error) {
      throw ManifestSignatureException(
        code: UpdateErrorCode.manifestSignatureInvalid,
        message: 'Manifest envelope is not valid UTF-8 JSON: $error',
      );
    }
  }

  String _requiredString(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('$field is required.');
  }
}

final class ManifestSignatureSigner {
  final SignatureAlgorithm algorithm;

  ManifestSignatureSigner({SignatureAlgorithm? algorithm})
      : algorithm = algorithm ?? Ed25519();

  Future<Uint8List> sign({
    required Uint8List payloadBytes,
    required String keyId,
    required String issuedAt,
    required String expiresAt,
    required String privateKeyBase64,
  }) async {
    if (keyId.isEmpty) {
      throw const FormatException('keyId must not be empty.');
    }
    final seed = base64.decode(privateKeyBase64);
    if (seed.length != 32) {
      throw const FormatException(
        'The Ed25519 private key must be a Base64-encoded 32-byte seed.',
      );
    }
    final keyPair = await Ed25519().newKeyPairFromSeed(seed);
    final signature = await algorithm.sign(
      ManifestSignatureVerifier.signatureInput(
        keyId: keyId,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        payloadBytes: payloadBytes,
      ),
      keyPair: keyPair,
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': ManifestSignatureVerifier.format,
          'keyId': keyId,
          'issuedAt': issuedAt,
          'expiresAt': expiresAt,
          'payload': base64.encode(payloadBytes),
          'signature': base64.encode(signature.bytes),
        }),
      ),
    );
  }
}
