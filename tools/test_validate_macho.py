"""Release-gate regressions using metadata fixtures, never published dylibs."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("ib6_macho", Path(__file__).with_name("validate_macho.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def fixture(*, minimum=0x60000, sdk=0x60100, cpu=12, subtype=9,
            library="/usr/lib/libsubstrate.dylib", signed=True, extra=b""):
    name = library.encode("ascii") + b"\0"
    size = (24 + len(name) + 3) & ~3
    dylib = struct.pack("<6I", 0xC, size, 24, 0, 0, 0) + name
    dylib += bytes(size - len(dylib))
    commands = struct.pack("<4I", 0x25, 16, minimum, sdk) + dylib + extra
    count = 2 + bool(extra)
    signature = b"\xfa\xde\x0c\xc0" + struct.pack(">2I", 12, 0)
    if signed:
        commands += struct.pack("<4I", 0x1D, 16, 28 + len(commands) + 16, len(signature))
        count += 1
    header = struct.pack("<7I", 0xFEEDFACE, cpu, subtype, 6, count, len(commands), 0)
    return header + commands + (signature if signed else b"")


class ReleaseGateTests(unittest.TestCase):
    def inspect(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "metadata-only.dylib"
            path.write_bytes(data)
            return MODULE.inspect(path)

    def test_declared_legacy_target(self):
        report = self.inspect(fixture())
        self.assertEqual(report["minimum_os"], "6.0")
        self.assertEqual(report["sdk"], "6.1")
        self.assertFalse(report["device_tested"])

    def test_reject_wrong_architecture_and_deployment(self):
        for changes in ({"cpu": 0x100000C}, {"subtype": 11}, {"minimum": 0x70000}, {"sdk": 0x90300}, {"sdk": 0xA0300}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.inspect(fixture(**changes))

    def test_reject_unknown_dependency_and_unsigned(self):
        for changes in ({"library": "@rpath/Unknown.dylib"}, {"signed": False}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.inspect(fixture(**changes))

    def test_reject_modern_platform_and_truncation(self):
        for data in (fixture(extra=struct.pack("<2I", 0x32, 8)), fixture()[:-1], b"short"):
            with self.subTest(length=len(data)), self.assertRaises(ValueError):
                self.inspect(data)


if __name__ == "__main__":
    unittest.main()
