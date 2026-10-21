#!/usr/bin/env python3
"""Verify legacy SDK metadata and real armv7 dylib exports before building."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import zipfile

LIBRARIES = {
    "usr/lib/libobjc.A.dylib": {"_objc_msgSend_stret"},
    "usr/lib/libSystem.B.dylib": set(),
    "usr/lib/system/libunwind.dylib": {"__Unwind_SjLj_Register", "__Unwind_SjLj_Resume", "__Unwind_SjLj_Unregister"},
    "usr/lib/system/libcompiler_rt.dylib": {"___udivdi3"},
    "System/Library/Frameworks/Foundation.framework/Foundation": set(),
    "System/Library/Frameworks/CoreFoundation.framework/CoreFoundation": set(),
    "System/Library/Frameworks/Security.framework/Security": set(),
}


def armv7_slice(data):
    if data[:4] == b"\xca\xfe\xba\xbe":
        count = struct.unpack_from(">I", data, 4)[0]
        if not 1 <= count <= 32 or 8 + count * 20 > len(data):
            raise ValueError("invalid fat SDK library")
        matches = []
        for index in range(count):
            cpu, subtype, start, length, _ = struct.unpack_from(">5I", data, 8 + index * 20)
            if cpu == 12 and subtype & 0xFFFFFF == 9:
                if length < 28 or start + length > len(data):
                    raise ValueError("invalid armv7 slice bounds")
                matches.append(data[start:start + length])
        if len(matches) != 1:
            raise ValueError("SDK library needs exactly one armv7 slice")
        data = matches[0]
    if len(data) < 28:
        raise ValueError("truncated SDK dylib")
    magic, cpu, subtype, filetype, count, size, _ = struct.unpack_from("<7I", data)
    if (magic, cpu, subtype & 0xFFFFFF, filetype) != (0xFEEDFACE, 12, 9, 6):
        raise ValueError("SDK library is not an armv7 MH_DYLIB")
    if 28 + size > len(data) or count > 4096:
        raise ValueError("invalid SDK dylib load commands")
    return data


def exported_symbols(data):
    data = armv7_slice(data)
    count, size = struct.unpack_from("<2I", data, 16)
    offset, end, symbols = 28, 28 + size, set()
    for _ in range(count):
        command, length = struct.unpack_from("<2I", data, offset)
        if length < 8 or offset + length > end:
            raise ValueError("invalid SDK load command size")
        if command == 2:  # LC_SYMTAB
            if length != 24:
                raise ValueError("invalid SDK symbol command")
            symoff, nsyms, stroff, strsize = struct.unpack_from("<4I", data, offset + 8)
            if symoff + nsyms * 12 > len(data) or stroff + strsize > len(data):
                raise ValueError("invalid SDK symbol table bounds")
            strings = data[stroff:stroff + strsize]
            for index in range(nsyms):
                strx, kind, _, _, _ = struct.unpack_from("<IBBHI", data, symoff + index * 12)
                if kind & 1 and kind & 0x0E in (0x0E, 0x02):
                    if strx >= len(strings):
                        raise ValueError("invalid SDK symbol name")
                    symbols.add(strings[strx:].split(b"\0", 1)[0].decode("ascii"))
        offset += length
    if offset != end:
        raise ValueError("incomplete SDK load commands")
    return symbols


def inspect(read):
    metadata = plistlib.loads(read("SDKSettings.plist"))
    if metadata.get("Version") != "6.1" or metadata.get("CanonicalName") != "iphoneos6.1":
        raise ValueError("expected SDK 6.1 / iphoneos6.1 metadata")
    report = {"version": "6.1", "canonical_name": "iphoneos6.1", "architecture": "armv7", "libraries": {}}
    for path, required in LIBRARIES.items():
        data = read(path)
        missing = required - exported_symbols(data)
        if missing:
            raise ValueError(f"{path} missing armv7 exports: {sorted(missing)}")
        report["libraries"][path] = {"sha256": hashlib.sha256(data).hexdigest(), "required_exports": sorted(required)}
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="iPhoneOS6.1.sdk directory or original SDK zip")
    args = parser.parse_args()
    try:
        if args.source.is_file():
            with zipfile.ZipFile(args.source) as archive:
                report = inspect(lambda path: archive.read("iPhoneOS6.1.sdk/" + path))
        else:
            report = inspect(lambda path: (args.source / path).read_bytes())
    except (ValueError, KeyError, OSError, struct.error, zipfile.BadZipFile) as error:
        parser.error(str(error))
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
