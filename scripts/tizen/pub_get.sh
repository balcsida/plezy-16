#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_toolchain
if "$TOOLCHAIN/bin/flutter-tizen" pub get "$@"; then exit 0; fi
# The stable upstream lock pins a commit no longer fetched by a mirror clone.
# Fetch that EXACT commit into Pub's existing mirror; never change the lock/ref.
url=https://github.com/edde746/background_downloader
sha=c52103f4a2d683c22ce3b8b8661da610644bfef1
mirror="${PUB_CACHE:-$HOME/.pub-cache}/git/cache/background_downloader-1d7b12fd19de14ed6e966d5456165b44c3d684dd"
[[ -d "$mirror" && "$(git --git-dir="$mirror" remote get-url origin)" == "$url" ]] || exit 1
if git --git-dir="$mirror" cat-file -e "$sha:pubspec.yaml" 2>/dev/null; then exit 1; fi
git --git-dir="$mirror" fetch --no-tags origin "$sha"
exec "$TOOLCHAIN/bin/flutter-tizen" pub get "$@"
