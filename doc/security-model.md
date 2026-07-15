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
The signed envelope rejects extra fields: its exact allowlist is `format`,
`keyId`, `issuedAt`, `expiresAt`, `payload`, and `signature`.

The host configures trusted raw public keys with
`ManifestSignaturePolicy.required` or `ManifestSignaturePolicy.optional`.
Optional policy permits a bare manifest containing only official-store or
Android-market actions over trusted transport, but never permits a bare
self-hosted artifact. Required policy rejects every bare manifest.

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

Schema version 3 uses an exact allowlist for the root, every release, every
policy, and every action object. It rejects unknown fields, removed legacy
fields, and unknown action types. There is no `extensions` escape hatch.
Publishers that need another field must define a new schema version; v3 never
silently ignores it. Every action object requires `type`, and fields that do not
belong to the selected action type reject the complete response.

The optional `buildNumber` must be a non-negative ASCII decimal integer string.
Leading zeroes are valid and parsing is numeric; malformed, signed, negative,
or non-ASCII values reject the complete response. An optional
`minSupportedVersion` must be a valid semantic version no greater than the
containing release `version`. These checks occur before release selection.

Remote `installPackage` actions are forbidden because a network document must
never select an arbitrary local path. Official store URLs and Android market
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

A foreground checkpoint binds the complete source URL through a SHA-256
fingerprint without persisting the raw URL or query token. Resume requires safe
range semantics and strong server validators. A process-local ownership guard
and a persistent operating-system lock prevent two writers from targeting the
same artifact path. Protocol, storage, cancellation, size, and digest failures
release ownership and preserve or remove checkpoint state according to whether
a safe resume remains possible.

### Android durable URL and storage boundary

Android durable downloads deliberately use a stricter contract than the
foreground downloader. `start()` accepts and the task record persists only a
credential-free stable entry URL with no userinfo, query, or fragment. For
expiring credentials, the stable endpoint may return an HTTPS redirect to a
short-lived signed URL. Each redirect hop is revalidated; HTTPS never
downgrades to HTTP. The signed URL is an in-memory transport target and is never
persisted, so resume always begins again at the stable entry.

Durable task state lives below Android `noBackupFilesDir`. APK and partial
artifacts live in the app-private, FileProvider-backed `filesDir` tree. On first
use of this split layout, tasks and artifacts from the pre-release single-root
layout are reset rather than migrated. That prevents stale records from
silently referring to artifacts under the former storage boundary.

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
