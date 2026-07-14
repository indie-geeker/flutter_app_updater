package com.indiegeeker.flutter_app_updater.background

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.io.IOException
import java.security.MessageDigest

internal data class ApkPackageIdentity(
  val packageName: String,
  val currentSigners: Set<String>,
  val signingHistory: Set<String>,
  val hasMultipleSigners: Boolean = false,
)

internal class ApkIdentityVerificationException(
  val code: String,
  message: String,
  cause: Throwable? = null,
) : Exception(message, cause)

internal class ApkIdentityVerifier(
  private val store: BackgroundDownloadStore,
  private val hostPackageName: String,
  private val hostIdentity: ApkPackageIdentity?,
  private val archiveIdentityReader: (File) -> ApkPackageIdentity?,
) {
  constructor(context: Context, store: BackgroundDownloadStore) : this(
    store = store,
    hostPackageName = context.packageName,
    hostIdentity = AndroidApkIdentityReader.installed(context.packageManager, context.packageName),
    archiveIdentityReader = { file ->
      AndroidApkIdentityReader.archive(context.packageManager, file)
    },
  )

  fun verifyCompleted(id: String): File {
    val record = try {
      store.read(BackgroundDownloadContract.requireValidId(id))
    } catch (error: Exception) {
      throw ApkIdentityVerificationException(
        "BACKGROUND_DOWNLOAD_NOT_FOUND",
        "Background download task was not found.",
        error,
      )
    }
    if (record.status != BackgroundDownloadStatus.completed) {
      throw ApkIdentityVerificationException(
        "BACKGROUND_DOWNLOAD_INVALID_STATE",
        "Only a completed background download can be prepared for installation.",
      )
    }
    val apk = try {
      store.apkFile(id)
    } catch (error: Exception) {
      throw ApkIdentityVerificationException(
        "PACKAGE_FILE_NOT_FOUND",
        "The completed APK is not a safe internal package file.",
        error,
      )
    }
    return verifyFile(apk, record.expectedSizeBytes, record.expectedSha256)
  }

  /** Verifies integrity and application identity immediately before handoff. */
  fun verifyFile(
    file: File,
    expectedSizeBytes: Long?,
    expectedSha256: String?,
  ): File {
    val apk = try {
      file.canonicalFile
    } catch (error: IOException) {
      throw ApkIdentityVerificationException(
        "PACKAGE_FILE_NOT_FOUND",
        "The APK path cannot be resolved safely.",
        error,
      )
    }
    if (!apk.isFile) {
      throw ApkIdentityVerificationException("PACKAGE_FILE_NOT_FOUND", "The APK file is missing.")
    }
    if ((expectedSizeBytes == null) != (expectedSha256 == null)) {
      throw ApkIdentityVerificationException(
        "PACKAGE_HASH_MISMATCH",
        "APK size and SHA-256 must be supplied together.",
      )
    }
    if (expectedSizeBytes != null && apk.length() != expectedSizeBytes) {
      throw ApkIdentityVerificationException("PACKAGE_HASH_MISMATCH", "The APK size changed.")
    }
    if (expectedSha256 != null && !sha256(apk).equals(expectedSha256, ignoreCase = true)) {
      throw ApkIdentityVerificationException("PACKAGE_HASH_MISMATCH", "The APK hash changed.")
    }

    val installed = hostIdentity ?: throw ApkIdentityVerificationException(
      "PACKAGE_SIGNATURE_INVALID",
      "The installed application signing identity is unavailable.",
    )
    val archive = archiveIdentityReader(apk) ?: throw ApkIdentityVerificationException(
      "PACKAGE_SIGNATURE_INVALID",
      "The file is not a readable APK.",
    )
    if (archive.packageName != hostPackageName || installed.packageName != hostPackageName) {
      throw ApkIdentityVerificationException(
        "PACKAGE_SIGNATURE_INVALID",
        "The APK package ID does not match the host application.",
      )
    }
    if (!hasCompatibleSigningIdentity(installed, archive)) {
      throw ApkIdentityVerificationException(
        "PACKAGE_SIGNATURE_INVALID",
        "The APK signing identity is not compatible with the installed application.",
      )
    }
    return apk
  }

  /** Revalidates managed artifacts immediately before the installer handoff. */
  fun verifyManagedPath(
    path: String,
    expectedSizeBytes: Long?,
    expectedSha256: String?,
  ): File? {
    val id = try {
      store.managedApkTaskId(path)
    } catch (error: Exception) {
      throw ApkIdentityVerificationException(
        "PACKAGE_FILE_NOT_FOUND",
        "The managed APK path is no longer safe.",
        error,
      )
    } ?: return null
    val verified = verifyCompleted(id)
    if (expectedSizeBytes != null || expectedSha256 != null) {
      return verifyFile(verified, expectedSizeBytes, expectedSha256)
    }
    return verified
  }

  private fun sha256(file: File): String = try {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().buffered().use { input ->
      val buffer = ByteArray(64 * 1024)
      while (true) {
        val read = input.read(buffer)
        if (read < 0) break
        if (read > 0) digest.update(buffer, 0, read)
      }
    }
    digest.digest().joinToString("") { "%02x".format(it) }
  } catch (error: IOException) {
    throw ApkIdentityVerificationException("PACKAGE_FILE_NOT_FOUND", "The completed APK cannot be read.", error)
  }

  private fun hasCompatibleSigningIdentity(
    installed: ApkPackageIdentity,
    archive: ApkPackageIdentity,
  ): Boolean {
    if (installed.currentSigners.isEmpty() || archive.currentSigners.isEmpty()) return false
    if (installed.hasMultipleSigners || archive.hasMultipleSigners) {
      return installed.hasMultipleSigners && archive.hasMultipleSigners &&
        installed.currentSigners == archive.currentSigners
    }
    val installedCurrent = installed.currentSigners.singleOrNull() ?: return false
    return installedCurrent in archive.signingHistory
  }
}

private object AndroidApkIdentityReader {
  @Suppress("DEPRECATION")
  fun installed(packageManager: PackageManager, packageName: String): ApkPackageIdentity? =
    runCatching {
      val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        PackageManager.GET_SIGNING_CERTIFICATES
      } else {
        PackageManager.GET_SIGNATURES
      }
      packageInfoIdentity(packageManager.getPackageInfo(packageName, flags))
    }.getOrNull()

  @Suppress("DEPRECATION")
  fun archive(packageManager: PackageManager, file: File): ApkPackageIdentity? =
    runCatching {
      val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        PackageManager.GET_SIGNING_CERTIFICATES
      } else {
        PackageManager.GET_SIGNATURES
      }
      packageManager.getPackageArchiveInfo(file.absolutePath, flags)?.let(::packageInfoIdentity)
    }.getOrNull()

  @Suppress("DEPRECATION")
  private fun packageInfoIdentity(info: PackageInfo): ApkPackageIdentity {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      val signingInfo = checkNotNull(info.signingInfo)
      val current = signingInfo.apkContentsSigners.orEmpty().map(::fingerprint).toSet()
      val history = if (signingInfo.hasMultipleSigners()) {
        current
      } else {
        signingInfo.signingCertificateHistory.orEmpty().map(::fingerprint).toSet()
      }
      return ApkPackageIdentity(info.packageName, current, history, signingInfo.hasMultipleSigners())
    }
    val current = info.signatures.orEmpty().map(::fingerprint).toSet()
    return ApkPackageIdentity(info.packageName, current, current, current.size > 1)
  }

  private fun fingerprint(signature: android.content.pm.Signature): String =
    MessageDigest.getInstance("SHA-256")
      .digest(signature.toByteArray())
      .joinToString("") { "%02x".format(it) }
}
