---
name: flutter-tizen-create-plugin
description: Scaffold a new Tizen-side Flutter plugin (C++ or C#), wire it to Dart through a method channel, declare the right privileges in `tizen-manifest.xml`, and validate it against a device or emulator. Use when creating a new Flutter plugin for Tizen, when no existing Tizen plugin wraps a needed Tizen Native API, when a plugin's C++ build fails with link errors, or when extending a cross-platform plugin with a `_tizen` implementation.
metadata:
  target: flutter-tizen
  category: plugins
  last_modified: Wed, 27 May 2026 08:02:04 GMT
---
# Creating a Tizen Flutter plugin

## Decide: C++, C#, or Dart FFI

| Language | When to pick it | When not to |
|---|---|---|
| **C++** | The Tizen Native API you need is a C header (`<system_info.h>`, `<app_control.h>`, `<bluetooth.h>`, …). C++ plugins work with both C++ and C# app projects. | The API is only exposed through Tizen.* .NET assemblies. |
| **C#** | The host app is a C# Tizen app and the API is exposed via Tizen.* assemblies. | C++ app projects, cross-app plugin reuse, or perf-sensitive native loops. |
| **Dart FFI** | The API is a stable C ABI exposed by a system shared library and there's no event-callback handshake needed. | Anything that needs Tizen lifecycle bindings, registrar messengers, or `Ecore_*` mainloop integration. |

This skill focuses on **C++ plugins**, which are the default flutter-tizen plugin scaffold and the reusable path across app project languages.

## Decide: standalone vs federated implementation

- **Adding Tizen support to an existing plugin** (e.g. you want `foobar_tizen` to back `foobar`):
  - Use the plugin name `<base>_tizen` (`foobar_tizen`).
  - Implement the platform interface from the base plugin.
  - Mark your package as the Tizen implementation in `pubspec.yaml`.
  - Consumers must list both `foobar` and `foobar_tizen` (unless the base plugin endorses you).
- **New, Tizen-only feature** (`tizen_app_control`, `tizen_messageport`, …):
  - Single package, no platform interface package.
  - Pick a `lowercase_with_underscores` name.

## Scaffold the plugin

```sh
# Tizen-only or unendorsed implementation
flutter-tizen create \
    --platforms tizen \
    --template plugin \
    --tizen-language cpp \
    --org com.example \
    foo_tizen

cd foo_tizen
```

This produces:

```
foo_tizen/
├── lib/
│   ├── foo_tizen.dart                       # Dart-facing API
│   ├── foo_tizen_platform_interface.dart    # platform-interface base
│   └── foo_tizen_method_channel.dart        # MethodChannel wiring
├── tizen/
│   ├── inc/foo_tizen_plugin.h
│   ├── src/foo_tizen_plugin.cc              # C++ implementation
│   ├── src/log.h
│   ├── project_def.prop                     # Tizen native build settings
├── example/                                 # runnable harness app
│   └── tizen/tizen-manifest.xml             # privileges + appid metadata
└── pubspec.yaml
```

The scaffold already populates `pubspec.yaml` with the Tizen plugin class (auto-filled, not prompted — verified). Confirm it reads:

```yaml
flutter:
  plugin:
    platforms:
      tizen:
        pluginClass: FooTizenPlugin
        fileName: foo_tizen_plugin.h
```

## Implement the C++ side

Two layers:

1. **Method channel handler** — wired in `RegisterWithRegistrar` (already templated).
2. **Tizen Native API call** — replace the template `getPlatformVersion` body.

Minimal pattern:

```cpp
#include "foo_tizen_plugin.h"

#include <app_common.h>            // example Tizen native header
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "log.h"

namespace {

class FooTizenPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrar *registrar) {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "foo_tizen",
            &flutter::StandardMethodCodec::GetInstance());
    auto plugin = std::make_unique<FooTizenPlugin>();
    channel->SetMethodCallHandler(
        [p = plugin.get()] (const auto &call, auto result) {
          p->HandleMethodCall(call, std::move(result));
        });
    registrar->AddPlugin(std::move(plugin));
  }

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const auto &name = call.method_name();
    if (name == "getDataPath") {
      char *path = app_get_data_path();
      if (path == nullptr) {
        result->Error("APP_ERROR", "app_get_data_path returned null");
        return;
      }
      result->Success(flutter::EncodableValue(std::string(path)));
      free(path);
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
```

If the Tizen API needs link-time libraries, edit `tizen/project_def.prop`. The generated scaffold ships **only** these lines (verified on a fresh `flutter-tizen create --template plugin`):

```
type = staticLib
USER_SRCS += src/*.cc
USER_INC_DIRS = inc src
```

`USER_PKGS` and `USER_LIBS` are **not** present by default — you add them. There are two fields to keep straight:

```
# Tizen Native pkg-config module names — resolves both include dirs and
# link libraries via pkg-config. ADD this line for capi-* / dlog / vconf / ...
USER_PKGS = capi-appfw-app-common capi-system-info

# Plain link libraries (no -l prefix, no pkg-config). ADD this for
# system libs like pthread or for sharedLib plugins that link the
# Flutter embedder directly.
USER_LIBS =
```

Two pitfalls here:

- **`capi-*` belongs in `USER_PKGS`, not `USER_LIBS`.** They are pkg-config modules; resolving them with `USER_LIBS` silently misses the include paths and the build fails at link time with `undefined reference`.
- **Default plugin scaffold is `type = staticLib`.** The plugin is linked into the host TPK at app-build time, so most plugins do not need `USER_LIBS` at all — listing `USER_PKGS` is enough. `USER_LIBS` is mainly needed for `type = sharedLib` plugins (see flutter-tizen PR #407 for that path).

Event channels — replace `MethodChannel` with `EventChannel<flutter::EncodableValue>` and emit via the `StreamHandler` callback.

## Implement the Dart side

```dart
// lib/foo_tizen.dart
import 'foo_tizen_method_channel.dart';

class FooTizen {
  Future<String?> getDataPath() => FooTizenMethodChannel.instance.getDataPath();
}

// lib/foo_tizen_method_channel.dart
import 'package:flutter/services.dart';

class FooTizenMethodChannel {
  FooTizenMethodChannel._();
  static final instance = FooTizenMethodChannel._();
  static const _channel = MethodChannel('foo_tizen');

  Future<String?> getDataPath() => _channel.invokeMethod<String>('getDataPath');
}
```

When implementing a federated platform interface instead, override the base plugin's `XxxPlatform` class and call `XxxPlatform.instance = FooTizenPlatform()` in a `registerWith()` static method (see Flutter's federated-plugin docs for the exact pattern).

## Declare privileges and features

The generated plugin package does not include a runtime app manifest; the generated example app has `example/tizen/tizen-manifest.xml` with **no privileges** by default. Native APIs typically refuse to run without the right `<privilege>` line, even if the binary linked successfully.

For privilege categories (public / partner / platform), the privacy privilege list, and the Dart-side `permission_handler_tizen` flow, see [flutter-tizen-use-plugins](../flutter-tizen-use-plugins/SKILL.md). This section covers plugin-specific concerns.

If a privilege the agent picks is Partner / Platform, surface the limitation explicitly — building will succeed locally but signing fails or the device rejects the TPK on install.

### Lookup recipe

1. Open the Tizen Native API doc for the function being called (e.g. `app_get_data_path` → "Required privileges: none"; `location_manager_start` → `http://tizen.org/privilege/location`).
2. Add the URL under `<privileges>` in the host app's `tizen/tizen-manifest.xml` and in the plugin's example app manifest or documented snippet.
3. If it is a privacy privilege, also request it at runtime.
4. If the function needs a hardware feature (camera, bluetooth, NFC), add a matching `<feature>` selector so the package is filtered out on devices that lack the hardware. Without `<feature>`, the store install succeeds on incompatible hardware and the API throws at first call.

Example with both:

```xml
<privileges>
    <privilege>http://tizen.org/privilege/internet</privilege>
    <privilege>http://tizen.org/privilege/mediastorage</privilege>
    <privilege>http://tizen.org/privilege/location</privilege>
</privileges>
<feature name="http://tizen.org/feature/network.internet"/>
<feature name="http://tizen.org/feature/location"/>
```

### Runtime permission from C++ (plugin-only path)

When the plugin must request permission from native code without Dart-side `permission_handler`:

```cpp
#include <privacy_privilege_manager.h>

void RequestLocation() {
  ppm_request_permission(
      "http://tizen.org/privilege/location",
      [](ppm_call_cause_e cause,
         ppm_request_result_e result,
         const char* privilege,
         void* user_data) {
        // dispatch back to Dart via MethodChannel reply
      },
      this);
}
```

Always handle three outcomes — granted, denied (re-ask later), denied-forever (open settings).

### Declaring privileges on both sides

Plugin package manifests are *metadata only* when present — the host app is what the OS evaluates at install / runtime. Two places must agree:

- The plugin's documented manifest snippet or example app `tizen/tizen-manifest.xml` — for documentation, generator tooling, and the example app fallback.
- Every consumer app's `tizen-manifest.xml` — the OS reads this one. Document the required privileges in the plugin README so consumers know what to copy.

## Workflow: Bring up a New Plugin

### Task Progress
- [ ] **Step 1: Confirm scope.** Standalone or federated? C++ vs C#? Pick once.
- [ ] **Step 2: Scaffold** with `flutter-tizen create --template plugin --tizen-language cpp`.
- [ ] **Step 3: Update `pubspec.yaml`** with the Tizen `pluginClass` and `fileName`.
- [ ] **Step 4: Replace `getPlatformVersion`** in the C++ source with the real Tizen Native API call.
- [ ] **Step 5: Add native API packages** in `tizen/project_def.prop` (`USER_PKGS` for `capi-*`; `USER_LIBS` only for plain libraries without pkg-config).
- [ ] **Step 6: Add `<privilege>` and `<feature>` entries** in the plugin's documented manifest snippet and the example app's `tizen/tizen-manifest.xml`.
- [ ] **Step 7: Define the Dart API** in `lib/<plugin>.dart` and the method-channel layer in `lib/<plugin>_method_channel.dart`.
- [ ] **Step 8: Build the example app** for the target profile, install, and exercise every Dart method while watching the foreground `flutter-tizen run` console.
- [ ] **Step 9: Add `flutter_test` widget tests** at minimum; integration tests on a real device if the API depends on Tizen runtime state.

## Testing the plugin

```sh
# From the example/ directory of the plugin
cd example
flutter-tizen -d <id> run --debug   # Dart print/debugPrint + PlatformException stream here
```

The foreground `flutter-tizen run` console is the verification surface that works on **every** target, including TV. Bridge native state to the Dart layer so it shows there:

- The template `src/log.h` `LOGI(...)` / `LOGE(...)` macros write to the **dlog buffer**. Readable with `sdb dlog` / `dlogutil` on targets where `sdb shell` is available (common emulator, Raspberry Pi), but **not on the Samsung TV emulator** (`secure_protocol:enabled`, no `sdb shell` / `dlogutil`), and dlog never appears in the `flutter-tizen run` console. Do not rely on dlog for verification on TV.
- Return native results through the method channel and `debugPrint` them; throw a `PlatformException` on failure so the Dart side prints the code/message in the `run` console. This is the only native-state inspection path that works on every target, including the TV emulator.

For unit tests on the Dart layer, mock `MethodChannel` via `TestDefaultBinaryMessengerBinding`:

```dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('foo_tizen');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'getDataPath') return '/opt/usr/apps/com.example.demo/data/';
    return null;
  });
  test('getDataPath returns', () async {
    expect(await FooTizen().getDataPath(), startsWith('/opt/usr/apps/'));
  });
}
```

## Pitfalls

- **Privilege missing from the *example app's* manifest.** Plugin metadata/snippets are documentation; the host app's manifest decides runtime privileges. The runnable example must declare the privilege.
- **Wrong `api-version`.** A plugin built for `6.0` won't load on a `5.5` device; bumping it past what the device firmware supports breaks `install`. Test on the lowest device version you ship for.
- **`USER_LIBS` syntax.** Library names are bare (`capi-appfw-app-common`), not `-lcapi-appfw-app-common`. The build accepts the wrong form silently and fails at link time with `undefined reference`.
- **Plugin not registered in TPK.** For default `staticLib` plugins, confirm `lib/libflutter_plugins.so` is packed by `unzip -l build/tizen/tpk/*.tpk | grep libflutter_plugins`; only `sharedLib` plugins appear as a plugin-named `.so`. If missing, `flutter-tizen clean` and rebuild.
- **Hot reload skips native changes.** Editing `.cc` requires a full rebuild + reinstall. Only Dart-side changes hot-reload.
- **Memory leaks from Tizen `free`-required strings.** Any Tizen API that returns `char *` typically transfers ownership; always `free()` after copying into `std::string`, as in the template.
