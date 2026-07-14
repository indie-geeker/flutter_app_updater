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
handoff independently checks package identity and signing lineage. Resumable
checkpoints fingerprint the source without storing raw URLs or query tokens, and
cross-process ownership prevents two writers from sharing an artifact target.
See [the complete security model](doc/security-model.md) for trust boundaries,
redirect rules, failure behavior, and host responsibilities.
