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
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
