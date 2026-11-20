<h1>
  <img src="assets/plezy.png" alt="Plezy 16 logo" height="24" style="vertical-align: middle;" />
  Plezy 16
</h1>

Plezy 16 is an unofficial fork of [Plezy](https://github.com/edde746/plezy) for Samsung TVs running Tizen 6.0. Plezy is a client for Plex, Jellyfin and Emby, built with Flutter. This fork packages it as a native TV app and plays video with the TV's own player instead of mpv.

> [!IMPORTANT]
> This is not an official Plezy build. The Plezy project doesn't maintain or support it, so please report problems in [this repository](https://github.com/balcsida/plezy-16/issues) and not upstream.

<p>
  <a href="https://github.com/balcsida/plezy-16/releases">Releases</a> ·
  <a href="#install">Install</a> ·
  <a href="docs/tizen/BUILD.md">Building</a> ·
  <a href="docs/tizen/ACCEPTANCE.md">Test log</a> ·
  <a href="LICENSE">License</a>
</p>

The 16 is a pun: sixteen is "tizenhat" in Hungarian.

## Status

Plezy 16 is based on Plezy 2.26.0. So far it has run on one TV, my Samsung UE55AU7022KXXH (Tizen 6.0), with a Jellyfin server. The package is built for Tizen 6.0 TVs with a 32-bit ARM processor. A TV with an older Tizen refuses to install it, and I don't know if it runs on newer ones.

Seen working on that TV:

- Signing in to Jellyfin and browsing
- Playing video with audio, seeking and the on-screen controls
- Downloading to a USB drive and playing the downloaded copy, with subtitles
- Installing a new version over the old one, without the app's data being cleared

Not tried on the TV: Emby, music and Watch Together.

Plex and Live TV are not tried either, and I expect playback to fail there. Both send extra headers with a stream, the TV's player can't send them, and the app refuses to play rather than leave them out.

[docs/tizen/ACCEPTANCE.md](docs/tizen/ACCEPTANCE.md) is the full log of what was tested and how.

## What is different on the TV

- The app asks Jellyfin for H.264 video up to 1080p (8-bit) with stereo AAC audio, and the server converts anything else. This is a cautious starting point and not the limit of the TV: HEVC, HDR, AV1 and surround sound are not tested yet, so the app doesn't ask for them.
- SRT and WebVTT subtitles are drawn by the app. ASS/SSA and image subtitles (PGS, DVD) are burned into the video by the server.
- There is no mpv, so the settings that only exist for it are hidden (`mpv.conf`, hardware decoding, the deinterlace and downmix filters).
- External players, audio passthrough, gamepads and the system media controls are off.
- No DRM, and no private Samsung APIs.
- No crash reports are sent to the Plezy project, and the app doesn't check for updates. Watch the [releases](https://github.com/balcsida/plezy-16/releases) instead.

For everything else, see the feature list in the [Plezy README](https://github.com/edde746/plezy#features). Most of it has not been tried on a TV yet.

## Install

Plezy 16 is not in Samsung's app store, so it has to be sideloaded.

1. Turn on Developer Mode on the TV ([how to](https://github.com/Apps2Samsung/Apps2Samsung/wiki/FAQ#-how-to-enable-developer-mode-on-your-tv)).
2. Download `plezy-tizen-6-arm-release.tpk` from the [latest release](https://github.com/balcsida/plezy-16/releases/latest). The `SHA256SUMS` file next to it has its checksum.
3. Install it with [Apps2Samsung](https://github.com/Apps2Samsung/Apps2Samsung): pick the downloaded `.tpk` as your own app and press Install. It signs the package for your TV and installs it.

Apps2Samsung can also take `balcsida/plezy-16` as a source of your own. It then lists the newest release itself, so you can skip the download.

If you would rather use the Tizen SDK and your own certificate, see [Signing for a Samsung TV](docs/tizen/BUILD.md#signing-for-a-samsung-tv).

To update, install the newer release the same way you installed the first one. The TV refuses an update that is signed by a different author, and removing the app first also removes its login and settings.

## Downloads

Downloads go to a USB drive. Without one a download fails, so it can't fill up the TV's own storage.

1. Plug in the drive.
2. In Settings, under Downloads, open Select Folder, press Select Folder in the dialog and pick the drive.
3. Download something. The files go to `Plezy/downloads` on the drive.

A few things to know:

- A download is the original file from the server, so it only plays if the TV's player can decode it.
- A FAT32 drive can't hold a file larger than 4 GB.
- The TV closes the app in standby, so a running download stops. It should start again when you open Plezy 16.
- If the TV mounts the drive under another name, the downloads show as missing until it is back under the old one.
- Deleting a download while the drive is unplugged leaves its files on the drive.

## Building

Every Flutter and Dart command goes through the pinned Flutter-Tizen toolchain in `scripts/tizen/`, not a separate Flutter install.

```sh
scripts/tizen/bootstrap.sh
scripts/tizen/pub_get.sh --enforce-lockfile
scripts/tizen/check.sh
```

The TV package is built in the container from `scripts/tizen/Dockerfile`. [docs/tizen/BUILD.md](docs/tizen/BUILD.md) has the commands and the signing options, and [docs/tizen/PORT.md](docs/tizen/PORT.md) explains how the port is put together.

CI builds a test-signed package for every push, and a `tizen-v*` tag publishes a signed release.

## Relation to Plezy

Plezy is made by [@edde746](https://github.com/edde746). He [allowed](https://github.com/edde746/plezy/pull/1164#issuecomment-6780334501) the "Plezy 16" name and the Plezy icon for this fork, and asked for two things: its own package ID (`com.balcsida.plezy16`) and a clear note that it is unofficial. [TRADEMARKS.md](TRADEMARKS.md) has the rules for the Plezy name and logo.

The Tizen changes sit on top of a Plezy release, 2.26.0 at the moment. Everything that isn't about the TV is upstream's work.

## Thanks

- [@edde746](https://github.com/edde746) for Plezy.
- [@George-Fam](https://github.com/George-Fam) for the [first Tizen port](https://github.com/George-Fam/plezy-tizen) ([edde746/plezy#1164](https://github.com/edde746/plezy/pull/1164)), which this fork builds on.
- [flutter-tizen](https://github.com/flutter-tizen/flutter-tizen) for bringing Flutter to Tizen.
- [Fladder-Tizen](https://github.com/popdollar/Fladder-Tizen), which showed that native video under Flutter controls works on this TV.

## License

GPL-3.0, like Plezy. See [LICENSE](LICENSE).
