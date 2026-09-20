// foo_tizen_plugin.cc
// C++ plugin wiring app_get_data_path() into the `foo_tizen` method channel.

#include "foo_tizen_plugin.h"

#include <app_common.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar.h>
#include <flutter/standard_method_codec.h>

#include <cstdlib>
#include <memory>
#include <string>

#include "log.h"

namespace {

class FooTizenPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrar* registrar) {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "foo_tizen",
            &flutter::StandardMethodCodec::GetInstance());
    auto plugin = std::make_unique<FooTizenPlugin>();
    channel->SetMethodCallHandler(
        [p = plugin.get()] (const auto& call, auto result) {
          p->HandleMethodCall(call, std::move(result));
        });
    registrar->AddPlugin(std::move(plugin));
  }

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "getDataPath") {
      char* path = app_get_data_path();
      if (!path) {
        result->Error("APP_ERROR", "app_get_data_path returned null");
        return;
      }
      result->Success(flutter::EncodableValue(std::string(path)));
      std::free(path);  // Tizen transfers ownership of the buffer.
    } else {
      result->NotImplemented();
    }
  }
};

}  // namespace

void FooTizenPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FooTizenPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrar>(registrar));
}
