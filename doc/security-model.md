# Security model

Flutter App Updater treats an update as a chain of independently checked trust
boundaries. A later check does not compensate for a missing earlier one:

```text
trusted transport
→ authenticated publisher manifest
→ expected application identity
→ valid release and action policy
→ exact artifact integrity
→ platform package identity
→ explicit host confirmation and execution
```

## Security goals and non-goals

The package is designed to prevent a network endpoint, malformed manifest,
substituted artifact, or unrelated Android APK from silently becoming an update
action. Failures close the affected path and return a structured error.

The package does not decide whether a publisher is legally permitted to
self-distribute, secure release infrastructure, protect signing keys, provide
host UI, grant Android installation permission, or make a compromised running
application trustworthy.

## Transport

Remote manifests and artifacts require absolute HTTPS URLs in production.
Embedded URI user information is rejected. Redirects are followed manually,
are limited to five, and every target is revalidated. An HTTPS request may not
downgrade to HTTP. Caller-supplied manifest headers are retained only across a
same-origin redirect so credentials do not cross an origin boundary.

Plain HTTP exists only as an explicitly enabled loopback development exception.
It is not a production trust mode.

## Manifest application identity

Every remote source requires `expectedAppId`. After authentication and
parsing, the manifest `appId` must equal that value before any release is
selected or action is executed. Android market actions must target the same
package name. A mismatch returns `APP_ID_MISMATCH`.

This binding prevents a valid manifest for one application from being replayed
as an update for another application. The host must configure its real package
or bundle identifier rather than a shared product-family value.

## Ed25519 publisher authentication

Self-hosted package and installer actions require a signed Ed25519 envelope.
The versioned envelope contains a `keyId`, exact issue and expiry timestamp
strings, a Base64 payload, and a signature. Verification uses a
domain-separated preimage that includes the exact header strings and decoded
payload bytes. Payload JSON is parsed only after signature verification.

The host configures trusted raw public keys with
`ManifestSignaturePolicy.required` or `ManifestSignaturePolicy.optional`.
Optional policy permits a bare official-store-only manifest over trusted
transport, but never permits a bare self-hosted artifact. Required policy
rejects every bare manifest.

Envelope time ranges must be positive, currently valid within configured clock
skew, and no longer than the configured maximum. This limits replay while
allowing bounded client clock differences.

### Key rotation

Use a distinct `keyId` for each release key. During rotation:

1. Ship an application version that trusts both the old and new public keys.
2. Begin signing new envelopes with the new identifier.
3. Keep the overlap long enough for supported clients to update.
4. Remove the old public key in a later application release.

An unknown identifier or invalid signature fails closed. Public keys may ship
in the application; signing keys must remain outside source code, examples,
client binaries, logs, manifests, and CI output.

## Manifest and distribution policy

Schema version 3 rejects removed legacy fields and unknown action types. Remote
`installPackage` actions are forbidden because a network document must never
select an arbitrary local path. Official store URLs and Android market
fallbacks are restricted to trusted destinations.

`UpdateDistributionPolicy` is a host-side restriction applied without
reordering actions:

- `any` permits supported store and self-hosted actions;
- `storeOnly` excludes package and installer actions;
- `selfHostedOnly` excludes official-store and Android-market actions.

Executor capability filtering runs as an additional boundary. The first action
remaining in publisher order becomes the recommendation. Distribution policy
does not weaken transport, signature, artifact, or platform verification.

## Artifact integrity

Every remote package or installer action must contain a positive exact
`packageSizeBytes` or installer size and a 64-character `sha256`. The
downloader enforces configured maximums, validates received byte counts while
streaming, and computes SHA-256 before committing the final file.

Resumable checkpoints bind the complete source URL through a SHA-256
fingerprint without persisting query tokens or the raw URL. Resume requires
safe range semantics and strong server validators. A process-local ownership
guard and a persistent operating-system lock prevent two writers from targeting
the same artifact path. Protocol, storage, cancellation, size, and digest
failures release ownership and preserve or remove checkpoint state according to
whether a safe resume remains possible.

## Android package identity

Before Android installer handoff, native code rechecks optional exact size and
`sha256`, parses the APK, and compares its package identity with the installed
host application. It also verifies signing lineage, including compatible
certificate rotation and multi-signer behavior. The installer intent is never
launched after a file, digest, package identity, or signing lineage failure.

Foreground download-and-install and durable background-download installation
use the same native verifier. Installation itself remains user-mediated and
requires the host to declare and justify any sensitive Android permission.

## Host responsibilities

The consuming application must:

- obtain accurate installed version, build, platform, channel, and architecture
  values;
- configure the real `expectedAppId` and a deliberate distribution policy;
- pin and rotate trusted Ed25519 public keys;
- publish exact artifact metadata from the final immutable files;
- protect signing infrastructure and audit release access;
- present release notes, required-update policy, confirmation, cancellation,
  accessibility, and recovery UI;
- request platform permissions only from visible user-initiated flows;
- log stable failure codes without tokens, headers, local sensitive paths, or
  secret material.

Unknown runtime architecture fails closed for architecture-specific releases;
publish a universal release only when the artifact genuinely supports it.

## Failure behavior

Checks are side-effect-free. Configuration, fetch, signature, application
identity, schema, policy, release matching, and capability failures become
`UpdateCheckFailed` or `PreparedUpdateCheckFailed`. Executed actions produce
one terminal `UpdateActionCompleted` containing a structured
`UpdateActionResult`. Cooperative cancellation is reported as
`ACTION_CANCELED`.

The host should treat signature, identity, SHA-256, and signing-lineage failures
as non-retryable security events. Only transient network and selected server
failures should use bounded retry. Never fall back from a failed authenticated
self-hosted path to an unverified local install.
