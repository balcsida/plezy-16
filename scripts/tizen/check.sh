#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_toolchain
cd "$ROOT"
export FLUTTER_TIZEN_ROOT="$TOOLCHAIN"
# The vendored plugin's dev dependencies are needed by upstream's analyzer.
(cd packages/wakelock_plus && "$ROOT/scripts/tizen/flutter.sh" pub get --enforce-lockfile --no-example)
python3 scripts/tizen/test_inspect.py
python3 scripts/tizen/test_toolchain_patch.py
find lib test scripts -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -print0 |
	xargs -0 scripts/tizen/dart.sh format --output=none --set-exit-if-changed
# This upstream check runs Platform.resolvedExecutable, i.e. the bundled Dart,
# and preserves its explicit one-diagnostic baseline rather than hiding warnings.
scripts/tizen/dart.sh run scripts/checks/check_analyzer.dart
scripts/codegen.sh --check
scripts/tizen/flutter.sh test --no-pub test/tizen test/focus test/database \
	test/services/jellyfin_playback_bundle_test.dart
scripts/tizen/flutter.sh test --no-pub --dart-define=TIZEN_BUILD=true test/tizen
