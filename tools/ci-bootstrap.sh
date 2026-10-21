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
SDK_SHA256=2696df17fc48e1b6ea3f7acd346b5f2356fb5c6cc60b0f3aaca0c24522d761de
SDK_URL=https://github.com/growtopiajaw/iPhoneOS-SDK/releases/download/v1.0/iPhoneOS6.1.sdk.zip
TOOLCHAIN_SHA256=0e4e21888517d0cd8c96d1e297dd17125546a0366410a33b811910083cabe110
TOOLCHAIN_URL=https://github.com/sbingner/llvm-project/releases/download/v10.0.0-2/linux-ios-arm64e-clang-toolchain.tar.lzma

git clone --filter=blob:none --no-checkout https://github.com/theos/theos.git "$THEOS"
git -C "$THEOS" checkout --detach "$THEOS_COMMIT"
git -C "$THEOS" submodule update --init --recursive --depth 1
test "$(git -C "$THEOS" rev-parse HEAD)" = "$THEOS_COMMIT"

DOWNLOAD_DIR=$(mktemp -d)
trap 'rm -f "$DOWNLOAD_DIR/toolchain.tar.lzma" "$DOWNLOAD_DIR/sdk.zip"; rmdir "$DOWNLOAD_DIR"' EXIT
curl --fail --location --retry 3 "$TOOLCHAIN_URL" -o "$DOWNLOAD_DIR/toolchain.tar.lzma"
printf '%s  %s\n' "$TOOLCHAIN_SHA256" "$DOWNLOAD_DIR/toolchain.tar.lzma" | sha256sum --check --strict
mkdir -p "$THEOS/toolchain/linux/iphone"
tar --lzma -xf "$DOWNLOAD_DIR/toolchain.tar.lzma" --strip-components=1 -C "$THEOS/toolchain/linux/iphone"

# The community mirror supplies actual legacy SDK armv7 dylibs. Verify the
# archive bytes before extraction; validate metadata and required exports.
# No SDK-provided executable is run or placed on PATH.
curl --fail --location --retry 3 "$SDK_URL" -o "$DOWNLOAD_DIR/sdk.zip"
printf '%s  %s\n' "$SDK_SHA256" "$DOWNLOAD_DIR/sdk.zip" | sha256sum --check --strict
mkdir -p "$THEOS/sdks"
unzip -q "$DOWNLOAD_DIR/sdk.zip" -d "$THEOS/sdks"
python3 tools/validate_sdk.py "$THEOS/sdks/iPhoneOS6.1.sdk" > "$THEOS/ib6-sdk-report.json"
cat "$THEOS/ib6-sdk-report.json"
# clang 10 reads Version only from SDKSettings.json when emitting its
# -platform_version linker arguments. Derive that build-only metadata from
# the validated legacy plist, without modifying any SDK library or header.
python3 - "$THEOS/sdks/iPhoneOS6.1.sdk" <<'PY'
import json
from pathlib import Path
import plistlib
import sys
root = Path(sys.argv[1])
metadata = plistlib.loads((root / "SDKSettings.plist").read_bytes())
assert metadata["Version"] == "6.1" and metadata["CanonicalName"] == "iphoneos6.1"
with (root / "SDKSettings.json").open("x", encoding="utf-8") as stream:
    json.dump({"Version": metadata["Version"]}, stream)
    stream.write("\n")
PY
cat "$THEOS/sdks/iPhoneOS6.1.sdk/SDKSettings.json"

"$THEOS/toolchain/linux/iphone/bin/clang" --version
test -f "$THEOS/sdks/iPhoneOS6.1.sdk/System/Library/Frameworks/Foundation.framework/Headers/Foundation.h"
printf 'Theos=%s\nSDKAssetID=29205306\nSDKSHA256=%s\nToolchainSHA256=%s\n' "$THEOS_COMMIT" "$SDK_SHA256" "$TOOLCHAIN_SHA256"
