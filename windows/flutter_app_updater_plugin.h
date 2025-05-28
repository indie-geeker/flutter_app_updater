#ifndef FLUTTER_PLUGIN_FLUTTER_APP_UPDATER_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_APP_UPDATER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_app_updater {

class FlutterAppUpdaterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterAppUpdaterPlugin();

  virtual ~FlutterAppUpdaterPlugin();

  // Disallow copy and assign.
  FlutterAppUpdaterPlugin(const FlutterAppUpdaterPlugin&) = delete;
  FlutterAppUpdaterPlugin& operator=(const FlutterAppUpdaterPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace flutter_app_updater

#endif  // FLUTTER_PLUGIN_FLUTTER_APP_UPDATER_PLUGIN_H_
