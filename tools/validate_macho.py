#!/usr/bin/env python3
"""Reject incompatible release binaries and emit a credential-free report.

This checks file metadata and linked libraries, not successful device execution
or availability of every Objective-C selector on iOS 6.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct


ALLOWED_LIBRARIES = {
    "/System/Library/Frameworks/Foundation.framework/Foundation",
    "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
    "/System/Library/Frameworks/Security.framework/Security",
    "/usr/lib/libobjc.A.dylib",
    "/usr/lib/libSystem.B.dylib",
    "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
    "/usr/lib/libsubstrate.dylib",
}


def inspect(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 28:
        raise ValueError("truncated Mach-O header")
    magic, cpu, subtype, filetype, count, commands_size, _ = struct.unpack_from("<7I", data)
    if (magic, cpu, subtype & 0x00FFFFFF, filetype) != (0xFEEDFACE, 12, 9, 6):
        raise ValueError("release must be a thin 32-bit armv7 MH_DYLIB")
    end = 28 + commands_size
    if end > len(data) or count > 4096:
        raise ValueError("invalid load command bounds")
    offset = 28
    versions = []
    libraries = []
    has_signature = False
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError("truncated load command")
        command, size = struct.unpack_from("<2I", data, offset)
        if size < 8 or size % 4 or offset + size > end:
            raise ValueError("invalid load command size")
        if command == 0x25:  # LC_VERSION_MIN_IPHONEOS
            if size != 16:
                raise ValueError("invalid iPhoneOS version command")
            version, sdk = struct.unpack_from("<2I", data, offset + 8)
            versions.append((version, sdk))
        elif command in (0x24, 0x2F, 0x30, 0x32):
            raise ValueError("unexpected platform or modern LC_BUILD_VERSION")
        elif command in (0xC, 0x80000018, 0x8000001F, 0x80000023, 0x20):
            if size < 24:
                raise ValueError("truncated dylib command")
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            if not 24 <= name_offset < size:
                raise ValueError("invalid dylib name offset")
            name = data[offset + name_offset:offset + size].split(b"\0", 1)[0].decode("ascii")
            if name not in ALLOWED_LIBRARIES:
                raise ValueError(f"unapproved linked library: {name}")
            libraries.append(name)
        elif command == 0x1D:  # LC_CODE_SIGNATURE
            if size != 16:
                raise ValueError("invalid signature load command")
            start, length = struct.unpack_from("<2I", data, offset + 8)
            if length < 12 or start + length > len(data):
                raise ValueError("missing signature bytes")
            if data[start:start + 4] != b"\xfa\xde\x0c\xc0":
                raise ValueError("missing embedded signature superblob")
            has_signature = True
        offset += size
    if offset != end or len(versions) != 1:
        raise ValueError("exactly one complete iPhoneOS minimum-version command required")
    minimum, sdk = versions[0]
    if minimum != 0x00060000 or sdk != 0x00060100:
        raise ValueError("release must target iOS 6.0 using declared SDK 6.1")
    if not has_signature:
        raise ValueError("unsigned tweak")
    if not any("substrate" in name.lower() for name in libraries):
        raise ValueError("missing Substrate linkage")
    return {
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
        "architecture": "armv7",
        "minimum_os": "6.0",
        "sdk": "6.1",
        "embedded_signature_present": True,
        "linked_libraries": libraries,
        "device_tested": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = inspect(args.binary)
    except (ValueError, UnicodeError, struct.error) as error:
        parser.error(str(error))
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        with args.output.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
    print(text, end="")


if __name__ == "__main__":
    main()
