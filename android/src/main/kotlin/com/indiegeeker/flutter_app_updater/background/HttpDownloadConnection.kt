package com.indiegeeker.flutter_app_updater.background

import java.io.ByteArrayInputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLConnection

internal data class HttpDownloadRequest(
  val url: String,
  val headers: Map<String, String>,
)

internal interface HttpDownloadConnection : AutoCloseable {
  val statusCode: Int
  fun header(name: String): String?
  fun body(): InputStream
  override fun close()
}

internal fun interface HttpDownloadConnectionFactory {
  fun open(request: HttpDownloadRequest): HttpDownloadConnection
}

/**
 * A connection factory whose opener may be bound to an Android Network by the
 * scheduler layer. The default opener uses the process default network.
 */
internal class UrlHttpDownloadConnectionFactory(
  private val opener: (URL) -> URLConnection = URL::openConnection,
  private val connectTimeoutMs: Int = 15_000,
  private val readTimeoutMs: Int = 30_000,
) : HttpDownloadConnectionFactory {
  override fun open(request: HttpDownloadRequest): HttpDownloadConnection {
    val connection = opener(URL(request.url)) as? HttpURLConnection
      ?: throw BackgroundDownloadProtocolException("Download URL is not HTTP(S)")
    connection.instanceFollowRedirects = false
    connection.connectTimeout = connectTimeoutMs
    connection.readTimeout = readTimeoutMs
    connection.requestMethod = "GET"
    for ((name, value) in request.headers) {
      connection.setRequestProperty(name, value)
    }
    return UrlHttpDownloadConnection(connection)
  }
}

private class UrlHttpDownloadConnection(
  private val connection: HttpURLConnection,
) : HttpDownloadConnection {
  override val statusCode: Int
    get() = connection.responseCode

  override fun header(name: String): String? = connection.getHeaderField(name)

  override fun body(): InputStream = if (statusCode >= 400) {
    connection.errorStream ?: ByteArrayInputStream(byteArrayOf())
  } else {
    connection.inputStream
  }

  override fun close() {
    connection.disconnect()
  }
}
