# Commercial Hardening Follow-up Design

## Goal

Close the three highest-value release blockers identified in the v3 commercial
readiness review:

1. keep credentials out of Android durable background state;
2. make manifest v3 fail closed on unknown or contradictory input; and
3. make the package CLI executable in a plain Dart VM.

The existing Flutter-facing `TargetPlatform` API, UI-free core, foreground
download behavior, and public background-download lifecycle remain unchanged.

## Android durable background URLs

`AndroidBackgroundDownloadManager.start` accepts only a stable persistent entry
URL. The entry must be absolute HTTPS (or loopback HTTP in tests) and must not
contain user information, a query, or a fragment. Publishers that need expiring
CDN credentials expose a credential-free entry which redirects to a signed URL:

```text
https://updates.example.com/android/latest.apk
  -> 302 https://cdn.example.com/app.apk?signature=...&expires=...
```

The stable entry is durable. Redirect targets remain local to the active native
request and are never written back to the task record. Transport targets still
reject user information, fragments, insecure production HTTP, and HTTPS
downgrades, but HTTPS redirect targets may contain a query.

State and artifacts use separate roots:

```text
noBackupFilesDir/flutter_app_updater/background/<task-id>/task.json
filesDir/flutter_app_updater/background/<task-id>/artifact.download
filesDir/flutter_app_updater/background/<task-id>/artifact.apk
```

This prevents task state from entering Android Auto Backup while preserving the
existing `<files-path>` FileProvider installation boundary. The store keeps
path validation and per-task locking for both roots. `list` enumerates the state
root; reconciliation and installation resolve artifacts only below the artifact
root.

The pre-release single-root layout is not migrated because it may contain raw
credentials. Initialization removes legacy `task.json`/AtomicFile remnants and
their associated artifacts only from valid direct task directories. Cleanup is
idempotent and never follows symlinks. Existing tasks are intentionally reset.

## Strict manifest v3

`ManifestSchema` remains the single wire-schema choke point. Validation order is:

1. recursively reject removed legacy field names with the existing dedicated
   error code;
2. validate exact field allowlists for the root, release, policy, and each
   action type;
3. validate types, enum values, timestamps, URLs, and cross-field semantics;
4. construct runtime models only from the validated document.

Manifest v3 has no implicit extension object. Future updater fields require a
new schema version. Unknown fields return `MANIFEST_INVALID` with a JSON path
and encoded field name, never the field value.

`buildNumber`, when present, is a non-negative decimal string. It must match
`^[0-9]+$`, parse as a Dart `int`, and be at least zero. Leading zeroes remain
accepted. `policy.minSupportedVersion` must be a valid supported semantic
version and must not be newer than the containing release version.

The signed envelope also uses an exact allowlist:
`format`, `keyId`, `issuedAt`, `expiresAt`, `payload`, and `signature`.

## Pure Dart CLI boundary

The CLI must not import Flutter libraries. JSON parsing is split into a pure
Dart document layer and a Flutter adapter:

```text
JSON map
  -> ManifestDocumentParser (pure Dart)
  -> ParsedManifestDocument / parsed actions (pure Dart)
       -> shared remote action policy -> CLI verify
       -> FlutterManifestAdapter -> UpdateManifest / TargetPlatform -> runtime
```

The document parser owns all wire enum/date/action parsing and delegates strict
shape validation to `ManifestSchema`. The Flutter adapter performs only the
conversion from the document platform enum to Flutter `TargetPlatform` and from
document actions to the current public action classes. Remote trust checks use
one primitive, pure Dart policy shared by the document and typed runtime
wrappers.

`CliCommandResult` moves to its own pure Dart file so `HashCommand` no longer
imports `ManifestCommand`. The public Flutter API remains source-compatible.

## Error handling

- Unknown fields and invalid build numbers: `MANIFEST_INVALID`.
- Invalid or contradictory minimum supported versions: preserve the existing
  `CONFIGURATION_INVALID` mapping.
- Unsupported actions retain `UNSUPPORTED_ACTION_TYPE`.
- A persistent background URL with credentials fails synchronously with
  `ArgumentError` before a platform call; native code independently applies the
  same rule.
- Legacy durable records are removed rather than copied into the new store.
- CLI failures remain concise and never print manifest field values, signed URL
  tokens, private keys, or local sensitive paths beyond the explicit input path.

## Verification

Every behavior change follows red-green-refactor.

- Dart tests cover strict URL rejection, exact manifest allowlists, build
  numbers, minimum-version ordering, envelope allowlists, and runtime mapping.
- Kotlin tests cover persistent versus transport URL policy, split roots,
  legacy cleanup, redirect queries remaining memory-only, and install paths.
- A real process gate runs `dart run flutter_app_updater --help`, manifest
  generate/verify, and hash. Flutter unit tests alone are not accepted as CLI
  proof.
- Workflow contract tests require the executable gate in the minimum-Flutter
  CI job.
- Final verification includes formatting, analysis, root/example tests,
  coverage, Dartdoc, Android native tests/lint/manifest, CLI smoke tests, and a
  clean publish dry-run.

Physical Android device/OEM qualification remains a separate manual release
gate and must not be inferred from automated tests.
