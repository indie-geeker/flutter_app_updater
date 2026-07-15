package com.indiegeeker.flutter_app_updater.background

import java.net.URI

internal object BackgroundDownloadUrlPolicy {
  private const val PERSISTENT_ENTRY_MESSAGE =
    "Persistent background downloads require a credential-free stable entry URL; " +
      "the server may redirect to a short-lived signed URL."
  private const val TRANSPORT_TARGET_MESSAGE =
    "Background download transport targets require HTTPS or true loopback HTTP " +
      "without userinfo or fragments."

  fun isAllowedPersistentEntry(value: String): Boolean =
    parseAllowedTransport(value, allowQuery = false) != null

  fun requirePersistentEntry(value: String): String {
    require(isAllowedPersistentEntry(value)) { PERSISTENT_ENTRY_MESSAGE }
    return value
  }

  fun isAllowedTransportTarget(value: String): Boolean =
    parseAllowedTransport(value, allowQuery = true) != null

  fun requireTransportTarget(value: String): String {
    require(isAllowedTransportTarget(value)) { TRANSPORT_TARGET_MESSAGE }
    return value
  }

  private fun parseAllowedTransport(value: String, allowQuery: Boolean): URI? {
    val uri = try {
      URI(value)
    } catch (_: Exception) {
      return null
    }
    val rawHost = uri.host?.lowercase()?.trim().orEmpty()
    if (!uri.isAbsolute || rawHost.isBlank()) return null
    if (uri.rawUserInfo != null || uri.rawFragment != null) return null
    if (!allowQuery && uri.rawQuery != null) return null
    if (uri.scheme.equals("https", true)) return uri
    if (!uri.scheme.equals("http", true)) return null
    val host = rawHost.removePrefix("[").removeSuffix("]")
    return uri.takeIf {
      host == "localhost" || host == "::1" || isIpv4Loopback(host)
    }
  }

  private fun isIpv4Loopback(host: String): Boolean {
    val parts = host.split('.')
    if (parts.size != 4) return false
    val octets = parts.map { part ->
      if (part.isEmpty() || part.any { !it.isDigit() }) return false
      part.toIntOrNull()?.takeIf { it in 0..255 } ?: return false
    }
    return octets.first() == 127
  }
}
