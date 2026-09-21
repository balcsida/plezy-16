# Building the Tizen 6 TV port

This is a native Flutter-Tizen/C# port of Plezy **2.20.0**, not a WebView or a
Fladder UI. The target is Samsung UE55AU7022KXXH, API 6.0, TV, **ARM32**.
See [PORT.md](PORT.md) and `tizen/toolchain.json` for provenance and exact pins.

## Evidence and limits

- The current native host, including ROI geometry, has compiled against the
  configured `tizen60` project. This does not prove every runtime API on the TV.
- The pure .NET geometry tests have passed. Dart channel tests use fake native
  channels; they are not playback or physical-remote tests.
- Early release-mode, disposable-test-signed TPKs installed but closed
  immediately; the cause was a missing integration-test registration entry
  point, since corrected. That history is superseded by the entries below and
  is retained only in [ACCEPTANCE.md](ACCEPTANCE.md), with hashes.
- A production-identity package signed by the preserved author is installed on
  the target TV as an in-place upgrade. The operator has confirmed Jellyfin
  playback with picture, audio, seek and the Flutter controls together. See
  [ACCEPTANCE.md](ACCEPTANCE.md) for the current status line and evidence.
- Independent cryptographic verification and Samsung entitlement remain open,
  as do storage/remote acceptance and the device-matrix rows. `inspection.json`
  still reports `cryptographic_signature_verified` and `tv_installation_verified`
  as false: it is a build-time structural report and is not retroactively
  changed by a later successful installation.
- CI has been run on GitHub and pre-releases are published from `tizen-v*` tags.
  A green workflow and an attached package are build evidence, not device
  acceptance.

## Reproducible Linux environment

All Flutter and Dart operations use the pinned Flutter-Tizen toolchain. Its
bootstrap applies the hash-pinned `host-test-native-assets.patch`, restoring
both the native-assets builder registration and test-command wiring from the
bundled Flutter CLI. Wrappers reject an unpatched SDK; bootstrap invalidates
its compiled snapshot and refuses conflicting changes. SDK versions are not
changed. The patch's upstream BSD license is included beside it.

Run host regressions on **Ubuntu 22.04 or newer** (glibc >= 2.33). The pinned
sqlite3 host library cannot load on Focal's glibc 2.31; do not work around that
by changing Plezy's database or bundling a host library in the TV package.

```sh
scripts/tizen/bootstrap.sh
scripts/tizen/pub_get.sh --enforce-lockfile
scripts/tizen/check.sh
```

For the **API-6 native package build**, use the digest-pinned focal/.NET 6 image
in `scripts/tizen/Dockerfile`: its SDK installer needs Python 3.8. CI likewise
runs host tests on Ubuntu 22.04 and the native build in this separate container.
Do not downgrade Plezy's Flutter/Dart constraints.

From the repository root, on a Docker host:

```sh
docker build --platform linux/amd64 \
  --build-arg BUILDER_UID="$(id -u)" \
  --build-arg BUILDER_GID="$(id -g)" \
  -t plezy-tizen-build scripts/tizen

docker run --rm --init --platform linux/amd64 --cap-add IPC_LOCK \
  -v "$PWD:/work" plezy-tizen-build bash -c '
    set -euo pipefail
    scripts/tizen/bootstrap.sh --sdk
    scripts/tizen/pub_get.sh --enforce-lockfile
    dotnet run --project test/tizen_native/GeometryTests.csproj
    scripts/tizen/build.sh --test-signing
  '
```

On Apple Silicon, the x86 SDK runs under emulation. If its Java VM crashes,
add `-e '_JAVA_OPTIONS=-Xint -XX:+UseSerialGC'` to `docker run`; this was used
successfully for the local SDK/signing probe. Native x86 CI does not need it.

`IPC_LOCK` permits gnome-keyring's existing secure-memory capability. Do **not**
strip that capability, use a privileged container, disable TLS verification,
or change the host's security settings as an installation workaround.

`build.sh --test-signing` creates a private session bus, keyring, random author
certificate and temporary profile. Certificate/password command output is
suppressed. Signing material is removed when the build exits. The profile is
never selected as the user's global active profile. Optional
`TIZEN_KEEP_SOURCE=1` retains only a diagnostic source tree; never upload it.

The staged build alone disables SQLite FFI asset bundling. Production Tizen
uses Drift over `sqflite_tizen`; the caller's desktop SQLite configuration,
existing schema and migration code are not replaced.

The release command retains these required arguments:

```text
build tpk --release --device-profile tv --target-arch arm
  --dart-define=TIZEN_BUILD=true --security-profile <profile> --no-pub
```

## Outputs

The output directory defaults to `build/tizen-release` (`TIZEN_OUTPUT_DIR`
overrides it). Only these files are CI artifacts:

- `plezy-tizen-6-arm-release.tpk`
- `inspection.json`
- `SHA256SUMS`

Inspection checks identity, TV/API/version, package paths, required files,
ARM32 little-endian ELF headers, absence of hard-float/SQLite FFI/debug assets,
and signature XML presence. It **does not verify XML signatures or TV trust**.
Read the explicit verification booleans, not just the build's exit code.
The release build also checks the compiled `Runner.dll` native plugin imports
against the packaged `libflutter_plugins.so` exports, using .NET metadata and
`readelf` (binutils). A missing registration entry point fails the build.

Native integration-test plugins belong only in the isolated device harness,
not the production dependency graph. The pinned SDK can retain development
registration calls after `pub get` when the release build uses `--no-pub`,
while omitting the corresponding native library symbols.

The inspection record includes the Git revision, working-tree dirty flag and
a SHA-256 fingerprint of staged source inputs before dependency generation.
The fingerprint hashes sorted relative UTF-8 paths followed by NUL and each
file's binary SHA-256 digest. Dependencies and toolchain pins are recorded in
the staged lockfile/manifest; this is provenance, not a reproducible-binary
claim. Disposable certificates and signing timestamps make package hashes vary.

Do not upload SDK homes, caches, profiles, keyrings, source staging trees,
private keys, raw device logs or authenticated media URLs.

## Signing for a Samsung TV

A `test-only` package establishes buildability, **not permission to install on
a retail Samsung TV**. In a trusted Linux SDK session, configure a Samsung TV
certificate/profile containing the target TV's DUID and unlock its keyring.
Keep all personal signing material outside the repository and CI.

```sh
TIZEN_SECURITY_PROFILE=your-samsung-tv-profile scripts/tizen/build.sh
```

This is labelled `user-profile-unverified` until independently checked and
accepted by the actual device. SDK signing success alone is not entitlement
verification. Installation and launch must follow the pinned SDK's documented
CLI/device instructions and the TV's normal Developer Mode flow.

Preserve the author key for upgrades and back it up securely. A disposable
author per build cannot upgrade an installed app: Tizen refuses the update and
the only ways out are a reinstall, which loses app data, or a separate test
identity. Build with a preserved key instead, supplying it from outside the
repository:

```sh
TIZEN_AUTHOR_P12=/path/author.p12 TIZEN_AUTHOR_PASSWORD_FILE=/path/author.pwd \
  scripts/tizen/build_signed.sh
```

It registers the key in a private session bus and keyring, removes the profile
on exit, and then runs the same `build.sh` release path. Certificate output is
suppressed and the key is never copied into the tree or into an artifact.

If an installed app has a different author, **do not uninstall it or erase its
data to bypass that error**. Resolve certificate ownership or use an explicitly
separate test application identity. Never use rooting, DRM workarounds or
private Samsung APIs.

## Fork-safe automation

`.github/workflows/tizen.yml` uses read-only PR permissions, pinned actions,
the pinned container recipe and an artifact allowlist. Its default
`tv-arm-release` job signs disposably, needs no TV and no secrets, and is the
only job that runs for a pull request.

A second `tv-arm-signed-release` job produces installable downloads. It is
repository-guarded, runs only on `workflow_dispatch` or a `tizen-v*` tag, and
reads `TIZEN_AUTHOR_P12_BASE64` and `TIZEN_AUTHOR_PASSWORD` repository secrets.
GitHub withholds secrets from fork pull requests, so that job cannot run for
one. The key is staged outside the workspace, mounted read-only, and deleted
after the build; only the three allowlisted files are ever uploaded. A tagged
run also attaches them to a GitHub release, marked as a pre-release when the
tag carries a semver pre-release identifier such as `tizen-v2.20.1-rc1`. Signing material still must not be
committed, and this remains sideload signing, not Samsung Store entitlement.

Inherited upstream CI/release/publishing jobs are repository-guarded. Their
formatting diagnostics were compared with the stable baseline; no new
`yamllint` findings were introduced. Legacy local desktop/release helpers are
not the Tizen build entry point; use `scripts/tizen/` exclusively. Their broader
CLI audit is still pending. Never run an upstream publishing helper on this fork.

Use [ACCEPTANCE.md](ACCEPTANCE.md) before calling the port TV-ready.
