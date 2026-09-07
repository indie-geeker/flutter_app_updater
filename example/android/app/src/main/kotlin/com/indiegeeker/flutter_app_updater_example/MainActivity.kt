package com.indiegeeker.flutter_app_updater_example

import android.content.pm.ApplicationInfo
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // Debug-only verification: never launches an installer or grants a URI.
    if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "updater_example/verification")
      .setMethodCallHandler { call, result ->
        if (call.method != "verifyFileProvider") {
          result.notImplemented()
        } else {
          try {
            val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
            require(file.path.startsWith(filesDir.canonicalPath + File.separator))
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val readable = contentResolver.openInputStream(uri)?.use { it.read() >= 0 } == true
            check(readable)
            result.success(uri.toString())
          } catch (_: Exception) {
            result.error("PATH_NOT_SHAREABLE", "File is not in a readable provider path", null)
          }
        }
      }
  }
}
