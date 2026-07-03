#include "flutter_app_updater_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <sstream>
#include <string>

namespace flutter_app_updater {

namespace {

std::optional<std::string> GetStringArgument(
    const flutter::EncodableValue* arguments,
    const char* key) {
  if (arguments == nullptr ||
      !std::holds_alternative<flutter::EncodableMap>(*arguments)) {
    return std::nullopt;
  }

  const auto& map = std::get<flutter::EncodableMap>(*arguments);
  auto iterator = map.find(flutter::EncodableValue(std::string(key)));
  if (iterator == map.end() ||
      !std::holds_alternative<std::string>(iterator->second)) {
    return std::nullopt;
  }

  return std::get<std::string>(iterator->second);
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }

  const int size_needed = MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(),
                      size_needed);
  return result;
}

}  // namespace

// static
void FlutterAppUpdaterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "flutter_app_updater",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterAppUpdaterPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FlutterAppUpdaterPlugin::FlutterAppUpdaterPlugin() {}

FlutterAppUpdaterPlugin::~FlutterAppUpdaterPlugin() {}

void FlutterAppUpdaterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
  } else if (method_call.method_name().compare("getAppVersionName") == 0 ||
             method_call.method_name().compare("getAppVersionCode") == 0 ||
             method_call.method_name().compare("getDownloadPath") == 0) {
    result->Success(flutter::EncodableValue());
  } else if (method_call.method_name().compare("openInstaller") == 0) {
    auto installer_path =
        GetStringArgument(method_call.arguments(), "installerPath");
    if (!installer_path.has_value() || installer_path->empty()) {
      result->Error("INVALID_ARGUMENT", "installerPath is required");
      return;
    }

    auto wide_path = Utf8ToWide(installer_path.value());
    HINSTANCE shell_result = ShellExecuteW(nullptr, L"open", wide_path.c_str(),
                                           nullptr, nullptr, SW_SHOWNORMAL);
    if (reinterpret_cast<intptr_t>(shell_result) <= 32) {
      result->Error("INSTALLER_OPEN_FAILED", "Failed to open installer");
      return;
    }

    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

}  // namespace flutter_app_updater
