# Security Policy

## Supported versions

Security fixes are provided for the latest published major version. Users
should reproduce reports against the newest release before filing them.

## Reporting a vulnerability

Do not open a public issue for vulnerabilities involving update manifests,
artifact integrity, path handling, native installers, or credential exposure.
Use [GitHub private vulnerability reporting](https://github.com/indie-geeker/flutter_app_updater/security/advisories/new).
If that channel is unavailable, email `indiegeeker@gmail.com` with a minimal
reproduction and no production secrets.

You should receive an acknowledgment within seven days. The maintainer will
coordinate validation, remediation, and disclosure timing with the reporter.

## Deployment responsibility

Consumers are responsible for HTTPS hosting, access control, Ed25519 manifest
signing and key rotation, distribution-policy compliance, and platform-specific
installer permissions. Every remote artifact needs an exact size and SHA-256;
the digest detects changed bytes but is not a substitute for publisher code
signing.

Remote manifests must be bound to the expected application. Android installer
handoff independently checks package identity and signing lineage.

Foreground and Android durable downloads have distinct credential-persistence
boundaries. A foreground checkpoint stores only a SHA-256 URL fingerprint,
without raw URLs or query tokens, and cross-process ownership prevents two
writers from sharing an artifact target. An Android durable task accepts and
persists only a credential-free stable entry URL with no userinfo, query, or
fragment. That endpoint may redirect over HTTPS to a short-lived signed URL;
the redirect is only an in-memory transport target and is never persisted.
Durable state is stored below `noBackupFilesDir`, while private APK and partial
artifacts remain below the FileProvider-backed `filesDir` tree. Upgrading from
the pre-release single-root layout resets those old tasks and artifacts.

See [the complete security model](doc/security-model.md) for exact manifest and
envelope schemas, trust boundaries, redirect rules, failure behavior, and host
responsibilities.
