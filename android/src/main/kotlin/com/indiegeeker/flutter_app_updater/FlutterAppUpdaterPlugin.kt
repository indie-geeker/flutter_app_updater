package com.indiegeeker.flutter_app_updater

import android.content.Context
import android.content.Intent
import android.content.ActivityNotFoundException
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

/** FlutterAppUpdaterPlugin */
class FlutterAppUpdaterPlugin: FlutterPlugin, MethodCallHandler {

  private lateinit var channel : MethodChannel
  private lateinit var applicationContext: Context

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_app_updater")
    channel.setMethodCallHandler(this)

    applicationContext = flutterPluginBinding.applicationContext
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
      "getAppVersionCode" -> getAppVersionCode(result)
      "getAppVersionName" -> getAppVersionName(result)
      "installApp" -> {
        val filePath = call.arguments as? String
        if (filePath.isNullOrBlank()) {
          result.error("INVALID_ARGUMENT", "安装路径不能为空", null)
          return
        }
        installApp(filePath, result)
      }
      "getDownloadPath" -> getDownloadPath(result)
      "openStore" -> openStore(call, result)
      "startPlayInAppUpdate" -> startPlayInAppUpdate(result)
      else -> result.notImplemented()
    }
  }


  private fun getAppVersionCode(result: Result) {
    try {
      val packageInfo = applicationContext.packageManager.getPackageInfo(applicationContext.packageName, 0)
      if(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        result.success(packageInfo.longVersionCode.toString())
        return
      }
      result.success(packageInfo.versionCode.toString())
    } catch (e: Exception) {
      result.error("VERSION_ERROR", "获取版本号失败", e.message)
    }
  }

  private fun getAppVersionName(result: Result) {
    try {
      val packageInfo = applicationContext.packageManager.getPackageInfo(applicationContext.packageName, 0)
      result.success(packageInfo.versionName)
    } catch (e: Exception) {
      result.error("VERSION_ERROR", "获取版本名称失败", e.message)
    }
  }

  private fun installApp(filePath: String, result: Result) {
    try {
      val file = File(filePath)
      if (!file.exists()) {
        result.error("FILE_NOT_FOUND", "安装文件不存在", null)
        return
      }

      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
          !applicationContext.packageManager.canRequestPackageInstalls()) {
        result.error(
          "INSTALL_PERMISSION_REQUIRED",
          "未授权安装未知来源应用，请在系统设置中允许当前应用安装APK",
          null
        )
        return
      }

      val intent = Intent(Intent.ACTION_VIEW)
      val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        // 适配Android 7.0及以上
        val authority = "${applicationContext.packageName}.fileprovider"
        FileProvider.getUriForFile(applicationContext, authority, file)
      } else {
        Uri.fromFile(file)
      }

      intent.setDataAndType(uri, "application/vnd.android.package-archive")
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

      applicationContext.startActivity(intent)
      result.success(true)
    } catch (e: Exception) {
      result.error("INSTALL_ERROR", "安装失败", e.message)
    }
  }

  private fun getDownloadPath(result: Result) {
    try {
      // 使用应用私有的缓存目录，无需申请存储权限
      // Android 10+(API 29)以后推荐使用应用私有目录
      val downloadDir = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        // Android 10+ 使用应用专属外部存储目录
        applicationContext.getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS)
      } else {
        // Android 10以下，尝试使用外部存储的Download目录
        // 如果无法访问，则回退到应用私有目录
        val externalDownloadDir = android.os.Environment.getExternalStoragePublicDirectory(
          android.os.Environment.DIRECTORY_DOWNLOADS
        )
        if (externalDownloadDir != null && externalDownloadDir.exists()) {
          externalDownloadDir
        } else {
          // 回退到应用私有外部目录
          applicationContext.getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS)
        }
      }

      if (downloadDir != null) {
        // 确保目录存在
        if (!downloadDir.exists()) {
          downloadDir.mkdirs()
        }
        result.success(downloadDir.absolutePath)
      } else {
        // 最终回退：使用应用内部缓存目录
        val cacheDir = applicationContext.cacheDir
        result.success(cacheDir.absolutePath)
      }
    } catch (e: Exception) {
      result.error("PATH_ERROR", "获取下载路径失败", e.message)
    }
  }

  private fun openStore(call: MethodCall, result: Result) {
    val arguments = call.arguments as? Map<*, *>
    val store = arguments?.get("store") as? String
    val storeUrl = arguments?.get("storeUrl") as? String

    if (storeUrl.isNullOrBlank()) {
      result.error("INVALID_ARGUMENT", "storeUrl不能为空", null)
      return
    }

    val uri = Uri.parse(storeUrl)
    if (uri.scheme.isNullOrBlank()) {
      result.error("INVALID_ARGUMENT", "storeUrl必须是绝对URL", null)
      return
    }

    if (store == "googlePlay" && tryOpenStoreIntent(uri, "com.android.vending")) {
      result.success(true)
      return
    }

    if (tryOpenStoreIntent(uri, null)) {
      result.success(true)
      return
    }

    result.error("STORE_NOT_AVAILABLE", "没有可用应用可以打开商店链接", null)
  }

  private fun tryOpenStoreIntent(uri: Uri, packageName: String?): Boolean {
    return try {
      val intent = Intent(Intent.ACTION_VIEW, uri)
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      if (!packageName.isNullOrBlank()) {
        intent.setPackage(packageName)
      }
      applicationContext.startActivity(intent)
      true
    } catch (e: ActivityNotFoundException) {
      false
    } catch (e: Exception) {
      false
    }
  }

  private fun startPlayInAppUpdate(result: Result) {
    result.error(
      "PLAY_IN_APP_UPDATE_UNAVAILABLE",
      "当前原生插件未集成Google Play In-App Updates",
      null
    )
  }
}
