# Plezy 2.20.0 → Tizen 6.0 TV

## Status (execution ledger, not a hardware certification)

Target: Samsung UE55AU7022KXXH, Tizen 6.0, TV, ARM32, release mode.
Direct SDK installation and launch-request acceptance have been verified on
this TV, but the original release crashed during native plugin registration.
The corrected release payload passes the compiled import/export check and now
stays on the login page in a separately installed diagnostic app. Native plugin,
player/window and initial database startup completed on the TV; the operator
confirmed the stable login UI. The corrected production-identity package remains
uninstalled. See [ACCEPTANCE.md](ACCEPTANCE.md) for exact evidence.
Decoder, physical remote, overlay and performance acceptance remain unverified.
No release or remote branch has been published. The authoritative source/toolchain
pins, including the host-test SDK compatibility patch, are `tizen/toolchain.json`.

## Baseline / prior art

- Verified GitHub `/repos/edde746/plezy/releases/latest`: stable 2.20.0,
  published 2026-09-15, neither draft nor prerelease. 2.19.1 is superseded.
- Workspace origin is balcsida/plezy, upstream is edde746/plezy. Clean before
  `gh tidy`; integration branch `feat/tizen-6-tv` starts at the 2.20.0 tag.
- George-Fam/plezy-tizen's true common ancestor with the selected release is
  recorded in the lock. Its ten subsequent commits are port work plus SDK/API
  downgrades, branding and workflow changes—not newer Jellyfin functionality.
- Upstream PR #1164 was closed, not merged, with maintenance concerns. Do not
  replay its old upstream files. PR #1429 concerns telemetry privacy, already
  addressed by current upstream's opt-in build gate.
- Fladder's `Tizen` release tag is **not** the tip of `feat/add-tizen-support`.
  The published asset is `nl.jknaapen.fladder-0.8.1.tpk`; later branch commits
  change seeking, track selection, scaling and the codec profile. The user's
  working installation does not identify which of those later changes it has.
  Related DonutWare/Fladder PR #680 is a reference, not proof of target coverage.

## Adopted / rejected

Adopt the Plezy port's C# FlutterApplication host, package identity
`com.edde746.plezy`, native player channels, transparent video-plane integration,
and Drift-over-sqflite strategy. Adapt these to the **current** contracts.
Preserve the fork's GPL attribution and upstream's license; no Fladder branding
or business logic is transplanted. Preserve Plezy's existing Jellyfin/Plex/Emby UI.

Reject SDK floor reduction, obsolete Jellyfin changes, replacing shared files,
workflow deletion, fork branding, fake window-manager success, swallowed playback
errors, unverified raw EFL P/Invoke, duplicate native Back forwarding, and labeling
video as hardware-decoded based on the audio decoder type.

From Fladder adopt the lesson that native video plus Flutter controls and bounded
TV focus are viable on this TV. Reject index-minus-one track mapping, forced play
on track changes, external ASS/PGS claims, AV1/HDR assumptions, and videoCodec=copy
as the only fallback.

## Backend decision

| Concern | Plezy public .NET bridge (selected) | video_player_videohole (inspected 0.6.0) |
|---|---|---|
| Tizen 6.0 | tizen60 reference assemblies; public Player/ElmSharp APIs | targets common-5.5, TV only; firmware dependencies still need verification |
| Public API constraint | no raw P/Invoke in application bridge | media_player_proxy resolves extension track/display/adaptive functions dynamically; not established as public 6.0 APIs |
| Composition | separate non-focusable window, Flutter transparent region | plugin-managed video hole; attractive but does not remove ABI audit |
| Authentication | User-Agent and constrained redundant token-header elision; query-token transport; unsupported headers fail closed | HTTP header restrictions require a separate audit |
| Seeking | serialize per player; generation guards; public SetPlayPositionAsync | documented keyframe-only seek, rate=1 restriction |
| Tracks/subtitles | public track IDs, SubtitleUpdated plus external text overlay | native track metadata; app still needs external text path |
| Lifecycle | app owns cancellation, event subscriptions, window cleanup | plugin owns much of it, but source logs URI and has restore/play behavior |
| Maintenance | narrow bridge to current Player contract | preferable if public API/header/lifecycle constraints are resolved |

The standard video_player_tizen plugin uses public APIs but explicitly lacks
track-selection methods. No second decoder or generic backend framework is added.

## Toolchain checkpoint

The pinned Flutter-Tizen bootstrap ran successfully on macOS ARM64 (Rosetta is
required by some Tizen tools): Flutter 3.47.1, Dart 3.13.1. CLI `build tpk --help`
confirms release, device-profile tv, target-arch arm, dart-define and security-profile.
Native builds now run in the pinned Focal/.NET 6.0.428 Linux container, with the
API-6 SDK and Python 3.8. Host regressions require Ubuntu 22.04+ for the pinned
SQLite library's glibc requirement. The hash-pinned SDK compatibility patch
restores host-test native-assets wiring without changing SDK versions or the
application database. See [BUILD.md](BUILD.md) for the two execution environments.
The current toolchain still targets Tizen 6.0 for real TV; emulator requirements
must not change that manifest. Engine and embedder hashes are independently pinned.

## Implementation / checks

The staged implementation follows the six stages in the task: host smoke first;
platform and persistent storage; native player contract; existing TV focus;
shared release/sign/inspection scripts and CI; tests and handover.
Update this ledger with actual command outcomes before claiming completion.
