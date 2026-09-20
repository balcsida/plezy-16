#!/usr/bin/env bash
# Sourced by the Tizen scripts; never adds an unrelated Dart/Flutter to PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLCHAIN="${FLUTTER_TIZEN_ROOT:-$ROOT/.toolchains/flutter-tizen}"
config() {
	python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print("\n".join(v) if isinstance(v,list) else v)' "$ROOT/tizen/toolchain.json" "$1"
}
# Backport the bundled Flutter host-test native-assets wiring. Never change the
# pinned SDK revision, overwrite conflicting edits, or reuse a stale snapshot.
toolchain_patch() {
	local patch="$ROOT/scripts/tizen/patches/host-test-native-assets.patch"
	python3 - "$patch" "$(config flutter_tizen_host_tests_patch_sha256)" <<'PY'
import hashlib, pathlib, sys
if hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest() != sys.argv[2]:
    raise SystemExit('Flutter-Tizen compatibility patch SHA-256 mismatch')
PY
	if git -C "$TOOLCHAIN" apply --reverse --check "$patch" >/dev/null 2>&1; then return 0; fi
	if [[ "${1:-check}" != apply ]]; then
		echo 'Run scripts/tizen/bootstrap.sh to apply the pinned host-test compatibility patch.' >&2
		return 1
	fi
	git -C "$TOOLCHAIN" apply --check "$patch"
	git -C "$TOOLCHAIN" apply "$patch"
	rm -f "$TOOLCHAIN/bin/cache/flutter-tizen.snapshot"
}
require_toolchain() {
	[[ -x "$TOOLCHAIN/bin/flutter-tizen" ]] || {
		echo 'Run scripts/tizen/bootstrap.sh first.' >&2
		exit 1
	}
	[[ "$(git -C "$TOOLCHAIN" rev-parse HEAD)" == "$(config flutter_tizen_sha)" ]] || {
		echo 'Flutter-Tizen revision differs from tizen/toolchain.json.' >&2
		exit 1
	}
	if [[ "${1:-}" != --bootstrap ]]; then toolchain_patch; fi
}
