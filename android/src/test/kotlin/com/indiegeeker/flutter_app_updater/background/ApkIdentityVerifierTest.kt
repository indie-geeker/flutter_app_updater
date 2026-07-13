package com.indiegeeker.flutter_app_updater.background

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import kotlin.io.path.createTempDirectory
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class ApkIdentityVerifierTest {
  private val roots = mutableListOf<File>()

  @AfterTest
  fun cleanUp() {
    roots.forEach(File::deleteRecursively)
  }

  @Test
  fun completedApkMustMatchInternalPathSizeHashPackageAndSigningLineage() {
    val fixture = fixture("signed apk".toByteArray())
    val verifier = ApkIdentityVerifier(
      store = fixture.store,
      hostPackageName = "com.example.app",
      hostIdentity = ApkPackageIdentity(
        packageName = "com.example.app",
        currentSigners = setOf("old-signer"),
        signingHistory = setOf("old-signer"),
      ),
      archiveIdentityReader = {
        ApkPackageIdentity(
          packageName = "com.example.app",
          currentSigners = setOf("new-signer"),
          signingHistory = setOf("old-signer", "new-signer"),
        )
      },
    )

    assertEquals(fixture.apk.canonicalPath, verifier.verifyCompleted(fixture.record.id).canonicalPath)
  }

  @Test
  fun rejectsHashPackageAndSignerMismatchWithStableCodes() {
    val fixture = fixture("signed apk".toByteArray())
    fixture.apk.writeText("tamper apk")
    assertCode("PACKAGE_HASH_MISMATCH") {
      verifier(fixture, packageName = "com.example.app", signer = "host").verifyCompleted(fixture.record.id)
    }

    val packageFixture = fixture("package mismatch".toByteArray())
    assertCode("BACKGROUND_DOWNLOAD_INVALID_STATE") {
      verifier(packageFixture, packageName = "com.other.app", signer = "host")
        .verifyCompleted(packageFixture.record.id)
    }

    val signerFixture = fixture("signer mismatch".toByteArray())
    assertCode("BACKGROUND_DOWNLOAD_INVALID_STATE") {
      verifier(signerFixture, packageName = "com.example.app", signer = "other")
        .verifyCompleted(signerFixture.record.id)
    }
  }

  @Test
  fun rejectsSymlinkThatEscapesTheInternalTaskDirectory() {
    val fixture = fixture("inside".toByteArray())
    val outside = File(fixture.root.parentFile, "outside-${System.nanoTime()}.apk")
    outside.writeText("outside")
    fixture.apk.delete()
    Files.createSymbolicLink(fixture.apk.toPath(), outside.toPath())

    try {
      assertCode("PACKAGE_FILE_NOT_FOUND") {
        verifier(fixture, packageName = "com.example.app", signer = "host")
          .verifyCompleted(fixture.record.id)
      }
    } finally {
      fixture.apk.delete()
      outside.delete()
    }
  }

  @Test
  fun multipleSignersRequireExactlyEqualCurrentSignerSets() {
    val fixture = fixture("multi signer".toByteArray())
    val host = ApkPackageIdentity(
      packageName = "com.example.app",
      currentSigners = setOf("one", "two"),
      signingHistory = setOf("one", "two"),
      hasMultipleSigners = true,
    )
    fun verifierWith(signers: Set<String>) = ApkIdentityVerifier(
      store = fixture.store,
      hostPackageName = "com.example.app",
      hostIdentity = host,
      archiveIdentityReader = {
        ApkPackageIdentity(
          packageName = "com.example.app",
          currentSigners = signers,
          signingHistory = signers + "one",
          hasMultipleSigners = true,
        )
      },
    )

    assertEquals(
      fixture.apk.canonicalPath,
      verifierWith(setOf("two", "one")).verifyCompleted(fixture.record.id).canonicalPath,
    )
    assertCode("BACKGROUND_DOWNLOAD_INVALID_STATE") {
      verifierWith(setOf("one", "three")).verifyCompleted(fixture.record.id)
    }
  }

  @Test
  fun managedInstallPathIsReverifiedAfterPreparation() {
    val fixture = fixture("signed apk".toByteArray())
    val verifier = verifier(fixture, packageName = "com.example.app", signer = "host")
    val prepared = verifier.verifyCompleted(fixture.record.id)
    fixture.apk.writeText("tamper apk")

    assertCode("PACKAGE_HASH_MISMATCH") {
      verifier.verifyManagedPath(prepared.absolutePath)
    }
  }

  private fun verifier(
    fixture: Fixture,
    packageName: String,
    signer: String,
  ) = ApkIdentityVerifier(
    store = fixture.store,
    hostPackageName = "com.example.app",
    hostIdentity = ApkPackageIdentity(
      packageName = "com.example.app",
      currentSigners = setOf("host"),
      signingHistory = setOf("host"),
    ),
    archiveIdentityReader = {
      ApkPackageIdentity(
        packageName = packageName,
        currentSigners = setOf(signer),
        signingHistory = setOf(signer),
      )
    },
  )

  private fun assertCode(code: String, action: () -> Unit) {
    val error = assertFailsWith<ApkIdentityVerificationException>(block = action)
    assertEquals(code, error.code)
  }

  private fun fixture(bytes: ByteArray): Fixture {
    val root = createTempDirectory("apk-identity").toFile().also(roots::add)
    val hash = MessageDigest.getInstance("SHA-256")
      .digest(bytes)
      .joinToString("") { "%02x".format(it) }
    val store = BackgroundDownloadStore(root, PlainRecordFileFactory)
    val record = BackgroundDownloadRecord(
      revision = 1,
      id = "task-1",
      packageUrl = "https://example.com/update.apk",
      status = BackgroundDownloadStatus.completed,
      downloadedBytes = bytes.size.toLong(),
      totalBytes = bytes.size.toLong(),
      expectedSizeBytes = bytes.size.toLong(),
      expectedSha256 = hash,
      createdAtEpochMs = 1,
      updatedAtEpochMs = 1,
    )
    store.create(record)
    val apk = store.apkFile(record.id)
    apk.writeBytes(bytes)
    return Fixture(root, store, record, apk)
  }

  private data class Fixture(
    val root: File,
    val store: BackgroundDownloadStore,
    val record: BackgroundDownloadRecord,
    val apk: File,
  )
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
      file.delete()
    }
  }
}
