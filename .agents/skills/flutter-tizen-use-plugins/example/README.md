# Example: Wire up a Tizen plugin with privileges

Add `geolocator` + `geolocator_tizen` and request location at runtime, including the manifest declaration.

## Files

- `pubspec.snippet.yaml` — relevant dependencies block.
- `tizen-manifest.snippet.xml` — `<privileges>` + `<feature>` block.
- `request_location.dart` — runtime permission request via `permission_handler`, backed by `permission_handler_tizen`.

## Scenario

User's cross-platform app uses `geolocator`; on Tizen it returns "service disabled" until the right privileges + runtime permission are wired. The three files together flip it to a working state.
