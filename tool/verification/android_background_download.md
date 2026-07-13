# Android background download verification

This harness provides repeatable HTTP failure modes for Android device tests. It
is intentionally local-only: the server accepts loopback IP addresses and binds
to `127.0.0.1` by default. An Android device reaches it through `adb reverse`.

The harness is test infrastructure, not a production download server. It does
not provide authentication, TLS, or access controls.

## Start the server

For manual host-side protocol checks only, start it with the deterministic
built-in payload:

```bash
dart run tool/verification/android_background_download_server.dart --port 18080
```

Do not use that built-in payload for the device integration suite. The full
`android_background_download_test.dart` suite must serve a real APK whose
package and signing identity match the app installed on the device. The example
debug APK is suitable when the integration test is running from the same
checkout:

```bash
cd example
flutter build apk --debug
cd ..
dart run tool/verification/android_background_download_server.dart \
  --port 18080 \
  --artifact example/build/app/outputs/flutter-apk/app-debug.apk
```

Then expose the loopback port to the attached device and run the integration
test in another terminal:

```bash
adb reverse tcp:18080 tcp:18080
cd example
flutter test integration_test/android_background_download_test.dart -d <device-id>
```

Press Ctrl+C to stop the server. SIGINT and SIGTERM stop accepting new requests
and close the HTTP server gracefully.

CLI options:

- `--host <ip>` accepts loopback IP addresses only (default `127.0.0.1`).
- `--port <0-65535>` selects the port (default `18080`; `0` chooses a free
  port).
- `--artifact <path>` loads the exact bytes served by `/artifact`. The path must
  be a regular file and is limited to 512 MiB because the harness keeps the
  artifact in memory. Without this option the server generates a deterministic
  256 KiB payload.
- `--help` prints usage.

Invalid arguments exit with code 64. A missing, non-file, or oversized artifact
exits with code 66, and an empty artifact exits with code 65.

## Stable HTTP interface

The device test should always download this URL after `adb reverse`:

```text
http://127.0.0.1:18080/artifact
```

The control interface is host-side and takes effect before its response is
returned:

| Request | Purpose |
| --- | --- |
| `GET /healthz` | Returns `{"status":"ok","length":...,"sha256":"..."}`. |
| `GET /artifact` | Serves the artifact using the active failure mode. |
| `GET /control` | Returns the active configuration, artifact identity, and response observations. |
| `POST /control` | Atomically applies a JSON configuration patch and clears observations. |

`POST /control` requires `Content-Type: application/json`. Unknown fields,
invalid enum values, out-of-range numbers, non-object bodies, and bodies larger
than 64 KiB return 400 without changing the active configuration.

Example reset to a resumable strong-validator response:

```bash
curl -fsS http://127.0.0.1:18080/control \
  -H 'content-type: application/json' \
  -d '{"mode":"range","etagMode":"strong","etagValue":"verification-v1"}'
```

Every successful control update resets the changing-ETag request counter and
clears `observations`; the POST response therefore contains an empty
`observations` array. A rejected update changes neither configuration nor
observations. The response includes all effective values, plus `artifactUrl`,
`length`, and the lowercase hex `sha256`, so a test can pass the exact artifact
identity to the public download API and record the server state it used.

Each `/artifact` response appends one observation synchronously when its
response decision is made:

```json
{
  "sequence": 1,
  "requestRange": "bytes=65536-",
  "requestIfRange": "\"verification-v1\"",
  "responseStatus": 206,
  "responseContentRange": "bytes 65536-99999/100000",
  "responseEtag": "\"verification-v1\"",
  "sentBytes": 34464
}
```

`requestRange`, `requestIfRange`, and `responseContentRange` are `null` when
absent. `sequence` resets to 1 after every successful control update.
`sentBytes` records the body-byte count selected at that linear response
decision; it is zero for 416 and equals the configured cutoff for disconnect.
Tests can read `observations` with `GET /control` to prove that a device issued
the expected Range/If-Range request and received the expected branch.

## Failure modes

Set `mode` with `POST /control`:

| `mode` | Behavior |
| --- | --- |
| `range` | No Range returns 200. `Range: bytes=N-` returns a precise 206. An offset at or beyond EOF returns `416` with `Content-Range: bytes */L`. |
| `ignoreRange` | Returns the complete body as 200 even when Range is present. |
| `exact416` | Always returns `416` with `Content-Range: bytes */L`. |
| `malformed416` | Always returns `416` with `Content-Range: bytes */not-a-number`. |
| `disconnect` | Below EOF, declares the full Content-Length, writes `disconnectAfterBytes`, then destroys the socket. At exact EOF, sends every artifact byte as chunked data but omits the terminating zero chunk, so the client retains full durable bytes while reporting a transfer error. |
| `slow` | Writes `chunkSize` bytes at a time with `delayPerChunkMs` between chunks. |
| `oversizedChunked` | Uses chunked transfer encoding and appends `oversizedBytes` beyond the artifact. |

In `range` mode, `If-Range` uses strong comparison. A missing `If-Range` is
accepted; a mismatched validator or a weak current validator causes a clean 200
response instead of appending.

Configure validators with `etagMode`:

- `strong` returns `"<etagValue>"`.
- `weak` returns `W/"<etagValue>"`.
- `changing` returns a new strong validator for each artifact request, starting
  at `"<etagValue>-1"` after each successful control update.

The numeric controls are:

- `disconnectAfterBytes`: 1 through artifact length. A value equal to the
  artifact length selects the incomplete chunked-termination behavior used by
  the deterministic EOF 416 recovery case.
- `delayPerChunkMs`: 0 through 60000.
- `chunkSize`: 1 through 1 MiB.
- `oversizedBytes`: 1 through 64 MiB.

`etagValue` accepts 1-128 ASCII letters, digits, dots, dashes, or underscores.

## Reproducible resume sequences

### Disconnect, then resume with 206

1. Configure `{"mode":"disconnect","etagMode":"strong",
   "disconnectAfterBytes":65536}`.
2. Start a background download and wait for the connection to fail.
3. Configure `{"mode":"range","etagMode":"strong"}` without changing
   `etagValue`.
4. Resume. The request's matching Range and If-Range receive a precise 206.

### Validator change, then clean restart

1. Create a checkpoint using strong `etagValue` `verification-v1`.
2. Configure `{"mode":"range","etagMode":"strong",
   "etagValue":"verification-v2"}`.
3. Resume. If-Range no longer matches, so the server returns a clean 200.

Alternatively, set `etagMode` to `changing`: a validator captured from the first
request is guaranteed not to match the next request.

### Complete from exact 416

1. Configure `{"mode":"disconnect","etagMode":"strong",
   "disconnectAfterBytes":<length>}` using the exact `length` returned by
   `/control`.
2. Start the download. The server delivers the complete payload but omits the
   final chunk terminator, so the client records a transfer error with durable
   bytes equal to the expected size instead of treating the response as a clean
   completion.
3. Configure `{"mode":"exact416","etagMode":"strong"}` without changing
   `etagValue`, then resume. The preserved checkpoint requests
   `Range: bytes=<length>-` and receives `Content-Range: bytes */<length>`.
4. Verify that the engine hashes the complete local artifact and transitions to
   completed. Use `malformed416` separately to verify that malformed completion
   evidence is rejected and does not loop.

## Automated server tests

Run the host-side contract suite before device verification:

```bash
flutter test test/tool/android_background_download_server_test.dart
```

The suite covers clean 200, precise 206, ignored Range, If-Range fallback,
strong/weak/changing ETags, exact and malformed 416, controlled disconnect,
full-payload incomplete chunk termination, slow chunks, oversized chunked
bodies, control validation, health state, and CLI validation.

Run the native Android unit, lint, and merged-manifest gate from
`example/android`:

```bash
../../android/gradlew :flutter_app_updater:testDebugUnitTest :flutter_app_updater:lintDebug :app:processDebugMainManifest
```

Then build the matching APK, start the server with `--artifact`, apply
`adb reverse`, and run the complete device suite as shown above. A passing
host-side server suite with the built-in payload is not a substitute for the
same-package, same-signature APK device run.

## Device evidence matrix

Do not generalize from an emulator or a single vendor. Before release, record
at least one Pixel/AOSP reference, one API 33-or-lower physical device, one API
34-or-higher physical device, and two Chinese OEM families. Use exact model,
API level, ROM name/build, patch level, battery mode, notification state, and
the commit tested; leave a row marked `not run` rather than inferring a result.

| Device/model | API | ROM/build | Battery mode | Notifications | Commit | Result/notes |
| --- | ---: | --- | --- | --- | --- | --- |
| Pixel/AOSP reference |  |  | default/restricted | allowed/denied |  | not run |
| API 33 or lower |  |  | default/restricted | allowed/denied |  | not run |
| API 34 or higher |  |  | default/restricted | allowed/denied |  | not run |
| Chinese OEM family 1 |  |  | default/restricted | allowed/denied |  | not run |
| Chinese OEM family 2 |  |  | default/restricted | allowed/denied |  | not run |

Use one row per actual scenario run rather than collapsing a device into one
summary result:

| Run ID | Device/API/ROM | Battery mode | Notifications | Scenario | Control JSON or setup | Expected state | Observed state | Result | Evidence link |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  | default/restricted | allowed/denied |  |  |  |  | not run |  |

Minimum platform evidence:

| API | Evidence to record |
| ---: | --- |
| 21 | minSdk build plus user-visible start-service behavior |
| 26 | foreground channel, icon, notification, and immediate foreground transition |
| 33 | visible user start with notification allowed and denied |
| 34 | UIDT internet network, notification, and schedule rejection handling |
| 35 | UIDT behavior without assuming a `dataSync` foreground fallback |
| 36 | stop reason and job lifecycle when an API 36 device is available |

For every applicable device, exercise background and locked-screen transfer,
network switch/loss, Flutter engine detach, process kill, recents swipe, Task
Manager Stop, force-stop, reboot, notification denial, retry/cancel, Range with
strong ETag, validator change, exact and malformed 416, disk full, hash
failure, and explicit user-triggered install. Query `/control` after each
protocol case and retain its request/response observations with the result.
For non-server faults, record the exact fixture too: for example the storage
quota or fill procedure used for disk-full, the byte/hash mutation used for
integrity failure, and the exact adb or system UI action used for process kill,
Task Manager Stop, or force-stop.

Record the device model, Android API level, ROM/build, battery mode, notification
permission state, and the exact control JSON used for every device run. A passing
host-side suite does not prove OEM background-execution reliability.

Only after the matrix contains real results may release notes say:

> On the devices and ROM versions listed in the verification matrix,
> interruption did not corrupt the artifact, and the task could be recovered
> after the user reopened the app.

This is evidence for those recorded devices and versions, not a guarantee of
uninterrupted background execution across an OEM family.
