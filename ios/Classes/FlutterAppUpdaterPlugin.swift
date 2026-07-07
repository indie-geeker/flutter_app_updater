import Flutter
import UIKit

public class FlutterAppUpdaterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_app_updater", binaryMessenger: registrar.messenger())
    let instance = FlutterAppUpdaterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "getAppVersionName":
      result(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
    case "getAppVersionCode":
      result(Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
    case "openStore":
      openStore(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openStore(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let storeUrl = arguments["storeUrl"] as? String,
      let url = URL(string: storeUrl),
      url.scheme != nil
    else {
      result(FlutterError(
        code: "INVALID_ARGUMENT",
        message: "storeUrl must be an absolute URL",
        details: nil
      ))
      return
    }

    UIApplication.shared.open(url, options: [:]) { success in
      if success {
        result(true)
      } else {
        result(FlutterError(
          code: "STORE_NOT_AVAILABLE",
          message: "No application can open the store URL",
          details: nil
        ))
      }
    }
  }
}
