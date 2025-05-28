#include "include/flutter_app_updater/flutter_app_updater_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_app_updater_plugin.h"

void FlutterAppUpdaterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_app_updater::FlutterAppUpdaterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
