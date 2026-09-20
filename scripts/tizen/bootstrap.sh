#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
if [[ ! -d "$TOOLCHAIN/.git" ]]; then
	git clone https://github.com/flutter-tizen/flutter-tizen.git "$TOOLCHAIN"
	git -C "$TOOLCHAIN" checkout --detach "$(config flutter_tizen_sha)"
fi
require_toolchain --bootstrap
toolchain_patch apply
"$TOOLCHAIN/bin/flutter-tizen" --version
if [[ "${1:-}" != --sdk ]]; then exit 0; fi
[[ "$(uname -s)/$(uname -m)" == Linux/x86_64 ]] || {
	echo 'Automated SDK setup requires Linux x86_64; see docs/tizen/BUILD.md for macOS.' >&2
	exit 1
}
: "${TIZEN_SDK:?Set TIZEN_SDK to the desired SDK directory (outside the source tree).}"
if [[ ! -x "$TIZEN_SDK/tools/ide/bin/tizen" ]]; then
	installer="$(mktemp)"
	trap 'rm -f "$installer"' EXIT
	curl --fail --location --retry 3 "$(config sdk_url)" -o "$installer"
	python3 - "$installer" "$(config sdk_sha256)" <<'PY'
import hashlib,sys
with open(sys.argv[1], 'rb') as f:
    actual=hashlib.file_digest(f, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(f.read()).hexdigest()
if actual != sys.argv[2]:
    raise SystemExit('Tizen SDK installer SHA-256 mismatch')
PY
	chmod 700 "$installer"
	"$installer" --accept-license "$TIZEN_SDK"
fi
packages=()
while IFS= read -r package; do packages+=("$package"); done < <(config sdk_packages)
"$TIZEN_SDK/package-manager/package-manager-cli.bin" install --accept-license "${packages[@]}"
"$TOOLCHAIN/bin/flutter-tizen" doctor -v
