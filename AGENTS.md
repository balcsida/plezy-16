# Plezy Tizen integration

Follow `CONTRIBUTING.md`; preserve non-Tizen backends, schemas, migrations and TLS validation.
The integration baseline and verification ledger are in `docs/tizen/PORT.md`.

## Always-on Flutter-Tizen CLI rule

Read and apply [.agents/flutter-tizen/rules/flutter_tizen_cli.md](.agents/flutter-tizen/rules/flutter_tizen_cli.md).
It is vendored from flutter-tizen/skills at the SHA in `.agents/flutter-tizen/SOURCE`;
its BSD notice is preserved there. Relevant skills and their relative examples are
manually installed in `.agents/skills/` (no global installation).

- Use `scripts/tizen/flutter.sh` for **every Flutter operation** in this checkout:
  dependency resolution, analysis, tests, generation, builds, runs and creation.
  It invokes the pinned flutter-tizen, not a separate Flutter installation.
- Use `scripts/tizen/dart.sh` for Dart tools. Never mix SDKs.
- Build/run/device tests must use `--dart-define=TIZEN_BUILD=true` and the explicit
  TV/ARM arguments in `scripts/tizen/build.sh`. Host regression tests deliberately
  run both with and without this define.
- No invented `flutter-tizen logs`, shell/dlog/key-injection success claims on
  secured TVs. Check `sdb capability`; consume foreground run/test results.
- No DRM, private Samsung APIs, certificate material in git/artifacts, privileged
  PR signing, telemetry to upstream services, or uninstalls to fix installation.
- Keep production API 6.0 / TV / ARM32. Newer emulator manifests are separate.
- Reference checkouts under `.git/tizen-references/` are research-only; never
  modify/publish them. Pins, not their working paths, define the build.

Existing upstream workflows target non-Tizen platforms and retain their original
SDK setup. Do not use those commands to resolve or build this Tizen checkout.
