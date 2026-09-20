#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_toolchain
exec "$TOOLCHAIN/flutter/bin/cache/dart-sdk/bin/dart" "$@"
