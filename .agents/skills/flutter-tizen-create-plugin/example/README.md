# Example: Wrap a Tizen Native API as a Flutter plugin

`foo_tizen` plugin exposing `app_get_data_path()` (Tizen Native API) through a `MethodChannel`.

## Files

- `foo_tizen.dart` — Dart-facing API.
- `foo_tizen_plugin.cc` — C++ plugin, registrar + method-channel handler.
- `project_def.prop` — pkg-config wiring (`capi-appfw-app-common`).
- `tizen-manifest.snippet.xml` — privileges + feature declarations the consumer app must copy.

## Scenario

User has a cross-platform Flutter app that needs `app_get_data_path()` (Tizen-only). The four files together produce a usable `FooTizen().getDataPath()` call.
