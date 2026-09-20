#!/usr/bin/env bash
# Bootstrap a host for flutter-tizen development.
# Companion to ../SKILL.md.

set -u

FLUTTER_TIZEN_HOME="${FLUTTER_TIZEN_HOME:-$HOME/flutter-tizen}"
TIZEN_SDK_TOOLS="${TIZEN_SDK_TOOLS:-$HOME/tizen-studio/tools}"

step() { printf '\n==> %s\n' "$*"; }
fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

step "1. PATH check"
export PATH="$FLUTTER_TIZEN_HOME/bin:$TIZEN_SDK_TOOLS:$PATH"
command -v flutter-tizen >/dev/null || fail "flutter-tizen not on PATH ($FLUTTER_TIZEN_HOME/bin missing?)"
command -v sdb >/dev/null || fail "sdb not on PATH ($TIZEN_SDK_TOOLS missing?)"
command -v tizen >/dev/null || fail "tizen CLI not on PATH ($TIZEN_SDK_TOOLS missing?)"

step "2. Tool versions"
flutter-tizen --version | head -3
sdb version
tizen version

step "3. doctor"
flutter-tizen doctor -v | tee /tmp/flutter-tizen-doctor.log
grep -q 'No issues found' /tmp/flutter-tizen-doctor.log ||
	echo "  (resolve red items above before continuing)"

step "4. Certificate profile"
if tizen security-profiles list 2>/dev/null | grep -q 'Profile name'; then
	tizen security-profiles list
else
	fail "no security profile registered — run 'tizen certificate' or Certificate Manager"
fi

step "5. Smoke build (debug, common profile)"
WORK="$(mktemp -d)"
pushd "$WORK" >/dev/null
flutter-tizen create demo
cd demo
flutter-tizen build tpk --debug --device-profile common --target-arch x86 ||
	fail "smoke build failed — inspect the log above"
ls build/tizen/tpk/
popd >/dev/null

step "Setup complete."
