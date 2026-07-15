import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/update_error_code.dart';

/// Configures Ed25519 authentication for remote manifest envelopes.
///
/// Public keys are raw 32-byte Ed25519 keys encoded as Base64 and indexed by
/// publisher-controlled key identifiers. Keeping multiple identifiers trusted
/// supports overlap during key rotation.
final class ManifestSignaturePolicy {
  /// Whether every remote manifest, including store-only manifests, must sign.
  final bool requireSignature;

  /// Trusted Base64 public keys indexed by envelope `keyId`.
  final Map<String, String> trustedPublicKeys;

  /// Clock tolerance applied at both ends of the validity window.
  final Duration maxClockSkew;

  /// Maximum accepted duration between `issuedAt` and `expiresAt`.
  final Duration maxValidity;

  /// Requires a valid envelope signed by one of [trustedPublicKeys].
  ManifestSignaturePolicy.required({
    required Map<String, String> trustedPublicKeys,
    this.maxClockSkew = const Duration(minutes: 5),
    this.maxValidity = const Duration(days: 7),
  })  : requireSignature = true,
        trustedPublicKeys = Map.unmodifiable(trustedPublicKeys);

  /// Allows bare official-store and Android-market manifests but authenticates envelopes if used.
  ///
  /// Bare manifests containing self-hosted artifacts are still rejected by the
  /// remote manifest policy.
  ManifestSignaturePolicy.optional({
    Map<String, String> trustedPublicKeys = const {},
    this.maxClockSkew = const Duration(minutes: 5),
    this.maxValidity = const Duration(days: 7),
  })  : requireSignature = false,
        trustedPublicKeys = Map.unmodifiable(trustedPublicKeys);
}

/// A structured remote-manifest signature or envelope failure.
final class ManifestSignatureException implements Exception {
  /// Whether authentication was required or the supplied envelope was invalid.
  final UpdateErrorCode code;

  /// Human-readable diagnostic that does not disclose private key material.
  final String message;

  /// Creates a signature failure with a stable [code].
  const ManifestSignatureException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => '${code.value}: $message';
}

/// Exact manifest payload bytes returned after envelope authentication.
final class VerifiedManifestPayload {
  /// Bytes that may now be UTF-8 decoded and parsed as a manifest.
  final Uint8List payloadBytes;

  /// Whether the bytes came from a successfully verified envelope.
  final bool isSigned;

  /// Trusted key identifier used for verification, or `null` when unsigned.
  final String? keyId;

  /// Creates a verified-payload boundary value.
  const VerifiedManifestPayload({
    required this.payloadBytes,
    required this.isSigned,
    this.keyId,
  });
}

/// Verifies versioned Ed25519 envelopes before manifest payload parsing.
///
/// Signature verification covers the exact received `keyId`, timestamps, and
/// payload bytes using a domain-separated preimage. Payload JSON must not be
/// interpreted until [verify] succeeds.
final class ManifestSignatureVerifier {
  /// Supported signed-envelope format identifier.
  static const format = 'flutter_app_updater.ed25519.v1';
  static const _envelopeFields = {
    'format',
    'keyId',
    'issuedAt',
    'expiresAt',
    'payload',
    'signature',
  };

  /// Trust policy used to select keys and enforce signature requirements.
  final ManifestSignaturePolicy policy;

  /// Clock used for deterministic validity-window evaluation.
  final DateTime Function() clock;

  /// Signature algorithm implementation, Ed25519 by default.
  final SignatureAlgorithm algorithm;

  /// Creates a verifier with injectable clock and crypto boundaries.
  ManifestSignatureVerifier({
    required this.policy,
    DateTime Function()? clock,
    SignatureAlgorithm? algorithm,
  })  : clock = clock ?? DateTime.now,
        algorithm = algorithm ?? Ed25519();

  /// Authenticates [bodyBytes] and returns bytes safe for manifest parsing.
  ///
  /// Throws [ManifestSignatureException] for required bare documents, malformed
  /// envelopes, unknown keys, invalid signatures, or invalid time windows.
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
    _rejectUnknownFields(outer);

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
    } catch (_) {
      throw const ManifestSignatureException(
        code: UpdateErrorCode.manifestSignatureInvalid,
        message: 'Invalid signed manifest envelope.',
      );
    }
  }

  /// Builds the domain-separated byte sequence covered by the signature.
  ///
  /// Timestamp strings are used exactly as received; callers must not parse and
  /// reserialize them before constructing this input.
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

  void _rejectUnknownFields(Map<String, Object?> envelope) {
    for (final field in envelope.keys) {
      if (!_envelopeFields.contains(field)) {
        throw ManifestSignatureException(
          code: UpdateErrorCode.manifestSignatureInvalid,
          message: 'Unknown signed manifest envelope field '
              '${jsonEncode(field)}.',
        );
      }
    }
  }
}

/// Creates signed manifest envelopes compatible with [ManifestSignatureVerifier].
///
/// Applications normally sign in a protected release environment, never in a
/// client application. The private key argument is a Base64-encoded 32-byte
/// Ed25519 seed.
final class ManifestSignatureSigner {
  /// Signature algorithm implementation, Ed25519 by default.
  final SignatureAlgorithm algorithm;

  /// Creates a signer with an injectable crypto implementation.
  ManifestSignatureSigner({SignatureAlgorithm? algorithm})
      : algorithm = algorithm ?? Ed25519();

  /// Signs exact [payloadBytes] and returns a UTF-8 JSON envelope.
  ///
  /// Throws [FormatException] when [keyId] is empty or the private seed does
  /// not decode to exactly 32 bytes.
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
