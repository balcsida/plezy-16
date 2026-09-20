# Example: Build TPK across targets

Sample build invocations covering the documented `--device-profile` / `--target-arch` / build-mode combinations from `flutter-tizen/doc/commands.md`.

## Files

- `build_examples.sh` — emulator (debug), Samsung TV (release+obfuscate), Raspberry Pi 4 (release).
- `tizen-manifest.snippet.xml` — matching `<manifest profile="..." api-version="...">` line per target.

## Scenario

User wants a release TPK for a 2022 Samsung TV plus a debug TPK for the TV emulator from the same project. The script shows both calls back to back, then inspects the signed artifact.
