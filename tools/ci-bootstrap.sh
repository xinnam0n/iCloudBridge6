#!/usr/bin/env bash
# Linux x86_64 only. External repositories and archives are pinned below.
set -euo pipefail

: "${THEOS:?Set THEOS to a new build-only directory}"
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    echo 'The pinned cross toolchain requires Linux x86_64.' >&2
    exit 2
fi
if [[ -e "$THEOS" ]]; then
    echo 'Refusing to replace an existing THEOS directory.' >&2
    exit 2
fi

THEOS_COMMIT=304e0799973e8145f32e4ca2de6c747a84b758ce
SDK_COMMIT=0222fd5413cf4b9af096f37b4621afa2688572f7
TOOLCHAIN_SHA256=0e4e21888517d0cd8c96d1e297dd17125546a0366410a33b811910083cabe110
TOOLCHAIN_URL=https://github.com/sbingner/llvm-project/releases/download/v10.0.0-2/linux-ios-arm64e-clang-toolchain.tar.lzma

git clone --filter=blob:none --no-checkout https://github.com/theos/theos.git "$THEOS"
git -C "$THEOS" checkout --detach "$THEOS_COMMIT"
git -C "$THEOS" submodule update --init --recursive --depth 1
test "$(git -C "$THEOS" rev-parse HEAD)" = "$THEOS_COMMIT"

DOWNLOAD_DIR=$(mktemp -d)
trap 'rm -f "$DOWNLOAD_DIR/toolchain.tar.lzma"; rmdir "$DOWNLOAD_DIR"' EXIT
curl --fail --location --retry 3 "$TOOLCHAIN_URL" -o "$DOWNLOAD_DIR/toolchain.tar.lzma"
printf '%s  %s\n' "$TOOLCHAIN_SHA256" "$DOWNLOAD_DIR/toolchain.tar.lzma" | sha256sum --check --strict
mkdir -p "$THEOS/toolchain/linux/iphone"
tar --lzma -xf "$DOWNLOAD_DIR/toolchain.tar.lzma" --strip-components=1 -C "$THEOS/toolchain/linux/iphone"

# The official SDK repository has 10.3, not 6.1. The build explicitly keeps
# deployment at 6.0 and validates the resulting Mach-O; it does not claim a
# native SDK 6.1 build or substitute for execution on iOS 6.1.3.
SDK_CHECKOUT="${THEOS}-sdks"
if [[ -e "$SDK_CHECKOUT" ]]; then
    echo 'Refusing to replace an existing SDK checkout.' >&2
    exit 2
fi
git clone --filter=blob:none --sparse --no-checkout https://github.com/theos/sdks.git "$SDK_CHECKOUT"
git -C "$SDK_CHECKOUT" sparse-checkout set iPhoneOS10.3.sdk
git -C "$SDK_CHECKOUT" checkout --detach "$SDK_COMMIT"
test "$(git -C "$SDK_CHECKOUT" rev-parse HEAD)" = "$SDK_COMMIT"
mkdir -p "$THEOS/sdks"
ln -s "$SDK_CHECKOUT/iPhoneOS10.3.sdk" "$THEOS/sdks/iPhoneOS10.3.sdk"

"$THEOS/toolchain/linux/iphone/bin/clang" --version
test -f "$THEOS/sdks/iPhoneOS10.3.sdk/System/Library/Frameworks/Foundation.framework/Headers/Foundation.h"
test -f "$THEOS/sdks/iPhoneOS10.3.sdk/usr/lib/system/liblaunch.tbd"
printf 'Theos=%s\nSDK=%s\nToolchainSHA256=%s\n' "$THEOS_COMMIT" "$SDK_COMMIT" "$TOOLCHAIN_SHA256"
