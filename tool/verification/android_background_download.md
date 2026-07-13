# Android background download verification

This harness provides repeatable HTTP failure modes for Android device tests. It
is intentionally local-only: the server accepts loopback IP addresses and binds
to `127.0.0.1` by default. An Android device reaches it through `adb reverse`.

The harness is test infrastructure, not a production download server. It does
not provide authentication, TLS, or access controls.

## Start the server

For protocol-only checks, start it with the deterministic built-in payload:

```bash
dart run tool/verification/android_background_download_server.dart --port 18080
```

For the install-preparation integration case, serve an APK whose package and
signing identity match the app installed on the device. The example debug APK
is suitable when the integration test is running from the same checkout:

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
- `--artifact <path>` loads the exact bytes served by `/artifact`. Without this
  option the server generates a deterministic 256 KiB payload.
- `--help` prints usage.

Invalid arguments exit with code 64. A missing artifact exits with code 66, and
an empty artifact exits with code 65.

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
| `GET /control` | Returns the active configuration, artifact URL, and length. |
| `POST /control` | Atomically applies a JSON configuration patch. |

`POST /control` requires `Content-Type: application/json`. Unknown fields,
invalid enum values, out-of-range numbers, non-object bodies, and bodies larger
than 64 KiB return 400 without changing the active configuration.

Example reset to a resumable strong-validator response:

```bash
curl -fsS http://127.0.0.1:18080/control \
  -H 'content-type: application/json' \
  -d '{"mode":"range","etagMode":"strong","etagValue":"verification-v1"}'
```

Every successful control update resets the changing-ETag request counter. The
response includes all effective values, plus `artifactUrl`, `length`, and the
lowercase hex `sha256`, so a test can pass the exact artifact identity to the
public download API and record the server state it used.

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

Record the device model, Android API level, ROM/build, battery mode, notification
permission state, and the exact control JSON used for every device run. A passing
host-side suite does not prove OEM background-execution reliability.
