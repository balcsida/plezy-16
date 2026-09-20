#!/usr/bin/env bash
# Sample TPK builds across documented targets.
# Companion to ../SKILL.md.

set -eu

# 1) TV emulator (Tizen TV 9.0 x86, debug, JIT-only)
flutter-tizen build tpk \
	--device-profile tv \
	--target-arch x86 \
	--debug

# 2) Samsung TV 2022 (real device, arm32, release, signed + obfuscated)
flutter-tizen build tpk \
	--device-profile tv \
	--target-arch arm \
	--release \
	--security-profile tv-store \
	--obfuscate --split-debug-info=build/symbols

# 3) Raspberry Pi 4 with 64-bit Tizen image (common profile)
flutter-tizen build tpk \
	--device-profile common \
	--target-arch arm64 \
	--release

# Inspect the most recent TPK
LATEST="$(ls -t build/tizen/tpk/*.tpk | head -1)"
echo "Artifact: $LATEST"
unzip -p "$LATEST" tizen-manifest.xml | grep -E 'profile|api-version|appid'
unzip -l "$LATEST" | grep -E 'signature|manifest'
