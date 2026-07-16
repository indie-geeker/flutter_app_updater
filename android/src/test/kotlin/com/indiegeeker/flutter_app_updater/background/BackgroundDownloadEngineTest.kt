package com.indiegeeker.flutter_app_updater.background

import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.net.ConnectException
import java.nio.file.Files
import java.security.MessageDigest
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLHandshakeException
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.json.JSONObject

internal class BackgroundDownloadEngineTest {
  private val roots = mutableListOf<File>()

  @AfterTest
  fun cleanUp() {
    roots.forEach(File::deleteRecursively)
  }

  @Test
  fun everySharedResumeVectorDrivesTheNativeEngineFromJson() {
    val vectors = sharedVectors()
    vectors.keys().asSequence().forEach { name ->
      executeSharedVector(name, vectors.getJSONObject(name))
    }
  }

  @Test
  fun sharedResumeFixtureHasAnExplicitNativeMapping() {
    val fixture = sharedVectors()

    val nativeOutcomeMapping = mapOf(
      "clean_200_identity_exact" to "complete",
      "clean_200_short_body" to "integrity-failure",
      "clean_200_hash_mismatch" to "hash-mismatch",
      "strong_etag_resume" to "complete",
      "weak_etag_restart" to "clean-restart",
      "resume_wrong_start" to "protocol-failure",
      "resume_wrong_body_length" to "protocol-failure",
      "resume_changed_total" to "protocol-failure",
      "range_ignored_200" to "complete",
      "range_416_exact_eof" to "complete",
      "range_416_overshoot" to "one-clean-retry",
      "range_416_malformed" to "one-clean-retry",
      "gzip_rejected" to "protocol-failure",
      "redirect_resume" to "follow",
      "redirect_https_downgrade" to "protocol-failure",
      "uncheckpointed_tail" to "truncate-to-checkpoint",
      "checkpoint_ahead" to "clean-restart",
    )
    assertEquals(fixture.keys().asSequence().toSet(), nativeOutcomeMapping.keys)
    nativeOutcomeMapping.forEach { (name, expectedOutcome) ->
      assertEquals(expectedOutcome, fixture.getJSONObject(name).getJSONObject("expected").getString("outcome"), name)
    }

    val clean = fixture.getJSONObject("clean_200_identity_exact")
    val cleanBody = clean.getJSONObject("response").getString("body").toByteArray()
    val cleanEnv = environment(
      expected = cleanBody,
      responses = listOf(response(200, cleanBody, mapOf("Content-Length" to cleanBody.size.toString()))),
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, cleanEnv.engine.execute(TASK_ID).outcome)
    assertEquals("identity", cleanEnv.factory.requests.single().headers["Accept-Encoding"])

    val resumedBody = "hello world".toByteArray()
    val resumeEnv = environment(
      expected = resumedBody,
      responses = listOf(
        response(
          206,
          " world".toByteArray(),
          mapOf(
            "Content-Range" to "bytes 5-10/11",
            "Content-Length" to "6",
            "ETag" to "\"v1\"",
          ),
        ),
      ),
      downloaded = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, resumeEnv.engine.execute(TASK_ID).outcome)
    assertEquals("bytes=5-", resumeEnv.factory.requests.single().headers["Range"])
    assertEquals("\"v1\"", resumeEnv.factory.requests.single().headers["If-Range"])

    val weakEnv = environment(
      expected = "fresh-package".toByteArray(),
      responses = listOf(response(200, "fresh-package".toByteArray())),
      downloaded = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "W/\"v1\"",
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, weakEnv.engine.execute(TASK_ID).outcome)
    assertNull(weakEnv.factory.requests.single().headers["Range"])

    assertProtocolFailure(
      expected = resumedBody,
      response = response(206, " world".toByteArray(), mapOf("Content-Range" to "bytes 0-5/11")),
      checkpoint = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )
    assertProtocolFailure(
      expected = resumedBody,
      response = response(
        206,
        " world".toByteArray(),
        mapOf("Content-Range" to "bytes 5-10/11", "Content-Length" to "5"),
      ),
      checkpoint = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )
    assertProtocolFailure(
      expected = resumedBody,
      response = response(
        206,
        " world".toByteArray(),
        mapOf("Content-Range" to "bytes 5-10/11", "Content-Length" to "6"),
      ),
      checkpoint = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )
    assertProtocolFailure(
      expected = resumedBody,
      response = response(
        206,
        " world".toByteArray(),
        mapOf("Content-Range" to "bytes 5-10/11", "Content-Length" to "6", "ETag" to "\"v2\""),
      ),
      checkpoint = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )
    assertProtocolFailure(
      expected = resumedBody,
      response = response(206, " world!".toByteArray(), mapOf("Content-Range" to "bytes 5-11/12")),
      checkpoint = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )

    val ignoredEnv = environment(
      expected = "fresh-package".toByteArray(),
      responses = listOf(response(200, "fresh-package".toByteArray())),
      downloaded = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, ignoredEnv.engine.execute(TASK_ID).outcome)
    assertEquals(1, ignoredEnv.factory.requests.size)
    assertNotNull(ignoredEnv.factory.requests[0].headers["Range"])

    val eofEnv = environment(
      expected = resumedBody,
      responses = listOf(response(416, byteArrayOf(), mapOf("Content-Range" to "bytes */11"))),
      downloaded = resumedBody,
      checkpointBytes = 11,
      etag = "\"v1\"",
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, eofEnv.engine.execute(TASK_ID).outcome)

    val retry416 = environment(
      expected = resumedBody,
      responses = listOf(
        response(416, byteArrayOf(), mapOf("Content-Range" to "not-a-range")),
        response(200, resumedBody),
      ),
      downloaded = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, retry416.engine.execute(TASK_ID).outcome)
    assertEquals(2, retry416.factory.requests.size)

    val overshootBody = "hello world!".toByteArray()
    val overshoot = environment(
      expected = overshootBody,
      responses = listOf(
        response(416, byteArrayOf(), mapOf("Content-Range" to "bytes */11")),
        response(200, overshootBody),
      ),
      downloaded = overshootBody,
      checkpointBytes = overshootBody.size.toLong(),
      etag = "\"v1\"",
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, overshoot.engine.execute(TASK_ID).outcome)
    assertEquals(2, overshoot.factory.requests.size)

    assertProtocolFailure(
      expected = "package-bytes".toByteArray(),
      response = response(200, "package-bytes".toByteArray(), mapOf("Content-Encoding" to "gzip")),
    )

    val redirectEnv = environment(
      expected = resumedBody,
      responses = listOf(
        response(302, byteArrayOf(), mapOf("Location" to "https://cdn.example.test/app.apk")),
        response(
          206,
          " world".toByteArray(),
          mapOf("Content-Range" to "bytes 5-10/11", "Content-Length" to "6", "ETag" to "\"v1\""),
        ),
      ),
      downloaded = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, redirectEnv.engine.execute(TASK_ID).outcome)
    assertEquals("bytes=5-", redirectEnv.factory.requests[1].headers["Range"])

    val downgrade = environment(
      expected = resumedBody,
      responses = listOf(response(302, byteArrayOf(), mapOf("Location" to "http://cdn.example.test/app.apk"))),
      downloaded = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )
    assertEquals(BackgroundDownloadExecutionOutcome.failed, downgrade.engine.execute(TASK_ID).outcome)
    assertFailure(downgrade.store.read(TASK_ID), "PACKAGE_DOWNLOAD_FAILED", "protocol_error")

    val tailEnv = environment(
      expected = resumedBody,
      responses = listOf(
        response(
          206,
          " world".toByteArray(),
          mapOf("Content-Range" to "bytes 5-10/11", "Content-Length" to "6", "ETag" to "\"v1\""),
        ),
      ),
      downloaded = "helloXX".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, tailEnv.engine.execute(TASK_ID).outcome)
    assertEquals("hello world", tailEnv.store.apkFile(TASK_ID).readText())

    val aheadEnv = environment(
      expected = resumedBody,
      responses = listOf(response(200, resumedBody)),
      downloaded = "hell".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, aheadEnv.engine.execute(TASK_ID).outcome)
    assertNull(aheadEnv.factory.requests.single().headers["Range"])
  }

  @Test
  fun exactSizeHashAndMaxBytesAreEnforced() {
    val short = environment(
      expected = "hello world".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray(), mapOf("Content-Length" to "11"))),
    )
    assertEquals(BackgroundDownloadExecutionOutcome.failed, short.engine.execute(TASK_ID).outcome)
    assertFailure(short.store.read(TASK_ID), "PACKAGE_DOWNLOAD_FAILED", "integrity_error")
    assertFalse(short.store.partialFile(TASK_ID).exists())
    assertFalse(short.store.apkFile(TASK_ID).exists())

    val hashMismatch = environment(
      expected = "hello".toByteArray(),
      expectedHash = sha256("other".toByteArray()),
      responses = listOf(response(200, "hello".toByteArray())),
    )
    assertEquals(BackgroundDownloadExecutionOutcome.failed, hashMismatch.engine.execute(TASK_ID).outcome)
    assertFailure(hashMismatch.store.read(TASK_ID), "PACKAGE_HASH_MISMATCH", "hash_mismatch")
    assertFalse(hashMismatch.store.partialFile(TASK_ID).exists())
    assertFalse(hashMismatch.store.apkFile(TASK_ID).exists())

    val max = environment(
      expected = "hello".toByteArray(),
      maxBytes = 4,
      responses = listOf(response(200, "hello".toByteArray())),
      createInvalidRecordDirectly = true,
    )
    assertEquals(BackgroundDownloadExecutionOutcome.failed, max.engine.execute(TASK_ID).outcome)
    assertFailure(max.store.read(TASK_ID), "PACKAGE_TOO_LARGE", "size_limit_exceeded")
    assertFalse(max.store.partialFile(TASK_ID).exists())
    assertFalse(max.store.apkFile(TASK_ID).exists())
  }

  @Test
  fun diskPreflightUsesRemainingBytesPlusSixtyFourMibOrFivePercent() {
    val expectedSize = 100L * 1024 * 1024
    val available = expectedSize + 64L * 1024 * 1024 - 1
    val env = environment(
      expected = ByteArray(1),
      recordExpectedSize = expectedSize,
      expectedHash = "0".repeat(64),
      responses = emptyList(),
      availableBytes = available,
    )

    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, env.engine.execute(TASK_ID).outcome)
    assertFailure(env.store.read(TASK_ID), "BACKGROUND_STORAGE_UNAVAILABLE", "insufficient_storage")
    assertTrue(env.factory.requests.isEmpty())
  }

  @Test
  fun retryIsBoundedAndDistinguishesNetworkFromWriteFailure() {
    val delays = mutableListOf<Long>()
    val network = environment(
      expected = "hello".toByteArray(),
      responses = listOf(
        ConnectException("offline"),
        response(503, byteArrayOf()),
        ConnectException("still offline"),
      ),
      sleeper = { delays += it },
    )

    assertEquals(BackgroundDownloadExecutionOutcome.waitingForNetwork, network.engine.execute(TASK_ID).outcome)
    assertEquals(3, network.factory.requests.size)
    assertEquals(listOf(250L, 500L), delays)
    assertFailure(network.store.read(TASK_ID), "PACKAGE_DOWNLOAD_FAILED", "network_error")

    val write = environment(
      expected = "hello".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray())),
      artifactWriterFactory = { throw BackgroundDownloadWriteException("disk full") },
    )
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, write.engine.execute(TASK_ID).outcome)
    assertFailure(write.store.read(TASK_ID), "BACKGROUND_STORAGE_UNAVAILABLE", "storage_write_error")
    assertEquals(1, write.factory.requests.size)

    val genericNetworkIo = environment(
      expected = "hello".toByteArray(),
      responses = listOf(IOException("connection reset"), IOException("connection reset"), IOException("connection reset")),
    )
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForNetwork, genericNetworkIo.engine.execute(TASK_ID).outcome)

    val genericWriteIo = environment(
      expected = "hello".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray())),
      artifactWriterFactory = { throw IOException("disk full") },
    )
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, genericWriteIo.engine.execute(TASK_ID).outcome)
  }

  @Test
  fun duplicateExecutionDoesNotRunConcurrently() {
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val env = environment(
      expected = "hello".toByteArray(),
      responses = listOf(
        response(200, "hello".toByteArray(), beforeOpen = {
          entered.countDown()
          assertTrue(release.await(5, TimeUnit.SECONDS))
        }),
      ),
    )
    val executor = Executors.newSingleThreadExecutor()
    try {
      val first = executor.submit<BackgroundDownloadExecutionResult> { env.engine.execute(TASK_ID) }
      assertTrue(entered.await(5, TimeUnit.SECONDS))
      assertEquals(BackgroundDownloadExecutionOutcome.alreadyRunning, env.engine.execute(TASK_ID).outcome)
      release.countDown()
      assertEquals(BackgroundDownloadExecutionOutcome.completed, first.get(5, TimeUnit.SECONDS).outcome)
      assertEquals(1, env.factory.requests.size)
    } finally {
      release.countDown()
      executor.shutdownNow()
    }
  }

  @Test
  fun systemStopCheckpointsAndPausesWhileCancelRemainsAuthoritative() {
    var stop = BackgroundDownloadStopReason.none
    val clock = FakeClock()
    val body = ByteArray(5 * 1024 * 1024) { 7 }
    val stopped = environment(
      expected = body,
      responses = listOf(
        response(200, body, mapOf("ETag" to "\"v1\""), chunkSize = 1024 * 1024) {
          clock.advance(100)
          if (it >= 1024 * 1024) stop = BackgroundDownloadStopReason.system(17)
        },
      ),
      clock = clock,
      stopSignal = { stop },
    )
    assertEquals(BackgroundDownloadExecutionOutcome.pausedBySystem, stopped.engine.execute(TASK_ID).outcome)
    val paused = stopped.store.read(TASK_ID)
    assertEquals(BackgroundDownloadStatus.pausedBySystem, paused.status)
    assertTrue(paused.downloadedBytes > 0)
    assertEquals(17, paused.lastStopReason)

    var cancelStop = BackgroundDownloadStopReason.none
    lateinit var canceled: TestEnvironment
    canceled = environment(
      expected = body,
      responses = listOf(
        response(200, body, mapOf("ETag" to "\"v1\""), chunkSize = 1024 * 1024) {
          if (it >= 1024 * 1024) {
            canceled.coordinator.cancel(TASK_ID)
            cancelStop = BackgroundDownloadStopReason.cancel
          }
        },
      ),
      stopSignal = { cancelStop },
    )
    assertEquals(BackgroundDownloadExecutionOutcome.canceled, canceled.engine.execute(TASK_ID).outcome)
    assertEquals(BackgroundDownloadStatus.canceled, canceled.store.read(TASK_ID).status)
    assertFalse(canceled.store.partialFile(TASK_ID).exists())
    assertFalse(canceled.store.apkFile(TASK_ID).exists())
  }

  @Test
  fun executionCanUseSchedulerBoundConnectionAndStopSeams() {
    val env = environment(
      expected = "hello".toByteArray(),
      responses = emptyList(),
    )
    val assignedNetworkFactory = FakeConnectionFactory(
      mutableListOf(response(200, "hello".toByteArray())),
    )

    val result = env.engine.execute(
      TASK_ID,
      connectionFactory = assignedNetworkFactory,
      stopSignal = { BackgroundDownloadStopReason.none },
    )

    assertEquals(BackgroundDownloadExecutionOutcome.completed, result.outcome)
    assertEquals(1, assignedNetworkFactory.requests.size)
    assertTrue(env.factory.requests.isEmpty())
  }

  @Test
  fun stableEntryRedirectsToSignedTransportWithoutPersistingCredentials() {
    val stableEntry = "https://downloads.example.test/app.apk"
    val signedTarget = "https://cdn.example.test/app.apk?token=secret-token"
    val expected = "hello world".toByteArray()
    val env = environment(
      expected = expected,
      packageUrl = stableEntry,
      responses = listOf(
        response(302, byteArrayOf(), mapOf("Location" to signedTarget)),
        response(
          206,
          " world".toByteArray(),
          mapOf(
            "Content-Range" to "bytes 5-10/11",
            "Content-Length" to "6",
            "ETag" to "\"v1\"",
          ),
        ),
      ),
      downloaded = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )

    val result = env.engine.execute(TASK_ID)

    assertEquals(BackgroundDownloadExecutionOutcome.completed, result.outcome)
    assertEquals(listOf(stableEntry, signedTarget), env.factory.requests.map { it.url })
    assertTrue(env.factory.requests.all { it.headers["Range"] == "bytes=5-" })
    assertTrue(env.factory.requests.all { it.headers["If-Range"] == "\"v1\"" })
    val completed = env.store.read(TASK_ID)
    assertEquals(stableEntry, completed.packageUrl)
    assertFalse(completed.toJson().toString().contains("secret-token"))
    assertFalse(completed.toJson().toString().contains("?token="))
  }

  @Test
  fun httpsRedirectToLoopbackHttpIsRejectedBeforeOpeningDowngradeTarget() {
    val stableEntry = "https://downloads.example.test/app.apk"
    val loopbackTarget = "http://127.0.0.1/app.apk"
    val expected = "package".toByteArray()
    val env = environment(
      expected = expected,
      packageUrl = stableEntry,
      responses = listOf(
        response(302, byteArrayOf(), mapOf("Location" to loopbackTarget)),
        response(200, expected),
      ),
    )

    val result = env.engine.execute(TASK_ID)

    assertEquals(listOf(stableEntry), env.factory.requests.map { it.url })
    assertEquals(BackgroundDownloadExecutionOutcome.failed, result.outcome)
    assertFailure(env.store.read(TASK_ID), "PACKAGE_DOWNLOAD_FAILED", "protocol_error")
  }

  @Test
  fun httpsHopRedirectToLoopbackHttpIsRejectedBeforeOpeningDowngradeTarget() {
    val loopbackEntry = "http://127.0.0.1/start.apk"
    val httpsHop = "https://downloads.example.test/app.apk"
    val loopbackTarget = "http://127.0.0.1/final.apk"
    val expected = "package".toByteArray()
    val env = environment(
      expected = expected,
      packageUrl = loopbackEntry,
      responses = listOf(
        response(302, byteArrayOf(), mapOf("Location" to httpsHop)),
        response(302, byteArrayOf(), mapOf("Location" to loopbackTarget)),
        response(200, expected),
      ),
    )

    val result = env.engine.execute(TASK_ID)

    assertEquals(listOf(loopbackEntry, httpsHop), env.factory.requests.map { it.url })
    assertEquals(BackgroundDownloadExecutionOutcome.failed, result.outcome)
    assertFailure(env.store.read(TASK_ID), "PACKAGE_DOWNLOAD_FAILED", "protocol_error")
  }

  @Test
  fun loopbackHttpRedirectRemainsAllowedForDevelopmentTransport() {
    val loopbackEntry = "http://127.0.0.1/start.apk"
    val loopbackTarget = "http://127.255.1.2/app.apk"
    val expected = "package".toByteArray()
    val env = environment(
      expected = expected,
      packageUrl = loopbackEntry,
      responses = listOf(
        response(302, byteArrayOf(), mapOf("Location" to loopbackTarget)),
        response(200, expected),
      ),
    )

    val result = env.engine.execute(TASK_ID)

    assertEquals(BackgroundDownloadExecutionOutcome.completed, result.outcome)
    assertEquals(listOf(loopbackEntry, loopbackTarget), env.factory.requests.map { it.url })
  }

  @Test
  fun redirectsAreLimitedToFiveAndKeepResumeHeaders() {
    val maxRedirects = sharedVectors().getJSONObject("redirect_resume")
      .getJSONObject("expected").getInt("maxRedirects")
    val redirects = (1..maxRedirects + 1).map { index ->
      response(302, byteArrayOf(), mapOf("Location" to "https://cdn$index.example.test/app.apk"))
    }
    val env = environment(
      expected = "hello world".toByteArray(),
      responses = redirects,
      downloaded = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )

    assertEquals(BackgroundDownloadExecutionOutcome.failed, env.engine.execute(TASK_ID).outcome)
    assertFailure(env.store.read(TASK_ID), "PACKAGE_DOWNLOAD_FAILED", "protocol_error")
    assertEquals(maxRedirects + 1, env.factory.requests.size)
    assertTrue(env.factory.requests.all { it.headers["Range"] == "bytes=5-" })
    assertTrue(env.factory.requests.all { it.headers["If-Range"] == "\"v1\"" })
  }

  @Test
  fun engineUsesTheSameIpv4LoopbackPolicyAsThePluginBoundary() {
    val body = "package".toByteArray()
    val env = environment(
      expected = body,
      responses = listOf(response(200, body)),
      packageUrl = "http://127.255.1.2/app.apk",
    )

    assertEquals(BackgroundDownloadExecutionOutcome.completed, env.engine.execute(TASK_ID).outcome)
  }

  @Test
  fun retryableStreamFailuresCheckpointLatestStrongEtagTail() {
    val mib = 1024 * 1024
    val body = ByteArray(4 * mib) { 9 }
    val env = environment(
      expected = body,
      responses = listOf(
        response(200, body, mapOf("ETag" to "\"v1\""), chunkSize = mib, failureAfterBytes = mib),
        response(
          206,
          body.copyOfRange(mib, body.size),
          mapOf(
            "Content-Range" to "bytes $mib-${body.size - 1}/${body.size}",
            "Content-Length" to "${body.size - mib}",
            "ETag" to "\"v1\"",
          ),
          chunkSize = mib,
          failureAfterBytes = mib,
        ),
        response(
          206,
          body.copyOfRange(2 * mib, body.size),
          mapOf(
            "Content-Range" to "bytes ${2 * mib}-${body.size - 1}/${body.size}",
            "Content-Length" to "${body.size - 2 * mib}",
            "ETag" to "\"v1\"",
          ),
          chunkSize = mib,
          failureAfterBytes = mib,
        ),
      ),
    )

    assertEquals(BackgroundDownloadExecutionOutcome.waitingForNetwork, env.engine.execute(TASK_ID).outcome)
    assertEquals(3L * mib, env.store.read(TASK_ID).downloadedBytes)
    assertEquals(listOf(null, "bytes=$mib-", "bytes=${2 * mib}-"), env.factory.requests.map { it.headers["Range"] })
  }

  @Test
  fun oneCleanRetryBudgetSurvivesNetworkRetryAttempts() {
    val env = environment(
      expected = "hello world".toByteArray(),
      responses = listOf(
        response(416, byteArrayOf(), mapOf("Content-Range" to "not-a-range")),
        ConnectException("offline after clean restart"),
        response(416, byteArrayOf(), mapOf("Content-Range" to "not-a-range")),
      ),
      downloaded = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )

    assertEquals(BackgroundDownloadExecutionOutcome.failed, env.engine.execute(TASK_ID).outcome)
    assertFailure(env.store.read(TASK_ID), "PACKAGE_DOWNLOAD_FAILED", "protocol_error")
    assertEquals(3, env.factory.requests.size)
  }

  @Test
  fun repeatedRangeIgnored200ResponsesDoNotSpend416RetryBudget() {
    val mib = 1024 * 1024
    val body = ByteArray(3 * mib) { 11 }
    val env = environment(
      expected = body,
      responses = listOf(
        response(200, body, mapOf("ETag" to "\"v2\""), chunkSize = mib, failureAfterBytes = mib),
        response(200, body, mapOf("ETag" to "\"v2\""), chunkSize = mib, failureAfterBytes = mib),
        response(200, body, mapOf("ETag" to "\"v2\""), chunkSize = mib),
      ),
      downloaded = "hello".toByteArray(),
      checkpointBytes = 5,
      etag = "\"v1\"",
    )

    assertEquals(BackgroundDownloadExecutionOutcome.completed, env.engine.execute(TASK_ID).outcome)
    assertEquals(3, env.factory.requests.size)
    assertEquals("bytes=5-", env.factory.requests[0].headers["Range"])
    assertEquals("bytes=$mib-", env.factory.requests[1].headers["Range"])
    assertEquals("bytes=$mib-", env.factory.requests[2].headers["Range"])
  }

  @Test
  fun observerFailuresDoNotChangeDownloadState() {
    val body = ByteArray(5 * 1024 * 1024) { 4 }
    val env = environment(
      expected = body,
      responses = listOf(response(200, body, mapOf("ETag" to "\"v1\""), chunkSize = 1024 * 1024)),
      onProgress = { error("progress observer failed") },
      checkpointListener = { error("checkpoint observer failed") },
    )

    assertEquals(BackgroundDownloadExecutionOutcome.completed, env.engine.execute(TASK_ID).outcome)
    assertEquals(BackgroundDownloadStatus.completed, env.store.read(TASK_ID).status)
  }

  @Test
  fun cancellationDuringHashVerificationCannotCompleteTask() {
    val body = ByteArray(2 * 1024 * 1024) { 2 }
    lateinit var env: TestEnvironment
    var canceled = false
    env = environment(
      expected = body,
      responses = listOf(response(200, body)),
      verificationChunkListener = {
        if (!canceled) {
          canceled = true
          env.coordinator.cancel(TASK_ID)
        }
      },
    )

    assertEquals(BackgroundDownloadExecutionOutcome.canceled, env.engine.execute(TASK_ID).outcome)
    assertEquals(BackgroundDownloadStatus.canceled, env.store.read(TASK_ID).status)
    assertFalse(env.store.apkFile(TASK_ID).exists())
  }

  @Test
  fun externalStopClosesBlockedConnectionAndSystemStopDuringHashPauses() {
    val control = BackgroundDownloadExecutionControl()
    val entered = CountDownLatch(1)
    val closed = CountDownLatch(1)
    val blocked = BlockingConnection(entered, closed)
    val env = environment(expected = "hello".toByteArray(), responses = emptyList())
    val executor = Executors.newSingleThreadExecutor()
    try {
      val future = executor.submit<BackgroundDownloadExecutionResult> {
        env.engine.execute(TASK_ID, connectionFactory = HttpDownloadConnectionFactory { blocked }, control = control)
      }
      assertTrue(entered.await(5, TimeUnit.SECONDS))
      control.requestSystemStop(23)
      assertTrue(closed.await(5, TimeUnit.SECONDS))
      assertEquals(BackgroundDownloadExecutionOutcome.pausedBySystem, future.get(5, TimeUnit.SECONDS).outcome)
    } finally {
      executor.shutdownNow()
    }

    val bodyControl = BackgroundDownloadExecutionControl()
    val bodyEntered = CountDownLatch(1)
    val bodyClosed = CountDownLatch(1)
    val bodyBlocked = BlockingBodyConnection(bodyEntered, bodyClosed)
    val bodyEnv = environment(expected = "hello".toByteArray(), responses = emptyList())
    val bodyExecutor = Executors.newSingleThreadExecutor()
    try {
      val bodyFuture = bodyExecutor.submit<BackgroundDownloadExecutionResult> {
        bodyEnv.engine.execute(
          TASK_ID,
          connectionFactory = HttpDownloadConnectionFactory { bodyBlocked },
          control = bodyControl,
        )
      }
      assertTrue(bodyEntered.await(5, TimeUnit.SECONDS))
      bodyControl.requestCancel()
      assertTrue(bodyClosed.await(5, TimeUnit.SECONDS))
      assertEquals(BackgroundDownloadExecutionOutcome.canceled, bodyFuture.get(5, TimeUnit.SECONDS).outcome)
      assertEquals(1, bodyBlocked.closeCount)
    } finally {
      bodyExecutor.shutdownNow()
    }

    val hashControl = BackgroundDownloadExecutionControl()
    val body = ByteArray(2 * 1024 * 1024) { 8 }
    var requested = false
    val hashEnv = environment(
      expected = body,
      responses = listOf(response(200, body)),
      verificationChunkListener = {
        if (!requested) {
          requested = true
          hashControl.requestSystemStop(29)
        }
      },
    )
    val hashResult = hashEnv.engine.execute(TASK_ID, control = hashControl)
    assertEquals(BackgroundDownloadExecutionOutcome.pausedBySystem, hashResult.outcome)
    assertEquals(BackgroundDownloadStatus.pausedBySystem, hashEnv.store.read(TASK_ID).status)
  }

  @Test
  fun stopStorageFailureAndInterruptedBackoffReturnTruthfulStructuredOutcomes() {
    val events = Collections.synchronizedList(mutableListOf<String>())
    val cancelWriteFailure = OneShotFailingRecordFileFactory(events) { contents ->
      contents.contains("\"status\":\"canceled\"")
    }
    val cancelEnv = environment(
      expected = "hello".toByteArray(),
      responses = emptyList(),
      stopSignal = { BackgroundDownloadStopReason.cancel },
      recordFileFactory = cancelWriteFailure,
    )
    cancelWriteFailure.arm()

    val cancelResult = cancelEnv.engine.execute(TASK_ID)

    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, cancelResult.outcome)
    assertEquals(BackgroundDownloadStatus.waitingForStorage, cancelEnv.store.read(TASK_ID).status)

    Thread.interrupted()
    val interrupted = environment(
      expected = "hello".toByteArray(),
      responses = listOf(ConnectException("offline")),
      sleeper = { throw InterruptedException("executor interrupted") },
    )
    try {
      val interruptedResult = interrupted.engine.execute(TASK_ID)
      assertEquals(BackgroundDownloadExecutionOutcome.pausedBySystem, interruptedResult.outcome)
      assertEquals(BackgroundDownloadStatus.pausedBySystem, interrupted.store.read(TASK_ID).status)
      assertTrue(Thread.currentThread().isInterrupted)
    } finally {
      Thread.interrupted()
    }
  }

  @Test
  fun networkCloseFailuresRetryAndTrackedConnectionsCloseOnlyOnce() {
    var connectionCloseCount = 0
    val inputClose = environment(
      expected = "hello".toByteArray(),
      responses = listOf(
        response(
          200,
          "hello".toByteArray(),
          mapOf("ETag" to "\"v1\""),
          inputCloseFailure = IOException("input close failed"),
        ),
        response(416, byteArrayOf(), mapOf("Content-Range" to "bytes */5")),
      ),
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, inputClose.engine.execute(TASK_ID).outcome)
    assertEquals(2, inputClose.factory.requests.size)

    val connectionClose = environment(
      expected = "hello".toByteArray(),
      responses = listOf(
        response(
          200,
          "hello".toByteArray(),
          mapOf("ETag" to "\"v1\""),
          connectionCloseFailure = IOException("connection close failed"),
          afterConnectionClose = { connectionCloseCount += 1 },
        ),
        response(416, byteArrayOf(), mapOf("Content-Range" to "bytes */5")),
      ),
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, connectionClose.engine.execute(TASK_ID).outcome)
    assertEquals(2, connectionClose.factory.requests.size)
    assertEquals(1, connectionCloseCount)
  }

  @Test
  fun systemStopPersistsStrongTailWhenClosedReadThrowsOrReturnsEof() {
    listOf(false, true).forEach { closeAsEof ->
      val control = BackgroundDownloadExecutionControl()
      val blocked = CountDownLatch(1)
      val closed = CountDownLatch(1)
      val tail = " durable".toByteArray()
      val total = 5 + tail.size + 10
      val connection = StopTailConnection(total, tail, closeAsEof, blocked, closed)
      val env = environment(
        expected = ByteArray(total),
        expectedHash = "0".repeat(64),
        responses = emptyList(),
        downloaded = "hello".toByteArray(),
        checkpointBytes = 5,
        etag = "\"v1\"",
      )
      val executor = Executors.newSingleThreadExecutor()
      try {
        val future = executor.submit<BackgroundDownloadExecutionResult> {
          env.engine.execute(
            TASK_ID,
            connectionFactory = HttpDownloadConnectionFactory { connection },
            control = control,
          )
        }
        assertTrue(blocked.await(5, TimeUnit.SECONDS))
        control.requestSystemStop(if (closeAsEof) 42 else 41)
        assertTrue(closed.await(5, TimeUnit.SECONDS))
        assertEquals(BackgroundDownloadExecutionOutcome.pausedBySystem, future.get(5, TimeUnit.SECONDS).outcome)
        val record = env.store.read(TASK_ID)
        assertEquals(BackgroundDownloadStatus.pausedBySystem, record.status)
        assertEquals((5 + tail.size).toLong(), record.downloadedBytes)
        assertEquals(record.downloadedBytes, env.store.partialFile(TASK_ID).length())
        assertEquals("\"v1\"", record.strongEtag)
      } finally {
        executor.shutdownNow()
      }
    }
  }

  @Test
  fun durableCancelSuppressesLateProgressAndWinsAroundRename() {
    val body = ByteArray(2 * 1024 * 1024) { 6 }
    val progress = mutableListOf<BackgroundDownloadProgress>()
    lateinit var progressEnv: TestEnvironment
    progressEnv = environment(
      expected = body,
      responses = listOf(response(200, body, chunkSize = 1024 * 1024) {
        progressEnv.coordinator.cancel(TASK_ID)
      }),
      onProgress = { progress += it },
    )
    assertEquals(BackgroundDownloadExecutionOutcome.canceled, progressEnv.engine.execute(TASK_ID).outcome)
    assertTrue(progress.isEmpty())

    lateinit var renameEnv: TestEnvironment
    val mover = object : BackgroundDownloadArtifactMover {
      override fun moveAtomically(source: File, target: File) {
        renameEnv.coordinator.cancel(TASK_ID)
        check(source.renameTo(target))
      }
      override fun syncDirectory(directory: File) = Unit
    }
    renameEnv = environment(
      expected = "hello".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray())),
      artifactMover = mover,
    )
    assertEquals(BackgroundDownloadExecutionOutcome.canceled, renameEnv.engine.execute(TASK_ID).outcome)
    assertFalse(renameEnv.store.apkFile(TASK_ID).exists())
    assertEquals(BackgroundDownloadStatus.canceled, renameEnv.store.read(TASK_ID).status)
  }

  @Test
  fun blockingProgressListenerNeverBlocksDurableCancel() {
    val listenerEntered = CountDownLatch(1)
    val releaseListener = CountDownLatch(1)
    val body = ByteArray(2 * 1024 * 1024) { 13 }
    val env = environment(
      expected = body,
      responses = listOf(response(200, body, chunkSize = 1024 * 1024)),
      onProgress = {
        listenerEntered.countDown()
        assertTrue(releaseListener.await(5, TimeUnit.SECONDS))
      },
    )
    val executor = Executors.newSingleThreadExecutor()
    try {
      val execution = executor.submit<BackgroundDownloadExecutionResult> { env.engine.execute(TASK_ID) }
      assertTrue(listenerEntered.await(5, TimeUnit.SECONDS))
      val canceled = env.coordinator.cancel(TASK_ID)
      assertEquals(BackgroundDownloadStatus.canceled, canceled.status)
      assertFalse(execution.isDone)
      releaseListener.countDown()
      assertEquals(BackgroundDownloadExecutionOutcome.canceled, execution.get(5, TimeUnit.SECONDS).outcome)
    } finally {
      releaseListener.countDown()
      executor.shutdownNow()
    }
  }

  @Test
  fun artifactFlushPrecedesOneShotCheckpointCasFailureAndCheckpointRemainsResumable() {
    val events = Collections.synchronizedList(mutableListOf<String>())
    val recordFiles = OneShotFailingRecordFileFactory(events) { contents ->
      contents.contains("\"status\":\"running\"") && !contents.contains("\"downloadedBytes\":0")
    }
    val body = ByteArray(5 * 1024 * 1024) { 15 }
    val env = environment(
      expected = body,
      responses = listOf(response(200, body, mapOf("ETag" to "\"v1\""), chunkSize = 1024 * 1024)),
      recordFileFactory = recordFiles,
      artifactWriterFactory = { file -> RecordingFakeArtifactWriter(file, events) },
    )
    recordFiles.arm()

    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, env.engine.execute(TASK_ID).outcome)
    val waiting = env.store.read(TASK_ID)
    assertEquals(BackgroundDownloadStatus.waitingForStorage, waiting.status)
    assertTrue(waiting.downloadedBytes >= 4L * 1024 * 1024)
    assertEquals("\"v1\"", waiting.strongEtag)
    assertTrue(env.store.partialFile(TASK_ID).length() >= waiting.downloadedBytes)
    assertTrue(events.indexOf("artifact-flush") < events.indexOf("record-cas-fail"))

    val persistentEvents = Collections.synchronizedList(mutableListOf<String>())
    val persistentFailure = OneShotFailingRecordFileFactory(
      persistentEvents,
      maxFailures = Int.MAX_VALUE,
    ) { contents ->
      (contents.contains("\"status\":\"running\"") &&
        !contents.contains("\"downloadedBytes\":0")) ||
        contents.contains("\"status\":\"waitingForStorage\"")
    }
    val persistent = environment(
      expected = body,
      responses = listOf(response(200, body, mapOf("ETag" to "\"v1\""), chunkSize = 1024 * 1024)),
      recordFileFactory = persistentFailure,
      artifactWriterFactory = { file -> RecordingFakeArtifactWriter(file, persistentEvents) },
    )
    persistentFailure.arm()
    val bestEffort = persistent.engine.execute(TASK_ID)
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, bestEffort.outcome)
    assertEquals(BackgroundDownloadStatus.running, bestEffort.record?.status)
    assertEquals(BackgroundDownloadStatus.running, persistent.store.read(TASK_ID).status)
    assertTrue(persistent.store.partialFile(TASK_ID).length() >= 4L * 1024 * 1024)
  }

  @Test
  fun verifyingCasFailureAfterDurableMoveRecoversWithoutNetwork() {
    val events = Collections.synchronizedList(mutableListOf<String>())
    val recordFiles = OneShotFailingRecordFileFactory(events) { contents ->
      contents.contains("\"status\":\"verifying\"")
    }
    val env = environment(
      expected = "hello".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray())),
      recordFileFactory = recordFiles,
    )
    recordFiles.arm()

    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, env.engine.execute(TASK_ID).outcome)
    assertEquals(BackgroundDownloadStatus.waitingForStorage, env.store.read(TASK_ID).status)
    assertTrue(env.store.apkFile(TASK_ID).isFile)
    assertFalse(env.store.partialFile(TASK_ID).exists())

    assertEquals(BackgroundDownloadExecutionOutcome.completed, env.engine.execute(TASK_ID).outcome)
    assertEquals(1, env.factory.requests.size)
    assertEquals(BackgroundDownloadStatus.completed, env.store.read(TASK_ID).status)
  }

  @Test
  fun recoveredApkReadAndCompletionRecordFailuresRemainRecoverableWithoutNetwork() {
    var failSync = true
    val oneShotSyncFailure = object : BackgroundDownloadArtifactMover {
      override fun moveAtomically(source: File, target: File) {
        check(source.renameTo(target))
      }

      override fun syncDirectory(directory: File) {
        if (failSync) {
          failSync = false
          throw IOException("simulated directory sync failure")
        }
      }
    }
    var failRecoveredRead = false
    val readFailure = environment(
      expected = "hello".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray())),
      artifactMover = oneShotSyncFailure,
      artifactInputStreamFactory = { file ->
        if (failRecoveredRead && file.name.endsWith(".apk")) {
          throw IOException("simulated recovered APK read failure")
        }
        file.inputStream()
      },
    )

    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, readFailure.engine.execute(TASK_ID).outcome)
    failRecoveredRead = true
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, readFailure.engine.execute(TASK_ID).outcome)
    assertEquals(BackgroundDownloadStatus.waitingForStorage, readFailure.store.read(TASK_ID).status)
    assertTrue(readFailure.store.apkFile(TASK_ID).isFile)
    assertEquals(1, readFailure.factory.requests.size)
    failRecoveredRead = false
    assertEquals(BackgroundDownloadExecutionOutcome.completed, readFailure.engine.execute(TASK_ID).outcome)
    assertEquals(1, readFailure.factory.requests.size)

    var completionFailSync = true
    val completionMover = object : BackgroundDownloadArtifactMover {
      override fun moveAtomically(source: File, target: File) {
        check(source.renameTo(target))
      }

      override fun syncDirectory(directory: File) {
        if (completionFailSync) {
          completionFailSync = false
          throw IOException("simulated first directory sync failure")
        }
      }
    }
    val events = Collections.synchronizedList(mutableListOf<String>())
    val completedRecordFailure = OneShotFailingRecordFileFactory(events) { contents ->
      contents.contains("\"status\":\"completed\"")
    }
    val completionFailure = environment(
      expected = "hello".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray())),
      artifactMover = completionMover,
      recordFileFactory = completedRecordFailure,
    )

    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, completionFailure.engine.execute(TASK_ID).outcome)
    completedRecordFailure.arm()
    val waitingCompletion = completionFailure.engine.execute(TASK_ID)
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, waitingCompletion.outcome)
    assertEquals(BackgroundDownloadStatus.verifying, waitingCompletion.record?.status)
    assertEquals(BackgroundDownloadStatus.verifying, completionFailure.store.read(TASK_ID).status)
    assertEquals(1, completionFailure.factory.requests.size)
    assertEquals(BackgroundDownloadExecutionOutcome.completed, completionFailure.engine.execute(TASK_ID).outcome)
    assertEquals(1, completionFailure.factory.requests.size)
  }

  @Test
  fun failedRecordCasAfterCleanupKeepsAZeroCheckpointStorageState() {
    val events = Collections.synchronizedList(mutableListOf<String>())
    val failedRecordWrite = OneShotFailingRecordFileFactory(events) { contents ->
      contents.contains("\"status\":\"failed\"")
    }
    val env = environment(
      expected = "hello".toByteArray(),
      expectedHash = sha256("different".toByteArray()),
      responses = listOf(response(200, "hello".toByteArray(), mapOf("ETag" to "\"v1\""))),
      recordFileFactory = failedRecordWrite,
    )
    failedRecordWrite.arm()

    val result = env.engine.execute(TASK_ID)

    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, result.outcome)
    val waiting = env.store.read(TASK_ID)
    assertEquals(BackgroundDownloadStatus.waitingForStorage, waiting.status)
    assertEquals(0, waiting.downloadedBytes)
    assertNull(waiting.totalBytes)
    assertNull(waiting.strongEtag)
    assertFailure(waiting, "BACKGROUND_STORAGE_UNAVAILABLE", "storage_write_error")
    assertFalse(env.store.partialFile(TASK_ID).exists())
    assertFalse(env.store.apkFile(TASK_ID).exists())
  }

  @Test
  fun cancelDuringFailureTransitionReturnsStructuredCanceledOutcome() {
    lateinit var env: TestEnvironment
    var canceled = false
    env = environment(
      expected = "hello world".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray())),
      beforeFailureTransition = {
        if (!canceled) {
          canceled = true
          env.coordinator.cancel(TASK_ID)
        }
      },
    )

    val result = env.engine.execute(TASK_ID)

    assertEquals(BackgroundDownloadExecutionOutcome.canceled, result.outcome)
    assertEquals(BackgroundDownloadStatus.canceled, env.store.read(TASK_ID).status)
    assertFalse(env.store.partialFile(TASK_ID).exists())
    assertFalse(env.store.apkFile(TASK_ID).exists())
  }

  @Test
  fun tlsIsTerminalWriterCloseIsStorageAndMessagesAreSanitized() {
    val tls = environment(
      expected = "hello".toByteArray(),
      responses = listOf(SSLHandshakeException("certificate rejected")),
    )
    assertEquals(BackgroundDownloadExecutionOutcome.failed, tls.engine.execute(TASK_ID).outcome)
    assertEquals(1, tls.factory.requests.size)
    assertFailure(tls.store.read(TASK_ID), "PACKAGE_DOWNLOAD_FAILED", "tls_error")

    val closeFailure = environment(
      expected = "hello".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray())),
      artifactWriterFactory = { file ->
        val delegate = RandomAccessArtifactWriter(file)
        object : BackgroundDownloadArtifactWriter by delegate {
          override fun close() {
            delegate.close()
            throw IOException("fsync close failed")
          }
        }
      },
    )
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, closeFailure.engine.execute(TASK_ID).outcome)
    assertFailure(closeFailure.store.read(TASK_ID), "BACKGROUND_STORAGE_UNAVAILABLE", "storage_write_error")

    val signedUrl = "https://download.example.test/app.apk?token=super-secret"
    val signed = environment(
      expected = "hello".toByteArray(),
      responses = listOf(IOException("failed while opening $signedUrl"), IOException("failed while opening $signedUrl"), IOException("failed while opening $signedUrl")),
    )
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForNetwork, signed.engine.execute(TASK_ID).outcome)
    val message = signed.store.read(TASK_ID).errorMessage.orEmpty()
    assertFalse(message.contains("token="))
    assertFalse(message.contains("super-secret"))
    assertFalse(message.contains("https://"))
  }

  @Test
  fun failedArtifactCleanupFailureKeepsTruthfulWaitingStorageState() {
    val deleteFalse = environment(
      expected = "hello world".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray())),
      artifactCleaner = BackgroundDownloadArtifactCleaner { false },
    )
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, deleteFalse.engine.execute(TASK_ID).outcome)
    assertEquals(BackgroundDownloadStatus.waitingForStorage, deleteFalse.store.read(TASK_ID).status)
    assertTrue(deleteFalse.store.partialFile(TASK_ID).exists())
    assertFailure(deleteFalse.store.read(TASK_ID), "BACKGROUND_STORAGE_UNAVAILABLE", "storage_cleanup_error")

    val deleteThrows = environment(
      expected = "hello world".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray())),
      artifactCleaner = BackgroundDownloadArtifactCleaner { throw IOException("delete denied") },
    )
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, deleteThrows.engine.execute(TASK_ID).outcome)
    assertTrue(deleteThrows.store.partialFile(TASK_ID).exists())
    assertFailure(deleteThrows.store.read(TASK_ID), "BACKGROUND_STORAGE_UNAVAILABLE", "storage_cleanup_error")

    val apkCleaner = BackgroundDownloadArtifactCleaner { file ->
      if (file.name.endsWith(".apk")) false else !file.exists() || file.delete()
    }
    val apkFailure = environment(
      expected = "package-bytes".toByteArray(),
      responses = listOf(response(200, "package-bytes".toByteArray(), mapOf("Content-Encoding" to "gzip"))),
      artifactCleaner = apkCleaner,
    )
    apkFailure.store.apkFile(TASK_ID).writeText("stale")
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, apkFailure.engine.execute(TASK_ID).outcome)
    assertTrue(apkFailure.store.apkFile(TASK_ID).exists())
    assertFailure(apkFailure.store.read(TASK_ID), "BACKGROUND_STORAGE_UNAVAILABLE", "storage_write_error")
  }

  @Test
  fun blankContentEncodingIsIdentityAndMoverOrdersRenameSyncBeforeCompletion() {
    val operations = mutableListOf<String>()
    lateinit var env: TestEnvironment
    val mover = object : BackgroundDownloadArtifactMover {
      override fun moveAtomically(source: File, target: File) {
        operations += "move:${env.store.read(TASK_ID).status}"
        check(source.renameTo(target))
      }
      override fun syncDirectory(directory: File) {
        operations += "sync:${env.store.read(TASK_ID).status}"
      }
    }
    env = environment(
      expected = "hello".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray(), mapOf("Content-Encoding" to "   "))),
      artifactMover = mover,
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, env.engine.execute(TASK_ID).outcome)
    assertEquals(listOf("move:running", "sync:running"), operations)
    assertEquals(BackgroundDownloadStatus.completed, env.store.read(TASK_ID).status)

    var failSync = true
    val failingMover = object : BackgroundDownloadArtifactMover {
      override fun moveAtomically(source: File, target: File) {
        check(source.renameTo(target))
      }
      override fun syncDirectory(directory: File) {
        if (failSync) {
          failSync = false
          throw IOException("directory fsync failed")
        }
      }
    }
    val failed = environment(
      expected = "hello".toByteArray(),
      responses = listOf(response(200, "hello".toByteArray())),
      artifactMover = failingMover,
    )
    assertEquals(BackgroundDownloadExecutionOutcome.waitingForStorage, failed.engine.execute(TASK_ID).outcome)
    assertFailure(failed.store.read(TASK_ID), "BACKGROUND_STORAGE_UNAVAILABLE", "storage_write_error")
    assertFalse(failed.store.partialFile(TASK_ID).exists())
    assertTrue(failed.store.apkFile(TASK_ID).exists())
    assertEquals(BackgroundDownloadExecutionOutcome.completed, failed.engine.execute(TASK_ID).outcome)
    assertEquals(1, failed.factory.requests.size)
  }

  @Test
  fun progressIsAtMostFourHzAndCheckpointUsesFourMibOrTwoSeconds() {
    val clock = FakeClock()
    val progressTimes = mutableListOf<Long>()
    val body = ByteArray(6 * 1024 * 1024) { 3 }
    val env = environment(
      expected = body,
      responses = listOf(
        response(200, body, mapOf("ETag" to "\"v1\""), chunkSize = 1024 * 1024) {
          clock.advance(100)
        },
      ),
      clock = clock,
      onProgress = { progressTimes += clock.now() },
    )

    assertEquals(BackgroundDownloadExecutionOutcome.completed, env.engine.execute(TASK_ID).outcome)
    assertTrue(progressTimes.zipWithNext().all { (a, b) -> b - a >= 250 })
    assertTrue(env.checkpoints.any { it >= 4L * 1024 * 1024 })

    val timeClock = FakeClock()
    val timeBody = ByteArray(3 * 1024) { 5 }
    val timeEnv = environment(
      expected = timeBody,
      responses = listOf(
        response(200, timeBody, mapOf("ETag" to "\"v2\""), chunkSize = 1024) {
          timeClock.advance(1_000)
        },
      ),
      clock = timeClock,
    )
    assertEquals(BackgroundDownloadExecutionOutcome.completed, timeEnv.engine.execute(TASK_ID).outcome)
    assertTrue(timeEnv.checkpoints.any { it in 1024L..2048L })
  }

  private fun assertProtocolFailure(
    expected: ByteArray,
    response: FakeResponse,
    checkpoint: ByteArray = byteArrayOf(),
    checkpointBytes: Long = 0,
    etag: String? = null,
  ) {
    val env = environment(
      expected = expected,
      responses = listOf(response),
      downloaded = checkpoint,
      checkpointBytes = checkpointBytes,
      etag = etag,
    )
    assertEquals(BackgroundDownloadExecutionOutcome.failed, env.engine.execute(TASK_ID).outcome)
    assertFailure(env.store.read(TASK_ID), "PACKAGE_DOWNLOAD_FAILED", "protocol_error")
  }

  private fun executeSharedVector(name: String, vector: JSONObject) {
    val expected = vector.getJSONObject("expected")
    val outcome = expected.getString("outcome")
    val checkpoint = vector.optJSONObject("checkpoint")
    val responseJson = vector.optJSONObject("response")
    val followUp = vector.optJSONObject("followResponse")
      ?: vector.optJSONObject("restartResponse")
      ?: vector.optJSONObject("resumeResponse")
    val responses = buildList {
      if (responseJson != null) add(responseFromVector(responseJson))
      if (followUp != null) add(responseFromVector(followUp))
    }
    val checkpointBody = checkpoint?.optString("body", "")?.toByteArray() ?: byteArrayOf()
    val checkpointBytes = checkpoint?.optLong("bytes", 0) ?: 0
    val checkpointTotal = checkpoint?.optLong("total", 0)?.takeIf { it > 0 }
    val expectedBody = when {
      expected.has("body") -> expected.getString("body").toByteArray()
      name == "range_416_overshoot" -> checkpointBody
      name == "uncheckpointed_tail" ->
        checkpointBody.copyOf(checkpointBytes.toInt()) + checkNotNull(followUp).getString("body").toByteArray()
      responseJson != null -> responseJson.optString("body", "").toByteArray()
      else -> byteArrayOf()
    }
    val expectedSize = checkpointTotal
      ?: responseJson?.optLong("contentLength", -1)?.takeIf { it >= 0 }
      ?: expectedBody.size.toLong()
    val artifactBytes = if (expectedBody.size.toLong() == expectedSize) expectedBody else ByteArray(expectedSize.toInt())
    val expectedHash = when {
      outcome == "hash-mismatch" -> "0".repeat(64)
      expected.has("sha256") -> expected.getString("sha256")
      else -> sha256(artifactBytes)
    }
    val env = environment(
      expected = artifactBytes,
      expectedHash = expectedHash,
      recordExpectedSize = expectedSize,
      responses = responses,
      downloaded = checkpointBody,
      checkpointBytes = checkpointBytes,
      etag = checkpoint?.optString("etag")?.takeIf { it.isNotEmpty() },
    )

    val result = env.engine.execute(TASK_ID)
    vector.optJSONObject("request")?.let { request ->
      val actual = env.factory.requests.first()
      if (request.has("acceptEncoding")) {
        assertEquals(request.getString("acceptEncoding"), actual.headers["Accept-Encoding"], name)
      }
      if (request.has("range")) assertEquals(request.getString("range"), actual.headers["Range"], name)
      if (request.has("ifRange")) assertEquals(request.getString("ifRange"), actual.headers["If-Range"], name)
    }
    when (outcome) {
      "complete" -> assertEquals(BackgroundDownloadExecutionOutcome.completed, result.outcome, name)
      "integrity-failure" -> assertFailure(env.store.read(TASK_ID), "PACKAGE_DOWNLOAD_FAILED", "integrity_error")
      "hash-mismatch" -> assertFailure(env.store.read(TASK_ID), "PACKAGE_HASH_MISMATCH", "hash_mismatch")
      "protocol-failure" -> assertFailure(env.store.read(TASK_ID), "PACKAGE_DOWNLOAD_FAILED", "protocol_error")
      "clean-restart" -> {
        assertEquals(BackgroundDownloadExecutionOutcome.completed, result.outcome, name)
        assertNull(env.factory.requests.single().headers["Range"], name)
      }
      "one-clean-retry" -> {
        assertEquals(BackgroundDownloadExecutionOutcome.completed, result.outcome, name)
        assertEquals(2, env.factory.requests.size, name)
      }
      "follow" -> {
        assertEquals(BackgroundDownloadExecutionOutcome.completed, result.outcome, name)
        assertEquals(responseJson?.getString("location"), env.factory.requests[1].url)
        assertEquals("bytes=$checkpointBytes-", env.factory.requests[1].headers["Range"])
        if (expected.optBoolean("preserveRange")) {
          assertTrue(env.factory.requests.all { it.headers["Range"] == "bytes=$checkpointBytes-" })
          assertTrue(env.factory.requests.all { it.headers["If-Range"] == checkpoint?.getString("etag") })
        }
      }
      "truncate-to-checkpoint" -> {
        assertEquals(BackgroundDownloadExecutionOutcome.completed, result.outcome, name)
        assertEquals("hello world", env.store.apkFile(TASK_ID).readText())
      }
      else -> error("Unhandled shared vector outcome: $outcome")
    }
  }

  private fun responseFromVector(json: JSONObject): FakeResponse {
    val headers = linkedMapOf<String, String>()
    if (json.has("contentEncoding")) headers["Content-Encoding"] = json.getString("contentEncoding")
    if (json.has("contentRange")) headers["Content-Range"] = json.getString("contentRange")
    if (json.has("contentLength")) headers["Content-Length"] = json.getLong("contentLength").toString()
    if (json.has("etag")) headers["ETag"] = json.getString("etag")
    if (json.has("location")) headers["Location"] = json.getString("location")
    return response(json.getInt("status"), json.optString("body", "").toByteArray(), headers)
  }

  private fun sharedVectors(): JSONObject = JSONObject(
    checkNotNull(javaClass.classLoader?.getResourceAsStream("http_resume_vectors.json"))
      .bufferedReader()
      .use { it.readText() },
  ).getJSONObject("vectors")

  private fun assertFailure(
    record: BackgroundDownloadRecord,
    publicCode: String,
    nativeCode: String,
  ) {
    assertEquals(publicCode, record.errorCode)
    assertEquals(nativeCode, record.nativeErrorCode, record.errorMessage)
  }

  private fun environment(
    expected: ByteArray,
    responses: List<Any>,
    packageUrl: String = "https://example.test/app.apk",
    downloaded: ByteArray = byteArrayOf(),
    checkpointBytes: Long = downloaded.size.toLong(),
    etag: String? = null,
    recordExpectedSize: Long = expected.size.toLong(),
    expectedHash: String = sha256(expected),
    maxBytes: Long = BackgroundDownloadContract.DEFAULT_MAX_DOWNLOAD_BYTES,
    createInvalidRecordDirectly: Boolean = false,
    availableBytes: Long = Long.MAX_VALUE,
    clock: FakeClock = FakeClock(),
    sleeper: (Long) -> Unit = {},
    stopSignal: () -> BackgroundDownloadStopReason = { BackgroundDownloadStopReason.none },
    onProgress: (BackgroundDownloadProgress) -> Unit = {},
    artifactWriterFactory: (File) -> BackgroundDownloadArtifactWriter = { RandomAccessArtifactWriter(it) },
    checkpointListener: (BackgroundDownloadRecord) -> Unit = {},
    verificationChunkListener: (Long) -> Unit = {},
    artifactMover: BackgroundDownloadArtifactMover = JvmBackgroundDownloadArtifactMover,
    artifactCleaner: BackgroundDownloadArtifactCleaner = JvmBackgroundDownloadArtifactCleaner,
    recordFileFactory: BackgroundRecordFileFactory = PlainRecordFileFactory,
    artifactInputStreamFactory: (File) -> java.io.InputStream = File::inputStream,
    beforeFailureTransition: () -> Unit = {},
  ): TestEnvironment {
    val root = Files.createTempDirectory("background-engine-test").toFile()
    roots += root
    val store = BackgroundDownloadStore(root, recordFileFactory = recordFileFactory, artifactVerifier = { file, record ->
      file.length() == record.expectedSizeBytes && sha256(file.readBytes()) == record.expectedSha256
    }, nowEpochMs = clock::now)
    val coordinator = BackgroundDownloadCoordinator(store, clock::now)
    val record = BackgroundDownloadRecord(
      revision = 1,
      id = TASK_ID,
      packageUrl = packageUrl,
      status = BackgroundDownloadStatus.queued,
      downloadedBytes = if (createInvalidRecordDirectly) 0 else checkpointBytes,
      totalBytes = if (checkpointBytes > 0) recordExpectedSize else null,
      expectedSizeBytes = if (createInvalidRecordDirectly) maxBytes else recordExpectedSize,
      expectedSha256 = expectedHash,
      maxDownloadBytes = maxBytes,
      strongEtag = etag,
      createdAtEpochMs = clock.now(),
      updatedAtEpochMs = clock.now(),
    )
    if (checkpointBytes > 0) {
      store.create(record.copy(status = BackgroundDownloadStatus.pausedBySystem))
    } else {
      coordinator.start(record)
    }
    if (downloaded.isNotEmpty()) store.partialFile(TASK_ID).writeBytes(downloaded)
    val factory = FakeConnectionFactory(responses.toMutableList())
    val checkpoints = Collections.synchronizedList(mutableListOf<Long>())
    val engine = BackgroundDownloadEngine(
      store = store,
      coordinator = coordinator,
      connectionFactory = factory,
      availableSpaceProvider = { availableBytes },
      nowElapsedMs = clock::now,
      sleeper = sleeper,
      stopSignal = stopSignal,
      progressListener = onProgress,
      artifactWriterFactory = artifactWriterFactory,
      checkpointListener = {
        checkpoints += it.downloadedBytes
        checkpointListener(it)
      },
      verificationChunkListener = verificationChunkListener,
      artifactMover = artifactMover,
      artifactCleaner = artifactCleaner,
      artifactInputStreamFactory = artifactInputStreamFactory,
      beforeFailureTransition = beforeFailureTransition,
    )
    return TestEnvironment(store, coordinator, engine, factory, checkpoints)
  }

  private fun response(
    status: Int,
    body: ByteArray,
    headers: Map<String, String> = emptyMap(),
    chunkSize: Int = body.size.coerceAtLeast(1),
    failureAfterBytes: Int? = null,
    beforeOpen: () -> Unit = {},
    inputCloseFailure: IOException? = null,
    connectionCloseFailure: IOException? = null,
    afterConnectionClose: () -> Unit = {},
    afterChunk: (Int) -> Unit = {},
  ) = FakeResponse(
    status = status,
    body = body,
    headers = headers,
    chunkSize = chunkSize,
    failureAfterBytes = failureAfterBytes,
    beforeOpen = beforeOpen,
    afterChunk = afterChunk,
    inputCloseFailure = inputCloseFailure,
    connectionCloseFailure = connectionCloseFailure,
    afterConnectionClose = afterConnectionClose,
  )

  private fun sha256(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

  private data class TestEnvironment(
    val store: BackgroundDownloadStore,
    val coordinator: BackgroundDownloadCoordinator,
    val engine: BackgroundDownloadEngine,
    val factory: FakeConnectionFactory,
    val checkpoints: List<Long>,
  )

  private data class FakeResponse(
    val status: Int,
    val body: ByteArray,
    val headers: Map<String, String>,
    val chunkSize: Int,
    val failureAfterBytes: Int?,
    val beforeOpen: () -> Unit,
    val afterChunk: (Int) -> Unit,
    val inputCloseFailure: IOException?,
    val connectionCloseFailure: IOException?,
    val afterConnectionClose: () -> Unit,
  )

  private class FakeConnectionFactory(private val responses: MutableList<Any>) :
    HttpDownloadConnectionFactory {
    val requests = Collections.synchronizedList(mutableListOf<HttpDownloadRequest>())

    override fun open(request: HttpDownloadRequest): HttpDownloadConnection {
      requests += request
      val next = synchronized(responses) { responses.removeAt(0) }
      if (next is Throwable) throw next
      val response = next as FakeResponse
      response.beforeOpen()
      return object : HttpDownloadConnection {
        override val statusCode: Int = response.status
        override fun header(name: String): String? =
          response.headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
        override fun body() = ChunkedInputStream(
          response.body,
          response.chunkSize,
          response.failureAfterBytes,
          response.afterChunk,
          response.inputCloseFailure,
        )
        override fun close() {
          response.afterConnectionClose()
          response.connectionCloseFailure?.let { throw it }
        }
      }
    }
  }

  private class ChunkedInputStream(
    bytes: ByteArray,
    private val chunkSize: Int,
    private val failureAfterBytes: Int?,
    private val afterChunk: (Int) -> Unit,
    private val closeFailure: IOException?,
  ) : ByteArrayInputStream(bytes) {
    private var total = 0
    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
      if (failureAfterBytes != null && total >= failureAfterBytes) {
        throw IOException("simulated stream failure")
      }
      val read = super.read(buffer, offset, minOf(length, chunkSize))
      if (read > 0) {
        total += read
        afterChunk(total)
      }
      return read
    }

    override fun close() {
      super.close()
      closeFailure?.let { throw it }
    }
  }

  private class FakeClock {
    private var value = 0L
    fun now(): Long = value
    fun advance(millis: Long) { value += millis }
  }

  private class RecordingFakeArtifactWriter(
    private val file: File,
    private val events: MutableList<String>,
  ) : BackgroundDownloadArtifactWriter {
    private var bytes = if (file.isFile) file.readBytes() else byteArrayOf()
    private var position = 0

    override val length: Long get() = bytes.size.toLong()

    override fun truncate(length: Long) {
      require(length in 0..Int.MAX_VALUE.toLong())
      bytes = bytes.copyOf(length.toInt())
      if (position > bytes.size) position = bytes.size
    }

    override fun seek(position: Long) {
      require(position in 0..Int.MAX_VALUE.toLong())
      this.position = position.toInt()
    }

    override fun write(bytes: ByteArray, offset: Int, length: Int) {
      require(offset >= 0 && length >= 0 && offset + length <= bytes.size)
      val end = position + length
      if (end > this.bytes.size) this.bytes = this.bytes.copyOf(end)
      bytes.copyInto(this.bytes, destinationOffset = position, startIndex = offset, endIndex = offset + length)
      position = end
    }

    override fun flush() {
      events += "artifact-flush"
      file.parentFile?.mkdirs()
      file.writeBytes(bytes)
    }

    override fun close() = Unit
  }

  private class OneShotFailingRecordFileFactory(
    private val events: MutableList<String>,
    private val maxFailures: Int = 1,
    private val shouldFail: (String) -> Boolean,
  ) : BackgroundRecordFileFactory {
    @Volatile private var armed = false
    @Volatile private var failureCount = 0

    fun arm() {
      armed = true
    }

    override fun create(file: File): BackgroundRecordFile {
      val delegate = PlainRecordFileFactory.create(file)
      return object : BackgroundRecordFile by delegate {
        override fun writeText(contents: String) {
          events += "record-cas"
          if (armed && failureCount < maxFailures && shouldFail(contents)) {
            failureCount += 1
            events += "record-cas-fail"
            throw IOException("simulated record CAS failure")
          }
          delegate.writeText(contents)
        }
      }
    }
  }

  private class BlockingConnection(
    private val entered: CountDownLatch,
    private val closed: CountDownLatch,
  ) : HttpDownloadConnection {
    @Volatile private var isClosed = false
    override val statusCode: Int
      get() {
        entered.countDown()
        while (!isClosed) Thread.yield()
        throw IOException("connection closed")
      }
    override fun header(name: String): String? = null
    override fun body() = ByteArrayInputStream(byteArrayOf())
    override fun close() {
      isClosed = true
      closed.countDown()
    }
  }

  private class BlockingBodyConnection(
    private val entered: CountDownLatch,
    private val closed: CountDownLatch,
  ) : HttpDownloadConnection {
    @Volatile private var isClosed = false
    @Volatile var closeCount = 0
      private set
    override val statusCode: Int = 200
    override fun header(name: String): String? = null
    override fun body() = object : java.io.InputStream() {
      override fun read(): Int {
        entered.countDown()
        while (!isClosed) Thread.yield()
        throw IOException("body closed")
      }
    }
    override fun close() {
      closeCount += 1
      isClosed = true
      closed.countDown()
    }
  }

  private class StopTailConnection(
    private val totalBytes: Int,
    private val tail: ByteArray,
    private val closeAsEof: Boolean,
    private val blocked: CountDownLatch,
    private val closed: CountDownLatch,
  ) : HttpDownloadConnection {
    @Volatile private var isClosed = false
    override val statusCode: Int = 206
    override fun header(name: String): String? = when (name.lowercase()) {
      "content-range" -> "bytes 5-${totalBytes - 1}/$totalBytes"
      "content-length" -> (totalBytes - 5).toString()
      "etag" -> "\"v1\""
      else -> null
    }
    override fun body() = object : java.io.InputStream() {
      private var delivered = false
      override fun read(): Int = error("single-byte read is not used")
      override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (!delivered) {
          delivered = true
          tail.copyInto(buffer, offset)
          return tail.size
        }
        blocked.countDown()
        while (!isClosed) Thread.yield()
        return if (closeAsEof) -1 else throw IOException("closed by stop")
      }
    }
    override fun close() {
      isClosed = true
      closed.countDown()
    }
  }

  private object PlainRecordFileFactory : BackgroundRecordFileFactory {
    override fun create(file: File): BackgroundRecordFile = object : BackgroundRecordFile {
      override fun exists(): Boolean = file.isFile
      override fun readText(): String = file.readText()
      override fun writeText(contents: String) {
        file.parentFile?.mkdirs()
        file.writeText(contents)
      }
      override fun delete() {
        if (file.exists()) check(file.delete())
      }
    }
  }

  private companion object {
    const val TASK_ID = "task"
  }
}
