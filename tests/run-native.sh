#!/bin/sh
set -eu
case "$(uname -s)" in
    Darwin) ;;
    *) echo 'Native policy tests require macOS Foundation and clang.' >&2; exit 2 ;;
esac
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ib6-native.XXXXXX")
trap 'rm -f "$TEST_DIR/native_policy" "$TEST_DIR/native_proxy"; rmdir "$TEST_DIR"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -framework Foundation -framework CoreFoundation -I"$ROOT/src" \
    "$ROOT/src/IB6Policy.m" "$ROOT/tests/native_policy.m" \
    -o "$TEST_DIR/native_policy"
"$TEST_DIR/native_policy"
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -framework Foundation -framework CoreFoundation -framework Security -I"$ROOT/src" \
    "$ROOT/src/IB6Policy.m" "$ROOT/tests/native_proxy.m" \
    -o "$TEST_DIR/native_proxy"
"$TEST_DIR/native_proxy"
