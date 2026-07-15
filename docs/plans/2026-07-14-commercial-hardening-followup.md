# Commercial Hardening Follow-up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove credential-bearing Android durable state, make manifest v3 fail closed, and restore a genuinely pure Dart package CLI without changing the public Flutter platform API.

**Architecture:** Split manifest wire parsing into a pure Dart document layer followed by a Flutter model adapter, with one primitive remote-action policy shared by CLI and runtime. Split Android background state and artifacts across `noBackupFilesDir` and FileProvider-compatible `filesDir`, persisting only a credential-free stable entry URL while allowing signed redirect targets in memory. Keep `ManifestSchema` as the exact v3 field and cross-field validation choke point.

**Tech Stack:** Dart 3.4+, Flutter 3.22+, Kotlin/JVM 17, Android API 21+, Flutter tests, Kotlin/JUnit tests, GitHub Actions, Ed25519, SHA-256.

---

## Execution boundary

- Work only in the `codex/commercial-hardening-followup` worktree.
- Preserve unrelated changes in the main checkout.
- Use TDD for every behavior change: focused failing test, observed expected
  failure, minimal implementation, focused green test, then broader tests.
- Stage only exact task paths. Do not push, tag, publish, or open a PR.
- The current main checkout contains the already approved bilingual README
  changes; import those three documentation files into this branch before the
  documentation task, then extend them rather than recreating an older README.
- Android native tests run through `example/android` with the plugin wrapper.

### Task 1: Make manifest v3 and its signed envelope fail closed

**Files:**

- Modify: `lib/src/manifest/manifest_schema.dart`
- Modify: `lib/src/manifest/manifest_signature.dart`
- Modify: `test/unit/v3/manifest_validator_test.dart`
- Modify: `test/unit/v3/manifest_signature_test.dart`
- Modify: `test/unit/v3/app_updater_manifest_source_test.dart`

**Step 1: Write failing exact-field tests**

Add focused tests that insert one unknown field at each of these paths and
expect `MANIFEST_INVALID`: root, release, policy, and every action type. Use a
field from another valid action to prove action allowlists are not a union.
Confirm an `extensions` object is rejected. Keep an existing removed field in
the same payload and assert `LEGACY_FIELD_NOT_SUPPORTED` still wins.

**Step 2: Verify RED**

Run:

```bash
flutter test --no-pub test/unit/v3/manifest_validator_test.dart
```

Expected: the new cases return normally because unknown fields are currently
ignored.

**Step 3: Implement exact allowlists with safe paths**

In `ManifestSchema`, validate exact keys for:

```text
$: schemaVersion appId channel releases
release: version buildNumber channel platform architecture releaseNotes releasedAt policy actions
policy: level minSupportedVersion
openStore: type store storeUrl
openAndroidMarket: type market targetPackageName fallbackUrl
downloadPackage: type packageUrl packageType packageSizeBytes sha256
installPackage: type packagePath packageType
downloadAndInstallPackage: type packageUrl packageType packageSizeBytes sha256
openInstaller: type installerUrl installerType installerSizeBytes sha256
```

Pass paths such as `$.releases[0].actions[0]`. Encode the unknown key with
`jsonEncode` and never include its value. Run legacy scanning first.

**Step 4: Write and observe failing semantic tests**

Cover accepted build numbers `"0"`, `"42"`, and `"00042"`. Reject JSON
numbers, signed/whitespace/decimal/non-numeric strings, and integer overflow.
Cover `minSupportedVersion` lower than/equal to the release as valid and higher
than the release as `CONFIGURATION_INVALID`, including prerelease ordering.

Run the focused test and confirm each new invalid vector currently passes.

**Step 5: Implement semantic checks**

Require `buildNumber` to match `^[0-9]+$`, parse with `int.tryParse`, and be
non-negative. Validate `minSupportedVersion <= release.version` with
`VersionComparator` after both versions are syntactically valid.

**Step 6: Lock the envelope allowlist**

Add a failing signature test for an extra envelope field, then restrict the
envelope to exactly `format`, `keyId`, `issuedAt`, `expiresAt`, `payload`, and
`signature`. Expect `MANIFEST_SIGNATURE_INVALID` through the runtime boundary.

**Step 7: Verify and commit**

```bash
flutter test --no-pub \
  test/unit/v3/manifest_validator_test.dart \
  test/unit/v3/manifest_signature_test.dart \
  test/unit/v3/app_updater_manifest_source_test.dart
```

Stage only the five files above and commit:

```bash
git commit -m "fix: make manifest v3 validation fail closed"
```

### Task 2: Extract the pure Dart manifest boundary and repair the CLI

**Files:**

- Create: `lib/src/cli/cli_command_result.dart`
- Create: `lib/src/manifest/manifest_document.dart`
- Create: `lib/src/manifest/manifest_document_parser.dart`
- Create: `lib/src/manifest/remote_action_policy.dart`
- Modify: `lib/src/cli/hash_command.dart`
- Modify: `lib/src/cli/manifest_command.dart`
- Modify: `lib/src/manifest/manifest_parser.dart`
- Modify: `lib/src/manifest/remote_manifest_policy.dart`
- Modify: `test/unit/v3/cli_manifest_test.dart`
- Modify: `test/unit/v3/manifest_parser_test.dart`
- Modify: `test/unit/v3/remote_manifest_policy_test.dart`
- Create: `tool/ci/verify_cli_executable.dart`
- Modify: `test/tool/workflow_contract_test.dart`
- Modify: `.github/workflows/full-gate.yml`

**Step 1: Add a real-process CLI regression and verify RED**

Create a tool test that launches, in order:

```text
dart run flutter_app_updater --help
dart run flutter_app_updater manifest generate
dart run flutter_app_updater manifest verify <generated-file>
dart run flutter_app_updater hash pubspec.yaml
```

It must require zero exit codes, the expected help/verify text, and a lowercase
64-character digest. Run it with `dart run tool/ci/verify_cli_executable.dart`
and observe the current `dart:ui is not available` failure.

**Step 2: Remove the accidental command dependency**

Move `CliCommandResult` into its own pure Dart file. Import it from the hash,
manifest, and bin command paths. Re-run the smoke tool; it must still fail at
the manifest parser dependency, proving this is only the first boundary fix.

**Step 3: Add pure document models and parser tests**

Define internal immutable document types for manifest, release, policy, action,
and a package-owned wire platform enum. The document parser must be pure Dart,
invoke `ManifestValidator`, and own all wire enum/date/URI interpretation.

Extend parser tests so the document and Flutter parser agree on valid manifests
and errors. Observe RED before implementing each document API.

**Step 4: Convert the Flutter parser into an adapter**

Make `ManifestParser` call the document parser, then convert only document
platform/actions/policy into existing `UpdateManifest`, `UpdateCandidate`, and
`TargetPlatform` types. Do not alter the public Flutter API.

**Step 5: Share primitive remote policy**

Extract HTTPS/user-info, artifact, store host, Android package binding, and
signature-required checks into a pure Dart primitive policy. The document CLI
policy and typed runtime wrapper both delegate to it. Preserve existing error
codes and messages where tests lock them.

**Step 6: Point the CLI at the pure boundary**

`ManifestCommand.verify` parses a `ManifestDocument` and applies the document
remote policy without importing Flutter. Keep generate/sign behavior and key
handling unchanged.

**Step 7: Add the executable CI contract**

Run the smoke tool in `quality-minimum`, and lock that workflow step in
`workflow_contract_test.dart`. Keep granular Flutter CLI unit tests.

**Step 8: Verify and commit**

```bash
dart run tool/ci/verify_cli_executable.dart
flutter test --no-pub \
  test/unit/v3/cli_manifest_test.dart \
  test/unit/v3/manifest_parser_test.dart \
  test/unit/v3/remote_manifest_policy_test.dart \
  test/tool/workflow_contract_test.dart
flutter analyze --no-pub
```

Stage only the listed task files and commit:

```bash
git commit -m "fix: make manifest CLI pure Dart"
```

### Task 3: Remove credentials from Android durable background state

**Files:**

- Create: `android/src/main/kotlin/com/indiegeeker/flutter_app_updater/background/BackgroundDownloadUrlPolicy.kt`
- Modify: `lib/src/background/android_background_download_manager.dart`
- Modify: `android/src/main/kotlin/com/indiegeeker/flutter_app_updater/background/BackgroundDownloadContract.kt`
- Modify: `android/src/main/kotlin/com/indiegeeker/flutter_app_updater/background/BackgroundDownloadEventBus.kt`
- Modify: `android/src/main/kotlin/com/indiegeeker/flutter_app_updater/background/BackgroundDownloadEngine.kt`
- Modify: `android/src/main/kotlin/com/indiegeeker/flutter_app_updater/background/BackgroundDownloadStore.kt`
- Modify: `test/unit/v3/android_background_download_manager_test.dart`
- Modify: `android/src/test/kotlin/com/indiegeeker/flutter_app_updater/BackgroundDownloadPluginTest.kt`
- Modify: `android/src/test/kotlin/com/indiegeeker/flutter_app_updater/background/BackgroundDownloadEngineTest.kt`
- Modify: `android/src/test/kotlin/com/indiegeeker/flutter_app_updater/background/BackgroundDownloadStoreTest.kt`

**Step 1: Write failing Dart boundary tests**

Require direct persistent URLs containing user information, any query (including
empty `?`), or a fragment to throw `ArgumentError` before the platform call.
Keep absolute HTTPS and loopback HTTP accepted.

Run the focused test and observe the current calls reach the fake platform.

**Step 2: Implement the Dart persistent-entry policy**

Reject `uri.userInfo.isNotEmpty`, `uri.hasQuery`, and `uri.hasFragment` in
addition to the existing scheme/host rule. Use an error message that directs
publishers to a stable credential-free URL which may redirect.

**Step 3: Write failing native URL policy tests**

Specify two native predicates:

- persistent entry: no user info/query/fragment;
- transport target: no user info/fragment, HTTPS query allowed.

Both accept production HTTPS and only real loopback HTTP. Observe RED before
creating the policy file.

**Step 4: Implement native defense in depth and redirect behavior**

Move the policy out of `BackgroundDownloadEventBus.kt`. Apply the persistent
predicate when a task starts and when a record is decoded. Apply the transport
predicate to active and redirected requests. Prove a stable URL can redirect to
a query-bearing signed URL while Range/If-Range remains intact and the record
still contains only the stable URL.

**Step 5: Write failing split-root store tests**

Construct a store with separate state and artifact roots. Require:

- `task.json` exists only under state root;
- partial/APK files exist only under artifact root;
- list/reconcile/remove work across both roots;
- managed APK path validation uses only artifact root;
- legacy cleanup deletes direct old AtomicFile record remnants and associated
  artifacts, is idempotent, and does not follow symlinks or delete new-layout
  artifact directories without an old record.

**Step 6: Implement the split store**

The primary constructor accepts `stateRoot` and an optional `artifactRoot`
defaulting to the same root for simple tests. The Android context constructor
uses `noBackupFilesDir` for state and `filesDir` for artifacts. Enumerate state
tasks from the state root and validate every path against its owning root.

Clean only valid direct legacy task directories containing `task.json`,
`task.json.bak`, or `task.json.new`. Delete those direct files and the known
partial/APK files without following symlinks.

**Step 7: Verify and commit**

```bash
flutter test --no-pub test/unit/v3/android_background_download_manager_test.dart
(cd example/android && ../../android/gradlew \
  :flutter_app_updater:testDebugUnitTest \
  :flutter_app_updater:lintDebug \
  :app:processDebugMainManifest --console=plain)
```

Stage only the listed task files and commit:

```bash
git commit -m "fix: protect Android durable download credentials"
```

### Task 4: Align bilingual docs, release notes, and contract tests

**Files:**

- Modify: `README.md`
- Create/modify: `README.zh-CN.md`
- Modify: `SECURITY.md`
- Modify: `doc/security-model.md`
- Modify: `CHANGELOG.md`
- Modify: `test/tool/documentation_contract_test.dart`

**Step 1: Import the approved bilingual README baseline**

Bring the exact current main-checkout versions of `README.md`,
`README.zh-CN.md`, and `test/tool/documentation_contract_test.dart` into this
branch. Verify the documentation contract test passes before adding new wording.

**Step 2: Write failing documentation contract assertions**

Require both languages to state:

- unknown v3 fields are rejected and there is no `extensions` escape hatch;
- `buildNumber` is a non-negative decimal string and invalid input rejects the
  response;
- `minSupportedVersion` must not exceed the release version;
- Android durable URLs must be credential-free stable entries;
- a signed query URL may appear only as an in-memory HTTPS redirect;
- durable state is no-backup while APK artifacts remain FileProvider-compatible.

Also require `SECURITY.md` and `doc/security-model.md` to distinguish foreground
URL fingerprints from Android durable stable-entry persistence.

**Step 3: Verify RED, then update docs**

Run `flutter test --no-pub test/tool/documentation_contract_test.dart`, observe
the new assertions fail, then update all listed documents. Add a v3 release note
for the breaking background URL restriction, task reset, strict schema, and CLI
repair.

**Step 4: Verify and commit**

```bash
flutter test --no-pub test/tool/documentation_contract_test.dart
git diff --check
```

Stage only the six listed files and commit:

```bash
git commit -m "docs: document fail-closed update contracts"
```

### Task 5: Run the release-quality verification matrix

**Files:** None unless a test exposes a real defect; any fix must start a new
focused TDD cycle and be reviewed before inclusion.

**Step 1: Run Dart and Flutter gates**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub
flutter test --coverage --no-pub
dart doc --dry-run
(cd example && flutter analyze --no-pub && flutter test --no-pub)
dart run tool/ci/verify_cli_executable.dart
```

Apply the CI coverage awk gate and require total plus all nine critical files to
remain at least 80 percent.

**Step 2: Run Android native gates**

```bash
(cd example/android && ../../android/gradlew \
  :flutter_app_updater:testDebugUnitTest \
  :flutter_app_updater:lintDebug \
  :app:processDebugMainManifest --console=plain)
```

**Step 3: Validate the publish archive**

Run the repository publish dry-run from the committed branch and require
`Package has 0 warnings`.

**Step 4: Review final scope**

Inspect the complete branch diff, confirm only planned files changed, verify no
URL token/private key appears in source fixtures or generated output, and keep
the physical-device matrix marked `not run`.
