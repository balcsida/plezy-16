#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export FLUTTER_TIZEN_ROOT="${FLUTTER_TIZEN_ROOT:-$PWD/.toolchains/flutter-tizen}"

if [[ "${1:-}" == "--check" ]]; then
	shift
	exec python3 scripts/checks/check_codegen.py "$@"
fi

scripts/tizen/dart.sh run scripts/codegen/generate_ducet_ranks.dart
scripts/tizen/dart.sh run scripts/codegen/generate_hid_key_labels.dart
scripts/tizen/dart.sh run scripts/codegen/generate_iso_639_data.dart
python3 scripts/codegen/generate_relay_protocol.py
scripts/tizen/dart.sh run slang
scripts/tizen/dart.sh run build_runner build "$@"
