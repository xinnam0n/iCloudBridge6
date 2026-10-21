import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("ib6_ci_version", Path(__file__).with_name("ci_version.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CIVersionTests(unittest.TestCase):
    def test_base_and_unique_run_attempt(self):
        control = "Package: local.legacyapple.icloudbridge6\nVersion: 0.1.0\n"
        self.assertEqual(MODULE.package_version(control, "10", "2"), "0.1.0+ci.10.2")
        self.assertNotEqual(MODULE.package_version(control, "10", "1"), MODULE.package_version(control, "10", "2"))
        self.assertNotEqual(MODULE.package_version(control, "10", "2"), MODULE.package_version(control, "11", "1"))

    def test_reject_missing_duplicate_and_invalid_base(self):
        for control in ("Package: test\n", "Version: 0.1\nVersion: 0.2\n", "Version: invalid\n", "Version: 0.1 value\n"):
            with self.subTest(control=control), self.assertRaises(ValueError):
                MODULE.package_version(control, "1", "1")

    def test_reject_invalid_workflow_metadata(self):
        for run, attempt in (("", "1"), ("0", "1"), ("1", "0"), ("01", "1"), ("1\nVersion: 2", "1")):
            with self.subTest(run=run, attempt=attempt), self.assertRaises(ValueError):
                MODULE.package_version("Version: 0.1.0\n", run, attempt)


if __name__ == "__main__":
    unittest.main()
