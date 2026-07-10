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

Consumers are responsible for HTTPS hosting, access control, artifact signing,
distribution-policy compliance, and platform-specific installer permissions.
SHA-256 detects accidental or malicious file changes but is not a substitute
for publisher code signing.
