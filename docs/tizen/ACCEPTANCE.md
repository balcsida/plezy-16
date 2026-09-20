# Tizen acceptance checklist

**Status: Jellyfin video playback is confirmed working on UE55AU7022KXXH /
Tizen 6.0 under the real `com.edde746.plezy` identity: picture, audio, seek and
the Flutter controls together. Startup, login, database and in-place signed
upgrade are also verified. Decoder counters, physical remote, long-run stability
and the remaining device-matrix rows are still unverified.**
Use the exact TPK SHA, TV model/firmware, source-input fingerprint and signing
category in every record. Do not substitute editor diagnostics or mocked
channels for device evidence.

## Current device evidence

- The earlier Apps2Samsung deployment opened and then closed, as observed by
  the operator. No exception or root cause was captured; deployment was not
  established as the cause.
- After the operator removed that installation, the unchanged runtime sources
  were rebuilt through `scripts/tizen/build.sh --test-signing`.
- Original failing package: version 2.20.0, API 6.0 / TV / ARM32, disposable
  test-only signing. Its output path was subsequently replaced by the corrected
  build; identify it by the hash below.
- TPK SHA-256: `3a3a274a0ade699ecb1111a136e301119126fe5c6d2ca90d45fa7b62c2cd7bdd`.
- Source-input SHA-256: `25c676937b0993ef879c479112a9a3c5a9bb396337b490dba2000f8db5c8b1cb`
  (matches the previous build; disposable signing changes the package hash).
- Structural inspection and checksum verification passed. SDK SDB 4.2.36
  reported `install completed`; SDK `tizen run` accepted launch with PID 444.
- Installation did not use Apps2Samsung. No agent-issued uninstall was run.
  The operator confirmed that this directly installed package also closes
  immediately. The failure therefore reproduces without Apps2Samsung.
- Bounded SDK-forwarded logging accepted a handshake and captured EGL startup
  on the Novatek / Mali-G52 r23p0 driver, then disconnected. The default launch
  logged selection of Impeller; one temporary `--enable-impeller=false` launch
  omitted that message but also disconnected immediately. Both probes restored
  the previous SDK launch arguments. A renderer switch alone did not resolve
  the exit.
- With operator approval, a separate `com.edde746.plezy.startupprobe` application
  (label **Plezy Startup**) was installed without replacing Plezy. Its TPK
  SHA-256 is `866e43a2d834a3e69d0c8f95740a5e2f81cd67c4d22a90c467dcd4604ac4a4e7`.
  Sanitized native stage tracing captured `create.after-base`, followed by
  `System.EntryPointNotFoundException` at
  `GeneratedPluginRegistrant.IntegrationTestPluginRegisterWithRegistrar`.
  Plugin registration failed before media-player construction.
- The release `.so` omits development-only plugins, but the pinned SDK's
  pre-build `pub get` generated a host registration call for the development
  integration-test plugin; `--no-pub` did not regenerate it for release.
  A compiled-host import/export regression check reproduced the missing
  symbol on the original production TPK.
- After removing the native test plugin from the production dependency graph,
  the release rebuild succeeded. All five compiled native plugin imports now
  match packaged exports; inspection and checksum verification passed.
  Corrected TPK SHA-256:
  `5edf2e14830128a5f185d2be86c2cc920d74f899422467337e467ad1ad58a526`.
  Source-input SHA-256:
  `82b88ecd4a6dffd087a251c270f2629ade035fff02aa353468e3c315c71935c2`.
  This corrected production package has **not** been installed on the TV.
- To avoid replacing an app signed by a different disposable author, a separate
  `com.edde746.plezy.startupfixed` / **Plezy Startup Fixed** diagnostic host was
  compiled with the SDK's public `tz` commands. Its `lib/` and `res/` contents
  are byte-identical to the corrected release; only the C# diagnostic host and
  identity differ. Native compilation had zero warnings/errors, and all five
  plugin imports plus structural inspection passed. Its TPK SHA-256 is
  `8a1dcd1a6be31f0ddbc7a248631699a07c29c29bdaa42e50ee9e729aa7a52780`.
- The fixed diagnostic installation reached 86%, then SDB reported
  `error: target not found`; the initial reconnect failed. The operator later
  confirmed that the TV had been switched off. After power was restored, SDB
  reconnected and listed the original app and both separate diagnostics.
  The installed fixed diagnostic's author-signature XML matches the inspected
  TPK byte-for-byte. No reinstall, uninstall or data deletion was needed.
- The fixed diagnostic launch accepted PID 1262. The bounded logger accepted
  its handshake and showed Dart startup, the first Flutter frame, database-ready
  and credentials-loaded stages without an early disconnect. Native tracing
  reached `create.after-plugins`, captured `TizenSynchronizationContext`, and
  completed player/window creation, focus-skip, channel binding and
  `create.after-player`, followed by `resume`.
- The operator confirmed that the app stayed open on the login page. Their
  subsequent closure was explicitly accidental, not an application crash.
  The same diagnostic was relaunched through the SDK, accepting PID 1940.
  Temporary launch arguments were restored after capture. This verifies a
  startup smoke test of the diagnostic, not playback or upgrade persistence.
- The operator's Jellyfin playback attempt failed with the generic
  `Tizen could not open this stream` message. A native-only trace update was
  compiled with zero warnings/errors and five matching plugin imports, using
  the same diagnostic author and byte-identical production `lib/` and `res/`.
  Its TPK SHA-256 is
  `b66fbf0a0ddf1f0313d3f1261c2e566addfd1f70498d817eb6f3be5dd56e24f3`.
  The first update attempt failed before transfer because SDB had disconnected;
  that transport failure is separate from the playback failure. After reconnect,
  the SDK reported installation completed, the installed signature XML matched
  this update, and its launch accepted PID 2055. No app data was cleared.
  Two retries reached `open.prepared`, audio tracks and `open.subtitle-tracks`,
  then failed with `System.InvalidOperationException` from
  `Tizen.Multimedia.PlayerErrorCodeExtensions.GetException`. Cleanup separately
  raised `AggregateException` with `Player.ValidatePlayerState`: API 6 retains
  the preparation cancellation callback, which is valid only while Preparing.
- The native bridge now discards unavailable optional subtitle metadata only
  while Ready, without publishing a partial subtitle list, and stops cancelling
  completed preparation. Cleanup still disposes native resources if cancellation
  fails. Codecs, authentication, Dart payload and renderer settings are unchanged.
  The linked-source host tests reproduced four failures before the fixes, then
  passed all five checks; geometry passed all 11 checks. These use host-only
  native API doubles and do not prove device playback. CI runs both suites.
  The new diagnostic compiled with zero warnings/errors and five matching imports:
  TPK `9e960ec5ea2a39868d7f282cef92655ced27050642c0c6bf9c6fb5f25d20e38d`,
  host inputs `3e857e42738619fd7321c931277fa45f3f620170a1cd4254e53bb8ed4d13a287`.
  It retains the diagnostic author and identical historical production `lib/`
  and `res/`. Once the TV was reachable again, the SDK reported `install completed`
  as an in-place update (no uninstall, no app data cleared), the installed
  signature XML matched this TPK byte-for-byte, and `tizen run` accepted launch
  with PID 1076. The historical production TPK does not contain these host fixes.
- With that build the operator retried Jellyfin playback. The subtitle-metadata
  failure did not recur: the sanitized trace reached `open.subtitle-unavailable`,
  `open.ready`, `open.play` and `open.complete` on both attempts, and the operator
  confirmed audible playback and working seek. The video plane, however, was not
  visible; the transparent Flutter window showed the TV's own screen behind it.
- Root cause: the bridge set `Display` and the ROI but never
  `DisplaySettings.IsVisible`. The Tizen default is not visible, so the overlay
  plane stayed hidden while audio decoded normally. All three flutter-tizen video
  plugins (`video_player`, `video_player_avplay`, `video_player_videohole`) call
  `player_set_display_visible(player, true)` immediately after setting the display
  and treat failure as fatal; the Plezy reference host sets `IsVisible = true`.
  The fix adds that one call, before preparation, matching the plugin order.
  A linked-source host check now asserts it: three of five native bridge checks
  failed before the fix and all five pass after, with geometry still 11 of 11.
  Host API doubles do not prove the TV composites the plane; that is the open item.
- The disposable author used for every package installed so far was lost with its
  session keyring, so none of those apps can be updated in place. Per BUILD.md the
  resolution is a preserved author key, now held outside the repository, plus the
  operator removing the never-working original `com.edde746.plezy` installation.
  No agent-issued uninstall was performed.
- The overlay never appeared with the visibility fix alone. The operator confirmed
  the TV's own screen still showed through the transparent window, which excludes a
  missing Flutter hole and a failed decode, leaving window stacking. `window.Lower()`
  had placed the separate `plezy-video` window below the whole application, including
  the TV launcher. Lowering was removed and the embedding's public `IsTopLevel` now
  raises the Flutter window above the video window, with the `window.priority.set`
  privilege declared in the manifest; the packaged manifest was checked for it.
  Stack order is launcher, video plane, then Flutter controls.
- TPK `625a5b0746eadb0709cad8ae460227611432bace38f0e464b8d6469455a34bb6` installed
  as an in-place signed upgrade over the previous build: no uninstall, no data
  cleared, installed signature byte-identical to the package, launch PID 530.
  The operator then confirmed working video with audio, seek and visible controls.
  This is a functional confirmation by observation, not a measured A/V benchmark.
- Signing now uses a preserved author key held outside the repository, so upgrades
  install in place. Losing it would again force a reinstall; it is the operator's
  to back up. The per-session disposable authors are no longer used for the TV.
- `inspection.json` remains the build-time report; its installation flag is
  not retroactively changed. Independent cryptographic verification is pending.

## Current host regression evidence

- The pinned SDK omitted both native-assets builder registration and test-command
  wiring. Restoring those exposes the host SQLite library; Focal then rejects it
  because it requires glibc 2.33 or newer. The same database test passes on
  glibc 2.35 without changing the application database.
- The SDK backport is now hash-pinned in `tizen/toolchain.json`, applied by
  bootstrap and checked by the wrappers. Three isolated SDK-fixture tests pass,
  covering rejection of the unpatched SDK, idempotence/cache invalidation, and
  preservation of conflicting edits. Both package-inspector tests also pass.
- On the modern Linux host, the selected database/focus/Jellyfin/platform/player
  regression run passed **287 tests, with 3 skipped**. The separate invocation
  with `TIZEN_BUILD=true` passed **all 10 tests**.
- The Back fixtures now use the Flutter binding's key-message dispatcher;
  direct `HardwareKeyboard.handleKeyEvent` had bypassed FocusManager. Their
  physical Escape surrogate tests logical GoBack propagation, not TV key mapping.
  No production focus behavior was changed for this fixture correction.
- The full Linux check formatted 1512 files with no changes, but stopped at the
  analyzer's three-minute deadline under x86 emulation. That Linux invocation
  is not a passing full-check result.
- The complete `scripts/tizen/check.sh` subsequently passed on native macOS ARM64:
  1512 files formatted with no changes, analyzer with zero diagnostics, isolated
  code-generation verification, both Python suites, 287 regression tests with
  3 skips, and all 10 Tizen-defined tests. The analyzer deadline and diagnostic
  allowances were not weakened.
- CI now separates Ubuntu 22.04 host checks from the pinned Focal API-6 package
  build. Actionlint passes. The four guarded upstream workflows have no added
  yamllint findings relative to the baseline; inherited formatting is preserved.
  No GitHub workflow execution is claimed.

## Verification tiers

1. Static analysis and workflow/shell/Python checks.
2. Host Dart tests, including current non-Tizen database/focus/Jellyfin tests.
3. Native geometry assertions and C# compilation.
4. Release-mode ARM32 package build and structural inspection.
5. Independent signature/trust verification and installation authorization.
6. Actual TV behavior, persistence, remote control and resource measurements.

Only report a tier as passed with its own executed evidence. An SDK-generated
signature and a package containing signature XML do not establish tiers 5–6.

## Isolated device storage suite

`integration_test/tizen_storage_test.dart` exercises native path/preferences
plugins, AES-GCM credential wrapping, a real Drift/sqflite transaction, schema
creation and database reopen. It uses a unique temporary database and synthetic
data, then deletes only its own fixture directory and preference key. It does
not prove persistence across application/process restarts or a real upgrade.

This suite is **authored but not device-packaged/executed**. Before execution,
prepare a separate test application identity and the same build-local SQLite
hook configuration as `build.sh`, in an isolated source copy. Follow the pinned
integration-test guide in `.agents/skills/flutter-tizen-integration-test/`.
Add `integration_test_tizen` **only to that isolated harness**, from
`https://github.com/flutter-tizen/plugins`, path `packages/integration_test`,
ref `49f314d80f66e0c7c6106f4a2bc0af9a2bf72bba`. Declare it as a harness runtime
dependency if testing a release build; release tooling excludes dev-only
native plugins. Keep it out of the production app dependency graph to avoid
stale registration calls in the pinned SDK's `pub get` → `--no-pub` path.
Do not replace an installed production app or modify its signing identity merely
to run tests. Completing this isolated device harness is still pending.

The existing vault's security model is retained: AES-GCM ciphertext in database
records, with the key in app-private preferences. This protects against casual
database-only inspection; it is **not hardware-backed key storage**, and access
to both preferences and the database permits recovery.

## Device matrix

Use a dedicated Jellyfin test account/library and synthetic media, not personal
credentials in scripts, logs, screenshots or bug reports.

| Area | Required acceptance |
| --- | --- |
| Startup | Cold/warm launch, no unsupported-plugin crash, no fork Sentry traffic |
| Server | Discovery/manual URL, HTTPS certificate validation, `/jellyfin` base path |
| Authentication | Login/relogin, expired token, rejected unsupported headers; no URL/token logs |
| Direct play | H.264/AAC stereo MP4 within the conservative profile |
| Transcode | Unsupported container/codec/audio triggers compatible H.264/AAC HLS, not an unsafe direct fallback |
| HLS | Master/media playlists, segment URLs, seek ranges, redirects and origin/credential boundaries |
| Audio | Sparse server indexes, language selection, paused selection without autoplay, transcode re-selection |
| Subtitles | SRT/VTT UTF-8, off, seek/replacement cancellation, base paths, same-origin redirect enforcement |
| Unsupported captions | Explicit conversion/burn-in flow for ASS/SSA/bitmap formats; never claim native styling |
| Resume/reporting | Resume offset, progress cadence, watched/completed state, stop/transcode cleanup |
| Remote | Physical arrows, Enter/OK/select, one Back action, key hold/repeat, menus and dialogs |
| Focus | Visible TV focus, route/dialog return restoration, no native-window focus theft |
| Geometry | Non-fullscreen viewport, contain/cover/fill, aspect ratios, native crop reset, overlays |
| Lifecycle | Home/app switch, suspend during prepare/seek, resume paused picture without autoplay |
| Ownership | Rapid A→B→C replacement, stale prepare/seek/error events and stale disposal |
| Completion/error | Video window hidden/released, state cleaned up, retry works |
| Storage | Login/preferences/history survive process restart and signed upgrade, migration/FK/rollback behavior |
| Failures | Offline server, TLS error, unsupported codec, denied media, empty/corrupt preferences/database |
| Long run | Repeated opens/seeks/suspend/resume, memory growth, buffering, audio/video sync |

Physical key mapping and system Back delivery are not established by Flutter
key-event tests. No native key forwarding/grabbing or fake window-manager API is
used. The TV's own runtime must confirm the single Flutter input path.

## Performance and privacy

One diagnostic launch recorded a first Flutter UI frame at 128 ms, database-ready
at 1435 ms and credentials-loaded at 2025 ms, relative to Dart main. These exclude
native startup before Dart main and are not cold/warm benchmarks or video-frame
measurements. Memory, seek and frame-drop results remain unmeasured. Dedicated
opt-in playback timing instrumentation is still pending. Record prepare completion
separately from an actually observed first video frame; never rename a prepare
callback into a measured first-frame event.

For manual acceptance, record cold/warm startup, request-to-prepare, visible
first frame, seek completion, memory before/after repeated playback, and playback
stability at the conservative bitrate. Use the same synthetic clip/conditions
for comparisons. Mark unavailable decoder/renderer counters as **unknown**, not
hardware acceleration or zero dropped frames.

Do not upload raw SDK/device logs. Check for authenticated URLs, tokens, headers,
key paths and personal metadata locally before sharing any bounded, redacted
extract. Only the explicitly allowlisted build artifacts belong in ordinary PR CI.

## Remaining implementation/review work

- Finish legacy local helper CLI audit; only `scripts/tizen/` is the supported
  fork build path. Upstream CI/release workflows are repository-guarded.
- Complete the plugin/settings capability audit and non-Tizen regression run.
- Exercise native playback/track/lifecycle races, real HLS authentication and
  subtitle burn-in/conversion, not just fake channel responses.
- Execute the isolated device suite and process-restart/upgrade checks.
- Establish independent cryptographic verification and Samsung entitlement.
- Run the checked-in GitHub workflow and record its actual run URL.

Do not call the port production-ready while these acceptance gates remain open.
