package com.indiegeeker.flutter_app_updater

import android.content.Context
import android.content.Intent
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
      "installApp" -> installApp(call.arguments as String, result)
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
}
