---
name: flutter-tizen-build-tpk
description: Build, sign, and inspect Tizen TPK packages for Flutter apps with `flutter-tizen build tpk`. Use when producing a deployable artifact for a specific device profile (`common` or `tv`), when troubleshooting signing failures, when a TPK install fails with signing or architecture mismatch errors, or when controlling ABI / build mode for emulator vs. real device.
metadata:
  target: flutter-tizen
  category: build
  last_modified: Wed, 27 May 2026 08:02:04 GMT
---
# Building Tizen TPKs from Flutter apps

## Background

`flutter-tizen build tpk` compiles the Flutter app, links it against the Tizen embedder, and packs the result as a `.tpk`. Output lands at:

```
build/tizen/tpk/<packageId>-<version>.tpk
```

Three knobs control the output:

- `--device-profile {common|tv}` — selects which Tizen profile the package targets. **Default is `tv`** (verified via `flutter-tizen build tpk --help`), so always pass `--device-profile` explicitly rather than relying on the default. **The TV profile must be matched explicitly; `common` packages will not install on Samsung TV.** The official `flutter-tizen` `doc/commands.md` documents only `common` and `tv`; phone targets land under `common`. Legacy `mobile` / `wearable` profiles are gone — use flutter-tizen 3.16.2 or older for Galaxy Watch.
- `--target-arch {arm|arm64|x86|x64}` — must match the device CPU. Default is `arm`. Current emulators are 64-bit `x64`: the Tizen 10.0 TV emulator (verified `cpu_arch:x86_64` on `T-samsung-10.0-x86_64`) and the common 10.x emulator are both `x64`; only older TV images (9.0 and earlier) are 32-bit `x86`. Verify with `sdb -s <id> capability | grep cpu_arch` — **not** `sdb shell uname -m`, which the secured TV emulator blocks (`intershell_support:disabled`, returns nothing). `x64` requires `api-version="8.0"` or newer in `tizen/tizen-manifest.xml`; the default generated `6.0` manifest fails. Real TVs and RPi are `arm` or `arm64`.
- `--debug` / `--profile` / `--release` — Flutter build mode. Defaults to `--release`. Emulators require a JIT-capable build, i.e. `--debug`.

The package is signed using the active `tizen security-profile`. See [flutter-tizen-setup](../flutter-tizen-setup/SKILL.md) before running this skill.

## Choosing a device profile and ABI

Match the profile and arch to the target. Mismatches produce installer errors that look like file-corruption.

| Target | `--device-profile` | `--target-arch` | Notes |
|---|---|---|---|
| Samsung TV 2021+ (real) | `tv` | `arm` (32-bit) | Tizen TV signing keys also required for store submission |
| Tizen TV emulator (TV 10.0 image) | `tv` | `x64` | 64-bit (verified `cpu_arch:x86_64`); must build `--debug` (JIT only) |
| Tizen TV emulator (TV 9.0 and older) | `tv` | `x86` | 32-bit, must build `--debug` (JIT only) |
| Raspberry Pi 4 (Tizen OS) | `common` | `arm` or `arm64` | Match the installed Tizen image word size |
| Tizen common emulator (Tizen 10.x) | `common` | `x64` | 64-bit; older images use `x86`. Must build `--debug`; set manifest `api-version` to `8.0`+ |

Find the target's arch with `sdb capability` — it works on every target, including TV (where `sdb shell` is blocked, so `sdb shell uname -m` returns nothing):

```sh
sdb -s <device-id> capability | grep -E 'cpu_arch|profile_name'
```

## Build modes

- `--debug` — JIT-based AOT-disabled build. Required for any Tizen emulator. Enables `hot reload` when launched via `flutter-tizen run`.
- `--profile` — AOT, instrumentation enabled. Use to measure performance on real hardware. Not runnable on emulators.
- `--release` — AOT, instrumentation stripped. Default. Use for store submission.

Pair `--release` with `--obfuscate --split-debug-info=<dir>` for production. The split-debug directory is what you keep to symbolize crashes later via `flutter-tizen symbolize`.

## Signing

TPKs must be signed at build time; there is no "sign later" step in the flutter-tizen flow.

- The build uses the currently-active `tizen security-profile`. Check with `tizen security-profiles list`.
- Override per build:
  ```sh
  flutter-tizen build tpk --security-profile my-profile
  ```
- Distributor certs must include the DUID of every device you intend to side-load to. A "package is not authorized" install error on a fresh device means the device's DUID is not in the cert.

## Workflow: Produce a Signed TPK

Copy this checklist:

### Task Progress
- [ ] **Step 1: Confirm toolchain.** `flutter-tizen doctor -v` clean; `tizen security-profiles list` shows a profile.
- [ ] **Step 2: Identify the target.** Capture `device-profile` and `target-arch` from `sdb -s <id> capability`.
- [ ] **Step 3: Pick build mode.** `--debug` for emulators; `--release` for store / hardware; `--profile` for benchmarks.
- [ ] **Step 4: Run the build.**
   ```sh
   flutter-tizen build tpk \
       --device-profile <profile> \
       --target-arch <arch> \
       [--debug|--profile|--release] \
       [--security-profile <name>] \
       [--obfuscate --split-debug-info=build/symbols]
   ```
- [ ] **Step 5: Locate the TPK** at `build/tizen/tpk/`.
- [ ] **Step 6: Sanity-install** on the target:
   ```sh
   sdb -s <device-id> install build/tizen/tpk/<file>.tpk
   ```
   The output must end with `key[end]   val[ok]`. Anything else means signing or profile mismatch.
- [ ] **Step 7: Capture symbol files** (release builds) into version control or artifact storage — without them, future crash reports are unreadable.

## Inspecting the output

A TPK is a ZIP. Useful one-liners:

```sh
# Manifest contents (privileges, profile, api-version, appid)
unzip -p build/tizen/tpk/*.tpk tizen-manifest.xml | head -40

# Signature blocks (must contain both author-signature.xml and signature1.xml)
unzip -l build/tizen/tpk/*.tpk | grep -E 'signature|manifest'

# Listed appid (used by sdb install/uninstall, launch, etc.)
unzip -p build/tizen/tpk/*.tpk tizen-manifest.xml | grep -oE 'appid="[^"]+"'
```

## Common failures

| Build / install error | Cause | Fix |
|---|---|---|
| `signature is invalid` at install time | Signing profile distributor cert does not include device DUID | Re-issue distributor cert with the device DUID; rebuild |
| `Tizen package is not authorized` | DUID mismatch or `--security-profile` not set | Rebuild with the correct `--security-profile` |
| Build OK, install reports `cannot find symbol` for libflutter | `--target-arch` mismatch | Rebuild with the device's actual arch (`sdb -s <id> capability \| grep cpu_arch`) |
| Emulator launches the TPK but app crashes immediately | Built `--release` for an emulator | Rebuild with `--debug` |
| `Failed to find security-profile` | No active profile | Run setup skill; `tizen security-profiles set-active <name>` |
| App installs but appid disappears | `tizen-manifest.xml` declares an api-version newer than the device firmware | Lower `api-version` in `tizen/tizen-manifest.xml` to one supported by the device |

## Examples

```sh
# Emulator (Tizen common 10.x, x64, debug)
# Requires api-version="8.0" or newer in tizen/tizen-manifest.xml.
flutter-tizen build tpk --device-profile common --target-arch x64 --debug

# Emulator (Tizen TV 10.0, x64, debug) — verified cpu_arch:x86_64
flutter-tizen build tpk --device-profile tv --target-arch x64 --debug

# Emulator (Tizen TV 9.0 and older, x86, debug)
flutter-tizen build tpk --device-profile tv --target-arch x86 --debug

# Samsung TV (2021+), release, with profile override
flutter-tizen build tpk \
    --device-profile tv \
    --target-arch arm \
    --release \
    --security-profile tv-store \
    --obfuscate --split-debug-info=build/symbols

# Raspberry Pi 4 with 64-bit Tizen image
flutter-tizen build tpk --device-profile common --target-arch arm64 --release
```
