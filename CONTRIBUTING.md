# Contributing

Thanks for improving `flutter_app_updater`. Focused bug fixes, platform
compatibility improvements, tests, and documentation corrections are welcome.

## Before opening a change

- Search existing issues and open one for behavior changes that need design
  agreement.
- Never include private manifests, signing material, access tokens, or real
  customer download URLs.
- Keep platform permissions opt-in and document any native capability change.

## Local checks

Install the current stable Flutter SDK, then run:

```bash
flutter pub get
(cd example && flutter pub get)
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub
flutter test --no-pub
dart doc --dry-run
(cd example && flutter analyze --no-pub && flutter test --no-pub)
flutter pub publish --dry-run
```

Add a failing test before changing behavior. Native changes should also include
the relevant Android, iOS, macOS, or Windows build/device verification.

## Pull requests

Keep each pull request narrowly scoped. Explain the public API or manifest
impact, list the commands run, and call out any permissions, networking,
installer, or distribution-policy implications.

## Maintainer releases

On the pub.dev package Admin page, automated publishing must be bound to
`indie-geeker/flutter_app_updater` with tag pattern `v{{version}}` and required
GitHub environment `pub.dev`. Protect that environment with a required reviewer.

After CI passes, update `version` and `CHANGELOG.md`, merge the release change,
then push the matching tag (for example, `v3.0.0`). The publish workflow checks
the tag against `pubspec.yaml` before calling the official Dart OIDC workflow.
No long-lived pub.dev credential belongs in GitHub secrets or repository files.
