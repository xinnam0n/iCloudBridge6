import importlib.util
from pathlib import Path
import plistlib
import struct
import unittest

SPEC = importlib.util.spec_from_file_location("ib6_sdk", Path(__file__).with_name("validate_sdk.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def library(names, cpu=12):
    strings = b"\0"
    entries = b""
    for name in names:
        entries += struct.pack("<IBBHI", len(strings), 0x0F, 1, 0, 0x1000)
        strings += name.encode() + b"\0"
    symoff = 52
    commands = struct.pack("<6I", 2, 24, symoff, len(names), symoff + len(entries), len(strings))
    return struct.pack("<7I", 0xFEEDFACE, cpu, 9, 6, 1, 24, 0) + commands + entries + strings


class SDKGateTests(unittest.TestCase):
    def test_required_legacy_exports_are_checked(self):
        required = set().union(*MODULE.LIBRARIES.values())
        data = library(sorted(required))
        mapping = {path: data for path in MODULE.LIBRARIES}
        mapping["SDKSettings.plist"] = plistlib.dumps({"Version": "6.1", "CanonicalName": "iphoneos6.1"})
        self.assertEqual(MODULE.inspect(mapping.__getitem__)["version"], "6.1")
        mapping["usr/lib/libobjc.A.dylib"] = library([])
        with self.assertRaisesRegex(ValueError, "missing armv7 exports"):
            MODULE.inspect(mapping.__getitem__)

    def test_reject_wrong_architecture_and_sdk(self):
        with self.assertRaises(ValueError):
            MODULE.exported_symbols(library([], cpu=0x100000C))
        with self.assertRaisesRegex(ValueError, "expected SDK 6.1"):
            MODULE.inspect(lambda _: plistlib.dumps({"Version": "10.3", "CanonicalName": "iphoneos10.3"}))

    def test_truncated_fat_library_is_rejected(self):
        with self.assertRaises(ValueError):
            MODULE.armv7_slice(b"\xca\xfe\xba\xbe" + struct.pack(">I", 1))


if __name__ == "__main__":
    unittest.main()
