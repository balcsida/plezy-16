#!/usr/bin/env bash
# One release path for local builds and CI. Signing material is never an artifact.
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_toolchain
: "${TIZEN_SDK:?Set TIZEN_SDK}"
export FLUTTER_TIZEN_ROOT="$TOOLCHAIN"
export PATH="$TIZEN_SDK/tools/ide/bin:$TIZEN_SDK/tools:$PATH"
umask 077
work="$(mktemp -d "${TMPDIR:-/tmp}/plezy-tizen-build.XXXXXX")"
profile="${TIZEN_SECURITY_PROFILE:-}"
category=user-profile-unverified
created_profile=false
cleanup() {
	if $created_profile; then tizen security-profiles remove -n "$profile" >/dev/null 2>&1 || true; fi
	if [[ "${TIZEN_KEEP_SOURCE:-0}" == 1 && -d "$work/source" ]]; then
		rm -rf "$work/signing"
		printf 'Local diagnostic source retained (never upload): %s/source\n' "$work"
	else
		rm -rf "$work" # Only the private directory created by mktemp above.
	fi
}
trap cleanup EXIT
if [[ "${1:-}" == --test-signing && "${PLEZY_TEST_SIGNING_SESSION:-0}" != 1 ]]; then
	# A fresh bus and private keyring: never unlock or overwrite a user's keyring.
	export XDG_DATA_HOME="$work/keyring-data" XDG_RUNTIME_DIR="$work/runtime"
	mkdir -p "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR"
	dbus-run-session -- env PLEZY_TEST_SIGNING_SESSION=1 bash "$ROOT/scripts/tizen/build.sh" "$@"
	exit 0
fi
if [[ "${1:-}" == --test-signing ]]; then
	profile="plezy-ci-$(python3 -c 'import secrets; print(secrets.token_hex(8))')"
	password="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
	mkdir "$work/signing"
	if ! printf '%s' "$password" | gnome-keyring-daemon --unlock --components=secrets >/dev/null; then
		echo 'Private keyring could not start. Containers need IPC_LOCK; do not strip keyring file capabilities.' >&2
		exit 1
	fi
	if ! tizen certificate -a plezy-ci -f author -p "$password" -- "$work/signing" >/dev/null 2>&1; then
		echo 'Disposable author-certificate creation failed (sensitive CLI output discarded).' >&2
		exit 1
	fi
	if ! tizen security-profiles add -f -n "$profile" -a "$work/signing/author.p12" -p "$password" >/dev/null 2>&1; then
		echo 'Disposable signing-profile creation failed (sensitive CLI output discarded).' >&2
		exit 1
	fi
	created_profile=true
	unset password
	category=test-only
elif [[ $# -gt 0 || -z "$profile" ]]; then
	echo 'Usage: build.sh --test-signing OR TIZEN_SECURITY_PROFILE=existing-profile build.sh' >&2
	exit 2
fi
out="${TIZEN_OUTPUT_DIR:-$ROOT/build/tizen-release}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
revision="$(git -C "$ROOT" rev-parse HEAD)"
provenance=()
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=normal)" ]]; then provenance+=(--dirty); fi
# Hook configuration is build-local: never change desktop SQLite resolution or
# rewrite the caller's pubspec. The Tizen database uses sqflite, not SQLite FFI.
python3 - "$ROOT" "$work/source" <<'PY'
import hashlib, pathlib, shutil, sys
root, stage = map(pathlib.Path, sys.argv[1:])
stage.mkdir()
for name in ['pubspec.yaml', 'pubspec.lock', 'lib', 'assets', 'packages', 'tizen']:
    source, target = root / name, stage / name
    if source.is_dir():
        shutil.copytree(source, target, ignore=shutil.ignore_patterns('build', 'bin', 'obj', 'flutter', '.dart_tool', '*.p12', '*.pfx', '*.csproj.user', '.app.deps.json'))
    else:
        shutil.copy2(source, target)
with (stage / 'pubspec.yaml').open('a') as f:
    f.write('\nhooks:\n  user_defines:\n    sqlite3:\n      source: process\n')
digest = hashlib.sha256()
for path in sorted(stage.rglob('*')):
    if path.is_file():
        digest.update(path.relative_to(stage).as_posix().encode() + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
(stage.parent / 'source.sha256').write_text(digest.hexdigest())
PY
source_hash="$(<"$work/source.sha256")"
cd "$work/source"
"$ROOT/scripts/tizen/pub_get.sh" --enforce-lockfile
"$ROOT/scripts/tizen/flutter.sh" build tpk --release --device-profile tv --target-arch arm \
	--dart-define=TIZEN_BUILD=true --security-profile "$profile" --no-pub
packages=(build/tizen/tpk/*.tpk)
[[ ${#packages[@]} == 1 && -f "${packages[0]}" ]] || {
	echo 'Expected exactly one release TPK.' >&2
	exit 1
}
python3 "$ROOT/scripts/tizen/inspect_tpk.py" "${packages[0]}" --signing-category "$category" \
	--revision "$revision" --source-inputs-sha256 "$source_hash" "${provenance[@]}" --output "$work/inspection.json"
# Compilation and ELF headers alone cannot detect a stale managed registrant.
dotnet run --project "$ROOT/test/tizen_native/plugin_imports/PluginImportsTests.csproj" -- "${packages[0]}"
cp "$work/inspection.json" "$out/inspection.json"
cp "${packages[0]}" "$out/plezy-tizen-6-arm-release.tpk"
python3 - "$out" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1]); package = root / 'plezy-tizen-6-arm-release.tpk'
digest = hashlib.sha256(package.read_bytes()).hexdigest()
(root / 'SHA256SUMS').write_text(f'{digest}  {package.name}\n')
print(f'Release package inspected: {package.name} ({digest})')
PY
printf 'Signing category: %s (not proof of Samsung TV installation)\n' "$category"
