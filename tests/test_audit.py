import importlib.util
import json
import plistlib
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("audit", Path(__file__).parents[1] / "tools/audit.py")
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class AuditTests(unittest.TestCase):
    def gsa(self, hsc=200, ec=0, **extra):
        response = {"Status": {"hsc": hsc, "ec": ec}, "M2": b"SECRET_PROOF",
                    "spd": b"SECRET_PAYLOAD", "np": b"SECRET_NP"}
        response.update(extra)
        return plistlib.dumps({"Response": response})

    def test_success_has_both_status_and_complete_shape(self):
        self.assertTrue(audit.analyze_gsa(self.gsa())["server_reported_complete_success"])
        self.assertFalse(audit.analyze_gsa(self.gsa(401, -22406))["server_reported_complete_success"])
        self.assertFalse(audit.analyze_gsa(self.gsa(M2=b""))["server_reported_complete_success"])

    def test_init_is_not_complete(self):
        data = plistlib.dumps({"Response": {"Status": {"hsc": 200, "ec": 0},
                              "s": b"s", "B": b"b", "i": 1, "sp": "s2k", "c": "secret"}})
        report = audit.analyze_gsa(data)
        self.assertTrue(report["init_shape"])
        self.assertFalse(report["server_reported_complete_success"])

    def test_never_merge_success_and_failure_responses(self):
        good, bad = audit.analyze_gsa(self.gsa()), audit.analyze_gsa(self.gsa(401, -22406))
        self.assertTrue(good["server_reported_complete_success"])
        self.assertEqual(bad["ec"], -22406)
        self.assertFalse(bad["server_reported_complete_success"])

    def test_bool_and_strings_are_not_status_codes(self):
        for value in (False, True, "0", "200", 200.0):
            self.assertFalse(audit.analyze_gsa(self.gsa(hsc=value))["server_reported_complete_success"])

    def test_secrets_in_values_and_keys_never_echo(self):
        data = plistlib.dumps({"status": 0, "delegates": {"com.apple.mobileme": {
            "status": 0, "tokens": {"SECRET_KEY": "SECRET_TOKEN"},
            "dsid": "SECRET_DSID"}}})
        rendered = json.dumps(audit.analyze_delegates(data)) + json.dumps(audit.analyze_gsa(self.gsa()))
        self.assertNotIn("SECRET", rendered)

    def test_syslog_only_reports_fixed_categories_and_line_numbers(self):
        data = ("SECRET_USER required dataclasses for syncing\n"
                "CalDAV SECRET_ACCOUNT error -25300\nCan't find store with id SECRET_ID\n"
                "backupd accountID=(null)\n"
                "IB6 session=1234abcd seq=1 tx=0 event=keychain_copy item=generic osstatus=-25300\n"
                "IB6 session=1234abcd seq=2 tx=0 event=SECRET_TOKEN password=SECRET\n").encode()
        report = audit.analyze_syslog(data)
        self.assertEqual(report["symptoms"]["required_dataclasses"]["lines_first_50"], [1])
        self.assertEqual(report["bridge_keychain_status_counts"], {"-25300": 1})
        self.assertEqual(report["bridge_session_count"], 1)
        self.assertNotIn("SECRET", json.dumps(report))

    def test_gsa_header_capture_supported(self):
        self.assertTrue(audit.analyze_gsa(b"HTTP/1.1 200 OK\r\n\r\n" + self.gsa())["complete_shape"])

    def test_parse_failure_does_not_echo_input_or_overwrite(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as tmp:
            source, output = Path(tmp) / "secret-name.log", Path(tmp) / "out.json"
            source.write_bytes(b"SECRET_INVALID_XML")
            self.assertEqual(audit.main(["--gsa-plist", str(source), "--output", str(output)]), 1)
            self.assertNotIn("SECRET", output.read_text())
            with self.assertRaises(FileExistsError):
                audit.main(["--gsa-plist", str(source), "--output", str(output)])
            self.assertEqual(source.read_bytes(), b"SECRET_INVALID_XML")


if __name__ == "__main__":
    unittest.main()
