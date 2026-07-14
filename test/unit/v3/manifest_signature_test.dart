import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_app_updater/src/manifest/manifest_signature.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13, 12);
  final payload = Uint8List.fromList(utf8.encode('{"schemaVersion":3}'));
  late SimpleKeyPair keyPair;
  late String publicKeyBase64;

  setUpAll(() async {
    keyPair =
        await Ed25519().newKeyPairFromSeed(List<int>.generate(32, (i) => i));
    final publicKey = await keyPair.extractPublicKey();
    publicKeyBase64 = base64.encode(publicKey.bytes);
  });

  Future<Uint8List> envelope({
    String format = ManifestSignatureVerifier.format,
    String keyId = 'release-2026-01',
    String issuedAt = '2026-07-13T11:00:00Z',
    String expiresAt = '2026-07-14T11:00:00Z',
    Uint8List? payloadBytes,
    SimpleKeyPair? signingKey,
  }) async {
    final effectivePayload = payloadBytes ?? payload;
    final preimage = ManifestSignatureVerifier.signatureInput(
      keyId: keyId,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      payloadBytes: effectivePayload,
    );
    final signature = await Ed25519().sign(
      preimage,
      keyPair: signingKey ?? keyPair,
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': format,
          'keyId': keyId,
          'issuedAt': issuedAt,
          'expiresAt': expiresAt,
          'payload': base64.encode(effectivePayload),
          'signature': base64.encode(signature.bytes),
        }),
      ),
    );
  }

  ManifestSignatureVerifier verifier({
    Map<String, String>? keys,
    Duration maxClockSkew = const Duration(minutes: 5),
  }) {
    return ManifestSignatureVerifier(
      policy: ManifestSignaturePolicy.required(
        trustedPublicKeys: keys ?? {'release-2026-01': publicKeyBase64},
        maxClockSkew: maxClockSkew,
      ),
      clock: () => now,
    );
  }

  test('verifies a valid envelope without reserializing signed fields',
      () async {
    final result = await verifier().verify(await envelope());

    expect(result.isSigned, isTrue);
    expect(result.keyId, 'release-2026-01');
    expect(result.payloadBytes, payload);
  });

  test('rejects one-byte payload changes and modified signed headers',
      () async {
    final valid =
        jsonDecode(utf8.decode(await envelope())) as Map<String, Object?>;
    final tamperedPayload = Map<String, Object?>.from(valid)
      ..['payload'] = base64.encode([...payload]..[0] ^= 1);
    final tamperedHeader = Map<String, Object?>.from(valid)
      ..['keyId'] = 'release-2026-02';

    for (final value in [tamperedPayload, tamperedHeader]) {
      await expectLater(
        verifier(
          keys: {
            'release-2026-01': publicKeyBase64,
            'release-2026-02': publicKeyBase64,
          },
        ).verify(Uint8List.fromList(utf8.encode(jsonEncode(value)))),
        _signatureFailure(UpdateErrorCode.manifestSignatureInvalid),
      );
    }
  });

  test('rejects malformed Base64, bad signatures, unknown keys, and format',
      () async {
    final valid =
        jsonDecode(utf8.decode(await envelope())) as Map<String, Object?>;
    final cases = [
      Map<String, Object?>.from(valid)..['payload'] = '***',
      Map<String, Object?>.from(valid)..['signature'] = base64.encode([1, 2]),
      Map<String, Object?>.from(valid)..['keyId'] = 'unknown',
      Map<String, Object?>.from(valid)..['format'] = 'wrong.v1',
    ];

    for (final value in cases) {
      await expectLater(
        verifier().verify(Uint8List.fromList(utf8.encode(jsonEncode(value)))),
        _signatureFailure(UpdateErrorCode.manifestSignatureInvalid),
      );
    }
  });

  test('rejects expired, future, inverted, and overlong validity windows',
      () async {
    final cases = [
      await envelope(
        issuedAt: '2026-07-12T10:00:00Z',
        expiresAt: '2026-07-13T11:54:59Z',
      ),
      await envelope(
        issuedAt: '2026-07-13T12:05:01Z',
        expiresAt: '2026-07-14T12:00:00Z',
      ),
      await envelope(
        issuedAt: '2026-07-14T00:00:00Z',
        expiresAt: '2026-07-13T00:00:00Z',
      ),
      await envelope(
        issuedAt: '2026-07-13T00:00:00Z',
        expiresAt: '2026-07-21T00:00:01Z',
      ),
    ];

    for (final value in cases) {
      await expectLater(
        verifier().verify(value),
        _signatureFailure(UpdateErrorCode.manifestSignatureInvalid),
      );
    }
  });

  test('required policy rejects every bare manifest', () async {
    await expectLater(
      verifier().verify(
        Uint8List.fromList(
          utf8.encode('{"schemaVersion":3,"releases":[]}'),
        ),
      ),
      _signatureFailure(UpdateErrorCode.manifestSignatureRequired),
    );
  });

  test('optional policy leaves malformed bare input for manifest parsing',
      () async {
    final bytes = Uint8List.fromList([0xff, 0xfe, 0xfd]);
    final result = await ManifestSignatureVerifier(
      policy: ManifestSignaturePolicy.optional(),
      clock: () => now,
    ).verify(bytes);

    expect(result.isSigned, isFalse);
    expect(result.payloadBytes, bytes);
  });

  test('supports two-key rotation', () async {
    final secondKey = await Ed25519().newKeyPairFromSeed(
      List<int>.generate(32, (i) => 31 - i),
    );
    final secondPublicKey = await secondKey.extractPublicKey();

    final result = await verifier(
      keys: {
        'release-2026-01': publicKeyBase64,
        'release-2026-02': base64.encode(secondPublicKey.bytes),
      },
    ).verify(
      await envelope(
        keyId: 'release-2026-02',
        signingKey: secondKey,
      ),
    );

    expect(result.keyId, 'release-2026-02');
  });
}

Matcher _signatureFailure(UpdateErrorCode code) {
  return throwsA(
    isA<ManifestSignatureException>().having(
      (error) => error.code,
      'code',
      code,
    ),
  );
}
