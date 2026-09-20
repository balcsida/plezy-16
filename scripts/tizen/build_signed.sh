#!/usr/bin/env bash
# Release build with a preserved author certificate, so an installed app can be
# upgraded in place. The caller supplies the key; it is never read from the
# repository, never written into it, and never becomes a build artifact.
set -euo pipefail
source "$(dirname "$0")/common.sh"
: "${TIZEN_AUTHOR_P12:?Set TIZEN_AUTHOR_P12 to the preserved author certificate}"
: "${TIZEN_AUTHOR_PASSWORD_FILE:?Set TIZEN_AUTHOR_PASSWORD_FILE to its password file}"
[[ -r "$TIZEN_AUTHOR_P12" && -r "$TIZEN_AUTHOR_PASSWORD_FILE" ]] || {
	echo 'Author certificate or password file is unreadable.' >&2
	exit 1
}
umask 077
if [[ "${PLEZY_SIGNED_SESSION:-0}" != 1 ]]; then
	# A private bus and keyring: never unlock or overwrite the caller's keyring.
	session="$(mktemp -d "${TMPDIR:-/tmp}/plezy-tizen-signed.XXXXXX")"
	trap 'rm -rf "$session"' EXIT
	export XDG_DATA_HOME="$session/keyring-data" XDG_RUNTIME_DIR="$session/runtime"
	mkdir -p "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR"
	dbus-run-session -- env PLEZY_SIGNED_SESSION=1 bash "$ROOT/scripts/tizen/build_signed.sh" "$@"
	exit 0
fi
export PATH="${TIZEN_SDK:?Set TIZEN_SDK}/tools/ide/bin:$TIZEN_SDK/tools:$PATH"
profile="${TIZEN_SECURITY_PROFILE:-plezy-preserved-author}"
created=false
cleanup() {
	# The profile references the caller's key; never leave it registered.
	if $created; then tizen security-profiles remove -n "$profile" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
password="$(cat "$TIZEN_AUTHOR_PASSWORD_FILE")"
if ! printf '%s' "$password" | gnome-keyring-daemon --unlock --components=secrets >/dev/null; then
	echo 'Private keyring could not start. Containers need IPC_LOCK; do not strip keyring file capabilities.' >&2
	exit 1
fi
# Sensitive CLI output is discarded, never logged.
if ! tizen security-profiles add -f -n "$profile" -a "$TIZEN_AUTHOR_P12" -p "$password" >/dev/null 2>&1; then
	echo 'Preserved-author profile registration failed (sensitive output discarded).' >&2
	exit 1
fi
created=true
unset password
TIZEN_SECURITY_PROFILE="$profile" exec "$ROOT/scripts/tizen/build.sh"
