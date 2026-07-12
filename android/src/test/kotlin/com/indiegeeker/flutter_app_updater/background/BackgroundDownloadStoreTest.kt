package com.indiegeeker.flutter_app_updater.background

import java.io.File
import java.math.BigInteger
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.json.JSONObject
import org.junit.jupiter.api.Assumptions

internal class BackgroundDownloadStoreTest {
  private val roots = mutableListOf<File>()

  @AfterTest
  fun cleanUp() {
    roots.forEach(File::deleteRecursively)
  }

  @Test
  fun recordJsonAndDartMapRoundTripEveryFieldIncludingLargeLongs() {
    val record = record(
      revision = 9_007_199_254_740_991L,
      status = BackgroundDownloadStatus.waitingForNetwork,
      downloadedBytes = 900_000_000L,
      totalBytes = 1_000_000_000L,
    ).copy(
      strongEtag = "\"release-7\"",
      lastStopReason = 3,
      errorCode = "network",
      errorMessage = "temporarily unavailable",
      nativeErrorCode = "503",
      createdAtEpochMs = 9_007_199_254_740_000L,
      updatedAtEpochMs = 9_007_199_254_740_991L,
    )

    assertEquals(record, BackgroundDownloadRecord.fromJson(record.toJson()))
    assertEquals(
      mapOf(
        "id" to record.id,
        "revision" to record.revision,
        "status" to "waitingForNetwork",
        "downloadedBytes" to record.downloadedBytes,
        "totalBytes" to record.totalBytes,
        "filePath" to "/safe/artifact.apk",
        "errorCode" to record.errorCode,
        "errorMessage" to record.errorMessage,
        "nativeErrorCode" to record.nativeErrorCode,
        "createdAtEpochMs" to record.createdAtEpochMs,
        "updatedAtEpochMs" to record.updatedAtEpochMs,
      ),
      record.toMap("/safe/artifact.apk"),
    )
  }

  @Test
  fun schemaV1CodecUsesExactKeysAndRejectsExtraKeys() {
    val json = record().toJson()
    assertEquals(SCHEMA_V1_KEYS, json.keys().asSequence().toSet())

    json.put("futureField", true)

    assertFailsWith<IllegalArgumentException> {
      BackgroundDownloadRecord.fromJson(json)
    }
  }

  @Test
  fun schemaV1CodecRejectsEveryMissingRequiredKey() {
    val valid = record().toJson()

    SCHEMA_V1_KEYS.forEach { key ->
      val missing = JSONObject(valid.toString()).apply { remove(key) }
      assertFailsWith<IllegalArgumentException>("missing key $key") {
        BackgroundDownloadRecord.fromJson(missing)
      }
    }
  }

  @Test
  fun schemaV1CodecRejectsWrongFieldTypes() {
    val valid = record().toJson()
    val numericKeys = setOf(
      "schemaVersion",
      "revision",
      "downloadedBytes",
      "totalBytes",
      "expectedSizeBytes",
      "maxDownloadBytes",
      "schedulerJobId",
      "notificationId",
      "lastStopReason",
      "createdAtEpochMs",
      "updatedAtEpochMs",
    )
    val stringKeys = setOf(
      "id",
      "packageUrl",
      "status",
      "expectedSha256",
      "strongEtag",
      "errorCode",
      "errorMessage",
      "nativeErrorCode",
    )

    numericKeys.forEach { key ->
      val wrong = JSONObject(valid.toString()).put(key, "1")
      assertFailsWith<IllegalArgumentException>("wrong type for $key") {
        BackgroundDownloadRecord.fromJson(wrong)
      }
    }
    stringKeys.forEach { key ->
      val wrong = JSONObject(valid.toString()).put(key, 1)
      assertFailsWith<IllegalArgumentException>("wrong type for $key") {
        BackgroundDownloadRecord.fromJson(wrong)
      }
    }
  }

  @Test
  fun recordRejectsDownloadPolicyOutsideNativeMvpLimits() {
    assertFailsWith<IllegalArgumentException> {
      record(expectedSizeBytes = 501, maxDownloadBytes = 500)
    }
    assertFailsWith<IllegalArgumentException> {
      record(
        expectedSizeBytes = BackgroundDownloadContract.DEFAULT_MAX_DOWNLOAD_BYTES,
        maxDownloadBytes = BackgroundDownloadContract.DEFAULT_MAX_DOWNLOAD_BYTES + 1,
      )
    }
  }

  @Test
  fun recordEnforcesStrictByteInvariantsAndLongOverflowTypes() {
    val boundary = record(
      downloadedBytes = 1,
      totalBytes = 1,
      expectedSizeBytes = 1,
      maxDownloadBytes = 1,
    )
    assertEquals(boundary, BackgroundDownloadRecord.fromJson(boundary.toJson()))

    listOf<() -> Unit>(
      { record(downloadedBytes = 2, expectedSizeBytes = 1, maxDownloadBytes = 1) },
      { record(totalBytes = 0) },
      { record(totalBytes = -1) },
      { record(totalBytes = 999_999_999) },
      { record(totalBytes = 1_000_000_001) },
      { record(downloadedBytes = 2, totalBytes = 1) },
    ).forEach { impossible ->
      assertFailsWith<IllegalArgumentException> { impossible() }
    }

    val validJson = record().toJson()
    listOf(
      JSONObject(validJson.toString()).put("downloadedBytes", 1_000_000_001L),
      JSONObject(validJson.toString()).put("totalBytes", 0),
      JSONObject(validJson.toString()).put("totalBytes", 999_999_999L),
      JSONObject(validJson.toString()).put("totalBytes", 1_000_000_001L),
    ).forEach { impossibleJson ->
      assertFailsWith<IllegalArgumentException> {
        BackgroundDownloadRecord.fromJson(impossibleJson)
      }
    }

    val overflow = JSONObject(validJson.toString()).put(
      "downloadedBytes",
      BigInteger.valueOf(Long.MAX_VALUE).add(BigInteger.ONE),
    )
    assertFailsWith<IllegalArgumentException> {
      BackgroundDownloadRecord.fromJson(overflow)
    }
  }

  @Test
  fun codecRejectsUnsupportedSchemaUnknownStatusInvalidHashAndInvalidId() {
    val valid = record().toJson()

    listOf(
      JSONObject(valid.toString()).put("schemaVersion", 2),
      JSONObject(valid.toString()).put("status", "unknown"),
      JSONObject(valid.toString()).put("expectedSha256", "A".repeat(64)),
      JSONObject(valid.toString()).put("id", "../escape"),
    ).forEach { json ->
      assertFailsWith<IllegalArgumentException> {
        BackgroundDownloadRecord.fromJson(json)
      }
    }
  }

  @Test
  fun listNeverCrashesForUnsupportedOrCorruptJson() {
    val root = newRoot()
    val factory = TestRecordFileFactory()
    val store = store(root, factory)
    store.create(record(id = "healthy", updatedAtEpochMs = 300))
    writeRawRecord(
      root,
      "unsupported",
      JSONObject(record(id = "unsupported").toJson().toString()).put("schemaVersion", 99).toString(),
    )
    writeRawRecord(root, "corrupt", "{not-json")
    writeRawRecord(root, "../ignored", "{not-json")

    val records = store.list()

    assertEquals(listOf("healthy", "unsupported", "corrupt"), records.map { it.id })
    assertEquals(BackgroundDownloadStatus.failed, records[1].status)
    assertEquals("unsupported_schema", records[1].errorCode)
    assertEquals(BackgroundDownloadStatus.failed, records[2].status)
    assertEquals("corrupt_state", records[2].errorCode)
  }

  @Test
  fun listRecoveryIsReadAndRemoveConsistent() {
    listOf(
      "corrupt" to "{not-json",
      "unsupported" to JSONObject(record(id = "unsupported").toJson().toString())
        .put("schemaVersion", 99)
        .toString(),
    ).forEach { (id, contents) ->
      val root = newRoot()
      val store = store(root, TestRecordFileFactory())
      writeRawRecord(root, id, contents)

      val listed = store.list().single()

      assertEquals(id, listed.id)
      assertEquals(BackgroundDownloadStatus.failed, listed.status)
      assertEquals(listed, store.read(id))
      store.remove(id)
      assertFalse(root.resolve(id).exists())
    }
  }

  @Test
  fun futureSchemaReturnsSyntheticFailureWithoutDowngradingRawState() {
    val root = newRoot()
    val store = store(root, TestRecordFileFactory())
    val futureJson = JSONObject(
      record(
        id = "future",
        revision = 700,
        updatedAtEpochMs = 900,
      ).toJson().toString(),
    ).put("schemaVersion", 2)
    val raw = futureJson.toString()
    writeRawRecord(root, "future", raw)

    val read = store.read("future")
    val listed = store.list().single()

    assertEquals(BackgroundDownloadStatus.failed, read.status)
    assertEquals("unsupported_schema", read.errorCode)
    assertEquals(700, read.revision)
    assertEquals(100, read.createdAtEpochMs)
    assertEquals(900, read.updatedAtEpochMs)
    assertEquals(read, listed)
    assertEquals(raw, root.resolve("future/task.json").readText())

    store.remove("future")
    assertFalse(root.resolve("future").exists())
  }

  @Test
  fun futureSchemaRejectsEveryMutationWithoutChangingStateOrArtifacts() {
    run {
      val fixture = futureSchemaFixture()
      val error = assertFailsWith<BackgroundDownloadStateException> {
        fixture.store.write(
          fixture.synthetic.copy(revision = fixture.synthetic.revision + 1),
          expectedRevision = fixture.synthetic.revision,
        )
      }
      assertEquals("unsupported_schema", error.message)
      fixture.assertUnchanged()
    }

    run {
      val fixture = futureSchemaFixture()

      val reconciled = fixture.store.reconcileArtifacts(fixture.synthetic.id)

      assertEquals(fixture.synthetic, reconciled)
      fixture.assertUnchanged()
    }

    run {
      val fixture = futureSchemaFixture()
      val error = assertFailsWith<BackgroundDownloadStateException> {
        fixture.store.cancelArtifactsAndWriteTombstone(
          fixture.synthetic.id,
          expectedRevision = fixture.synthetic.revision,
        )
      }
      assertEquals("unsupported_schema", error.message)
      fixture.assertUnchanged()
    }
  }

  @Test
  fun removeDeletesCorruptTaskWithoutFirstParsingIt() {
    listOf(
      "corrupt" to "{not-json",
      "unsupported" to JSONObject(record(id = "unsupported").toJson().toString())
        .put("schemaVersion", 99)
        .toString(),
    ).forEach { (id, contents) ->
      val root = newRoot()
      val store = store(root, TestRecordFileFactory())
      writeRawRecord(root, id, contents)

      store.remove(id)

      assertFalse(root.resolve(id).exists())
    }
  }

  @Test
  fun recoveryWriteFailureAndStorageReadFailureAreNotSwallowedByList() {
    val writeRoot = newRoot()
    val writeFactory = TestRecordFileFactory()
    val writeStore = store(writeRoot, writeFactory)
    writeRawRecord(writeRoot, "corrupt", "{not-json")
    writeFactory.failNextWrite = true
    assertFailsWith<TestInterruptedWriteException> { writeStore.list() }
    assertEquals("{not-json", writeRoot.resolve("corrupt/task.json").readText())

    val readRoot = newRoot()
    val readFactory = TestRecordFileFactory()
    val readStore = store(readRoot, readFactory)
    writeRawRecord(readRoot, "unreadable", record(id = "unreadable").toJson().toString())
    readFactory.failNextRead = true
    assertFailsWith<TestInterruptedReadException> { readStore.list() }
  }

  @Test
  fun interruptedAtomicWritePreservesPreviousRecord() {
    val root = newRoot()
    val factory = TestRecordFileFactory()
    val store = store(root, factory)
    val initial = record()
    store.create(initial)
    factory.failNextWrite = true

    assertFailsWith<TestInterruptedWriteException> {
      store.write(initial.copy(revision = 2, downloadedBytes = 10), expectedRevision = 1)
    }

    assertEquals(initial, store.read(initial.id))
  }

  @Test
  fun invalidIdsCannotResolvePathsOrRecords() {
    val store = store(newRoot(), TestRecordFileFactory())

    listOf("", "../escape", "nested/path", "a".repeat(81), "white space").forEach { id ->
      assertFailsWith<IllegalArgumentException> { store.taskDirectory(id) }
      assertFailsWith<IllegalArgumentException> { store.read(id) }
    }
    assertFailsWith<IllegalArgumentException> { store.create(record(id = "../escape")) }
  }

  @Test
  fun taskDirectoryMustBeExactDirectChildAndListSkipsAliases() {
    val root = newRoot()
    val store = store(root, TestRecordFileFactory())
    store.create(record(id = "real"))
    createSymlinkOrSkip(root.resolve("alias").toPath(), root.resolve("real").toPath())

    assertFailsWith<IllegalArgumentException> { store.taskDirectory("alias") }
    assertEquals(listOf("real"), store.list().map { it.id })

    val outside = newRoot().resolve("outside").apply { mkdirs() }
    outside.resolve("task.json").writeText(record(id = "escape").toJson().toString())
    createSymlinkOrSkip(root.resolve("escape").toPath(), outside.toPath())

    assertFailsWith<IllegalArgumentException> { store.taskDirectory("escape") }
    assertEquals(listOf("real"), store.list().map { it.id })
  }

  @Test
  fun taskFilesMustBeExactDirectFilesNotSymlinks() {
    listOf("task.json", "artifact.download", "artifact.apk").forEachIndexed { index, name ->
      val root = newRoot()
      val store = store(root, TestRecordFileFactory())
      val id = "task_$index"
      store.create(record(id = id))
      val directory = root.resolve(id)
      val direct = directory.resolve(name)
      if (direct.exists()) direct.delete()
      val target = directory.resolve("target_$index").apply {
        writeText(if (name == "task.json") record(id = id).toJson().toString() else "artifact")
      }
      createSymlinkOrSkip(direct.toPath(), target.toPath())

      assertFailsWith<IllegalArgumentException>(name) {
        when (name) {
          "task.json" -> store.read(id)
          "artifact.download" -> store.partialFile(id)
          else -> store.apkFile(id)
        }
      }
    }
  }

  @Test
  fun writesRequireMonotonicRevisionAndCurrentExpectedRevision() {
    val store = store(newRoot(), TestRecordFileFactory())
    val initial = record()
    store.create(initial)

    assertFailsWith<BackgroundDownloadRevisionException> {
      store.write(initial.copy(revision = 1), expectedRevision = 1)
    }
    val next = store.write(initial.copy(revision = 2, downloadedBytes = 10), expectedRevision = 1)
    assertEquals(2, next.revision)
    assertFailsWith<BackgroundDownloadRevisionException> {
      store.write(next.copy(revision = 3), expectedRevision = 1)
    }
  }

  @Test
  fun directStoreWritesRejectEveryImmutableFieldMutation() {
    immutableRecordMutations.forEach { mutation ->
      val store = store(newRoot(), TestRecordFileFactory())
      val initial = record()
      store.create(initial)
      val candidate = mutation.mutate(initial.copy(revision = initial.revision + 1))

      assertFailsWith<BackgroundDownloadStateException>(mutation.name) {
        store.write(candidate, expectedRevision = initial.revision)
      }
      assertEquals(initial, store.read(initial.id), mutation.name)
    }
  }

  @Test
  fun directStoreWritesAllowDocumentedMutableFields() {
    val store = store(newRoot(), TestRecordFileFactory())
    val initial = record(status = BackgroundDownloadStatus.running)
    store.create(initial)

    val updated = store.write(
      initial.copy(
        revision = initial.revision + 1,
        status = BackgroundDownloadStatus.waitingForNetwork,
        downloadedBytes = 5,
        totalBytes = initial.expectedSizeBytes,
        strongEtag = "\"etag\"",
        lastStopReason = 7,
        errorCode = "retry",
        errorMessage = "retry later",
        nativeErrorCode = "503",
        updatedAtEpochMs = initial.updatedAtEpochMs + 1,
      ),
      expectedRevision = initial.revision,
    )

    assertEquals(BackgroundDownloadStatus.waitingForNetwork, updated.status)
    assertEquals(5, updated.downloadedBytes)
    assertEquals("\"etag\"", updated.strongEtag)
    assertEquals(updated, store.read(initial.id))
  }

  @Test
  fun reconcileTruncatesPartialLongerThanDurableCheckpoint() {
    val store = store(newRoot(), TestRecordFileFactory())
    store.create(record(downloadedBytes = 5))
    store.partialFile("task_1").writeBytes(ByteArray(12) { 7 })

    val reconciled = store.reconcileArtifacts("task_1")

    assertEquals(5, store.partialFile("task_1").length())
    assertEquals(1, reconciled.revision)
    assertEquals(5, reconciled.downloadedBytes)
  }

  @Test
  fun reconcileDeletesShortPartialAndCreatesOneCleanPausedRestart() {
    val store = store(newRoot(), TestRecordFileFactory(), now = { 400 })
    store.create(
      record(
        status = BackgroundDownloadStatus.running,
        downloadedBytes = 10,
      ).copy(strongEtag = "\"old\""),
    )
    store.partialFile("task_1").writeBytes(ByteArray(4))

    val reconciled = store.reconcileArtifacts("task_1")

    assertFalse(store.partialFile("task_1").exists())
    assertEquals(BackgroundDownloadStatus.pausedBySystem, reconciled.status)
    assertEquals(0, reconciled.downloadedBytes)
    assertNull(reconciled.strongEtag)
    assertEquals(2, reconciled.revision)
    assertEquals(400, reconciled.updatedAtEpochMs)
  }

  @Test
  fun reconcilePromotesValidVerifyingApkAndFailsInvalidOne() {
    val validRoot = newRoot()
    val validStore = store(validRoot, TestRecordFileFactory(), verifier = { _, _ -> true })
    validStore.create(record(status = BackgroundDownloadStatus.verifying))
    validStore.apkFile("task_1").writeBytes(byteArrayOf(1))
    assertEquals(BackgroundDownloadStatus.completed, validStore.reconcileArtifacts("task_1").status)
    assertTrue(validStore.apkFile("task_1").exists())

    val invalidRoot = newRoot()
    val invalidStore = store(invalidRoot, TestRecordFileFactory(), verifier = { _, _ -> false })
    invalidStore.create(record(status = BackgroundDownloadStatus.verifying))
    invalidStore.apkFile("task_1").writeBytes(byteArrayOf(1))
    val failed = invalidStore.reconcileArtifacts("task_1")
    assertEquals(BackgroundDownloadStatus.failed, failed.status)
    assertEquals("artifact_verification_failed", failed.errorCode)
    assertFalse(invalidStore.apkFile("task_1").exists())
  }

  @Test
  fun reconcileVerifyingWithoutApkPausesWithSafePartialPrefix() {
    val store = store(newRoot(), TestRecordFileFactory(), now = { 500 })
    val verifying = record(
      status = BackgroundDownloadStatus.verifying,
      downloadedBytes = 5,
    ).copy(strongEtag = "\"safe\"")
    store.create(verifying)
    store.partialFile(verifying.id).writeBytes(ByteArray(8))

    val reconciled = store.reconcileArtifacts(verifying.id)

    assertEquals(BackgroundDownloadStatus.pausedBySystem, reconciled.status)
    assertEquals(5, reconciled.downloadedBytes)
    assertEquals("\"safe\"", reconciled.strongEtag)
    assertEquals(5, store.partialFile(verifying.id).length())
    assertEquals(verifying.revision + 1, reconciled.revision)
  }

  @Test
  fun reconcileVerifyingWithoutApkOrPartialFailsInsteadOfWedging() {
    val store = store(newRoot(), TestRecordFileFactory(), now = { 500 })
    val verifying = record(status = BackgroundDownloadStatus.verifying)
    store.create(verifying)

    val reconciled = store.reconcileArtifacts(verifying.id)

    assertEquals(BackgroundDownloadStatus.failed, reconciled.status)
    assertEquals("PACKAGE_DOWNLOAD_FAILED", reconciled.errorCode)
    assertEquals(verifying.revision + 1, reconciled.revision)
  }

  @Test
  fun reconcileVerifyingWithUnsafeShortPartialResetsCleanly() {
    val store = store(newRoot(), TestRecordFileFactory(), now = { 500 })
    val verifying = record(
      status = BackgroundDownloadStatus.verifying,
      downloadedBytes = 5,
    ).copy(strongEtag = "\"unsafe\"")
    store.create(verifying)
    store.partialFile(verifying.id).writeBytes(ByteArray(4))

    val reconciled = store.reconcileArtifacts(verifying.id)

    assertEquals(BackgroundDownloadStatus.pausedBySystem, reconciled.status)
    assertEquals(0, reconciled.downloadedBytes)
    assertNull(reconciled.strongEtag)
    assertFalse(store.partialFile(verifying.id).exists())
  }

  @Test
  fun completedRecordWithMissingOrInvalidApkIsFailedAndNeverMapsCompletedPath() {
    val missingStore = store(newRoot(), TestRecordFileFactory(), verifier = { _, _ -> true })
    missingStore.create(record(status = BackgroundDownloadStatus.completed))

    val missing = missingStore.reconcileArtifacts("task_1")

    assertEquals(BackgroundDownloadStatus.failed, missing.status)
    assertEquals("completed_artifact_missing", missing.errorCode)
    assertNull(
      if (missing.status == BackgroundDownloadStatus.completed) {
        missingStore.apkFile(missing.id).path
      } else {
        null
      },
    )

    val invalidStore = store(newRoot(), TestRecordFileFactory(), verifier = { _, _ -> false })
    invalidStore.create(record(status = BackgroundDownloadStatus.completed))
    invalidStore.apkFile("task_1").writeBytes(byteArrayOf(1))
    val invalid = invalidStore.reconcileArtifacts("task_1")
    assertEquals(BackgroundDownloadStatus.failed, invalid.status)
    assertEquals("completed_artifact_invalid", invalid.errorCode)
    assertFalse(invalidStore.apkFile("task_1").exists())
  }

  @Test
  fun cancelPersistsTombstoneDeletesArtifactsAndRemoveRequiresTerminalState() {
    val root = newRoot()
    val store = store(root, TestRecordFileFactory(), now = { 500 })
    store.create(record(status = BackgroundDownloadStatus.running))
    store.partialFile("task_1").writeBytes(byteArrayOf(1))
    store.apkFile("task_1").writeBytes(byteArrayOf(2))

    val tombstone = store.cancelArtifactsAndWriteTombstone("task_1", expectedRevision = 1)

    assertEquals(BackgroundDownloadStatus.canceled, tombstone.status)
    assertEquals(2, tombstone.revision)
    assertFalse(store.partialFile("task_1").exists())
    assertFalse(store.apkFile("task_1").exists())
    assertEquals(tombstone, store.read("task_1"))
    store.remove("task_1")
    assertFalse(root.resolve("task_1").exists())

    store.create(record(id = "active", status = BackgroundDownloadStatus.queued))
    assertFailsWith<BackgroundDownloadStateException> { store.remove("active") }
    assertNotNull(store.read("active"))
  }

  @Test
  fun canceledTombstoneWriteFailureLeavesActiveRecordAndArtifactsIntact() {
    val root = newRoot()
    val factory = TestRecordFileFactory()
    val store = store(root, factory)
    val active = record(status = BackgroundDownloadStatus.running)
    store.create(active)
    store.partialFile(active.id).writeBytes(byteArrayOf(1))
    store.apkFile(active.id).writeBytes(byteArrayOf(2))
    factory.failNextWrite = true

    assertFailsWith<TestInterruptedWriteException> {
      store.cancelArtifactsAndWriteTombstone(active.id, expectedRevision = active.revision)
    }

    assertEquals(active, store.read(active.id))
    assertTrue(store.partialFile(active.id).exists())
    assertTrue(store.apkFile(active.id).exists())
  }

  @Test
  fun repeatedCancelCleansArtifactsThatAppearAfterTombstone() {
    val store = store(newRoot(), TestRecordFileFactory())
    val active = record(status = BackgroundDownloadStatus.running)
    store.create(active)
    val canceled = store.cancelArtifactsAndWriteTombstone(active.id, active.revision)
    store.partialFile(active.id).writeBytes(byteArrayOf(1))
    store.apkFile(active.id).writeBytes(byteArrayOf(2))

    val repeated = store.cancelArtifactsAndWriteTombstone(active.id, active.revision)

    assertEquals(canceled, repeated)
    assertFalse(store.partialFile(active.id).exists())
    assertFalse(store.apkFile(active.id).exists())
  }

  @Test
  fun startupReconcileCleansResidualArtifactsForCanceledTombstone() {
    val store = store(newRoot(), TestRecordFileFactory())
    val active = record(status = BackgroundDownloadStatus.running)
    store.create(active)
    val canceled = store.cancelArtifactsAndWriteTombstone(active.id, active.revision)
    store.partialFile(active.id).writeBytes(byteArrayOf(1))
    store.apkFile(active.id).writeBytes(byteArrayOf(2))

    val reconciled = store.reconcileArtifacts(active.id)

    assertEquals(canceled, reconciled)
    assertFalse(store.partialFile(active.id).exists())
    assertFalse(store.apkFile(active.id).exists())
  }

  @Test
  fun taskLockAllocationIsFixedAndBounded() {
    val store = store(newRoot(), TestRecordFileFactory())
    repeat(256) { index ->
      store.create(record(id = "task_$index"))
    }

    val field = BackgroundDownloadStore::class.java.getDeclaredField("taskLocks").apply {
      isAccessible = true
    }
    val locks = assertIs<Array<*>>(field.get(store))

    assertEquals(64, locks.size)
  }

  private fun store(
    root: File,
    factory: BackgroundRecordFileFactory,
    verifier: (File, BackgroundDownloadRecord) -> Boolean = { _, _ -> false },
    now: () -> Long = { 300 },
  ): BackgroundDownloadStore = BackgroundDownloadStore(root, factory, verifier, now)

  private fun newRoot(): File = Files.createTempDirectory("background-store-").toFile().also(roots::add)

  private fun writeRawRecord(root: File, id: String, contents: String) {
    if (!BackgroundDownloadContract.isValidId(id)) return
    root.resolve(id).mkdirs()
    root.resolve(id).resolve("task.json").writeText(contents)
  }

  private fun futureSchemaFixture(): FutureSchemaFixture {
    val root = newRoot()
    val store = store(root, TestRecordFileFactory())
    val futureJson = JSONObject(
      record(
        id = "future_guarded",
        revision = 700,
        updatedAtEpochMs = 900,
      ).toJson().toString(),
    ).put("schemaVersion", 2)
    val raw = futureJson.toString()
    writeRawRecord(root, "future_guarded", raw)
    val partialBytes = byteArrayOf(1, 2, 3, 4)
    val apkBytes = byteArrayOf(5, 6, 7)
    root.resolve("future_guarded/artifact.download").writeBytes(partialBytes)
    root.resolve("future_guarded/artifact.apk").writeBytes(apkBytes)
    val synthetic = store.read("future_guarded")
    assertEquals(synthetic, store.list().single())
    return FutureSchemaFixture(
      root = root,
      store = store,
      rawJson = raw,
      partialBytes = partialBytes,
      apkBytes = apkBytes,
      synthetic = synthetic,
    )
  }
}

private data class FutureSchemaFixture(
  val root: File,
  val store: BackgroundDownloadStore,
  val rawJson: String,
  val partialBytes: ByteArray,
  val apkBytes: ByteArray,
  val synthetic: BackgroundDownloadRecord,
) {
  fun assertUnchanged() {
    assertEquals(rawJson, root.resolve("future_guarded/task.json").readText())
    assertContentEquals(partialBytes, root.resolve("future_guarded/artifact.download").readBytes())
    assertContentEquals(apkBytes, root.resolve("future_guarded/artifact.apk").readBytes())
  }
}

private class TestInterruptedWriteException : RuntimeException()
private class TestInterruptedReadException : RuntimeException()

private class TestRecordFileFactory : BackgroundRecordFileFactory {
  var failNextWrite = false
  var failNextRead = false

  override fun create(file: File): BackgroundRecordFile = object : BackgroundRecordFile {
    override fun exists(): Boolean = file.isFile

    override fun readText(): String {
      if (failNextRead) {
        failNextRead = false
        throw TestInterruptedReadException()
      }
      return file.readText()
    }

    override fun writeText(contents: String) {
      if (failNextWrite) {
        failNextWrite = false
        throw TestInterruptedWriteException()
      }
      val temporary = File(file.parentFile, "${file.name}.new")
      temporary.writeText(contents)
      Files.move(
        temporary.toPath(),
        file.toPath(),
        java.nio.file.StandardCopyOption.ATOMIC_MOVE,
        java.nio.file.StandardCopyOption.REPLACE_EXISTING,
      )
    }

    override fun delete() {
      file.delete()
    }
  }
}

private fun createSymlinkOrSkip(link: Path, target: Path) {
  try {
    Files.createSymbolicLink(link, target)
  } catch (error: UnsupportedOperationException) {
    Assumptions.assumeTrue(false, "Symlink creation unsupported: ${error.message}")
  } catch (error: SecurityException) {
    Assumptions.assumeTrue(false, "Symlink creation denied: ${error.message}")
  } catch (error: java.nio.file.FileSystemException) {
    Assumptions.assumeTrue(false, "Symlink creation unavailable: ${error.message}")
  }
}

internal fun record(
  id: String = "task_1",
  revision: Long = 1,
  packageUrl: String = "https://downloads.example.test/app.apk?token=secret",
  status: BackgroundDownloadStatus = BackgroundDownloadStatus.queued,
  downloadedBytes: Long = 0,
  totalBytes: Long? = null,
  expectedSizeBytes: Long = 1_000_000_000L,
  expectedSha256: String = "a".repeat(64),
  maxDownloadBytes: Long = BackgroundDownloadContract.DEFAULT_MAX_DOWNLOAD_BYTES,
  updatedAtEpochMs: Long = 200,
): BackgroundDownloadRecord = BackgroundDownloadRecord(
  revision = revision,
  id = id,
  packageUrl = packageUrl,
  status = status,
  downloadedBytes = downloadedBytes,
  totalBytes = totalBytes,
  expectedSizeBytes = expectedSizeBytes,
  expectedSha256 = expectedSha256,
  maxDownloadBytes = maxDownloadBytes,
  schedulerJobId = BackgroundDownloadContract.DEFAULT_SCHEDULER_JOB_ID,
  notificationId = BackgroundDownloadContract.DEFAULT_NOTIFICATION_ID,
  createdAtEpochMs = 100,
  updatedAtEpochMs = updatedAtEpochMs,
)

internal data class ImmutableRecordMutation(
  val name: String,
  val mutate: (BackgroundDownloadRecord) -> BackgroundDownloadRecord,
)

internal val immutableRecordMutations = listOf(
  ImmutableRecordMutation("id") { it.copy(id = "other") },
  ImmutableRecordMutation("schemaVersion") { record ->
    record.copy().also {
      BackgroundDownloadRecord::class.java.getDeclaredField("schemaVersion").apply {
        isAccessible = true
        setInt(it, BackgroundDownloadContract.SCHEMA_VERSION + 1)
      }
    }
  },
  ImmutableRecordMutation("packageUrl") {
    it.copy(packageUrl = "https://mirror.example.test/changed.apk")
  },
  ImmutableRecordMutation("expectedSha256") { it.copy(expectedSha256 = "b".repeat(64)) },
  ImmutableRecordMutation("expectedSizeBytes") {
    it.copy(expectedSizeBytes = it.expectedSizeBytes + 1)
  },
  ImmutableRecordMutation("maxDownloadBytes") {
    it.copy(maxDownloadBytes = it.maxDownloadBytes - 1)
  },
  ImmutableRecordMutation("schedulerJobId") { it.copy(schedulerJobId = it.schedulerJobId + 1) },
  ImmutableRecordMutation("notificationId") { it.copy(notificationId = it.notificationId + 1) },
  ImmutableRecordMutation("createdAtEpochMs") { it.copy(createdAtEpochMs = it.createdAtEpochMs + 1) },
)

private val SCHEMA_V1_KEYS = setOf(
  "schemaVersion",
  "revision",
  "id",
  "packageUrl",
  "status",
  "downloadedBytes",
  "totalBytes",
  "expectedSizeBytes",
  "expectedSha256",
  "maxDownloadBytes",
  "strongEtag",
  "schedulerJobId",
  "notificationId",
  "lastStopReason",
  "errorCode",
  "errorMessage",
  "nativeErrorCode",
  "createdAtEpochMs",
  "updatedAtEpochMs",
)
