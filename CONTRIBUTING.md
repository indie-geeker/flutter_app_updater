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

The supported floor is the exact version in
`tool/ci/flutter_min_version.txt` (currently Flutter 3.22.0). Changes must pass
both that version and the current stable Flutter SDK. The canonical automation
is `.github/workflows/full-gate.yml`; run the stable local subset with:

```bash
flutter pub get
(cd example && flutter pub get)
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub
flutter test --coverage --no-pub
dart doc --dry-run
(cd example && flutter analyze --no-pub && flutter test --no-pub)
(cd example/android && ../../android/gradlew :flutter_app_updater:testDebugUnitTest :flutter_app_updater:lintDebug :app:processDebugMainManifest)
(cd example && flutter build apk --debug --no-pub)
```

Add a failing test before changing behavior. Native changes should also include
the relevant Android, iOS, macOS, or Windows automated build and test gate.

Run `bash tool/ci/publish_dry_run.sh` after committing the intended changes. It
creates a temporary package from `git archive HEAD`, resolves dependencies, and
requires `flutter pub publish --dry-run` to report zero warnings.

## Pull requests

Keep each pull request narrowly scoped. Explain the public API or manifest
impact, list the commands run, and call out any permissions, networking,
installer, or distribution-policy implications.

## Maintainer releases

On the pub.dev package Admin page, automated publishing must be bound to
`indie-geeker/flutter_app_updater` with tag pattern `v{{version}}` and required
GitHub environment `pub.dev`. Protect that environment with a required reviewer.

After CI passes, update `version` and `CHANGELOG.md`, merge the release change,
then push the matching tag (for example, `v3.0.0`). Stable and prerelease tags
must exactly match a SemVer `pubspec.yaml` version without build metadata and a
same-version `CHANGELOG.md` heading. The publish workflow fetches full history,
requires the tagged commit to be an ancestor of `origin/main`, reruns the full
gate, and verifies metadata before calling the official Dart OIDC workflow.
No long-lived pub.dev credential belongs in GitHub secrets or repository files.

Verify the version and changelog contract locally before tagging:

```bash
version="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
dart run tool/ci/verify_release_metadata.dart --tag "v$version"
```
