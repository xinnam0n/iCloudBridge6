"""Synthetic format fixtures live only in temporary directories, never repo/pool."""
import bz2
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import struct
import tarfile
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("cydia_repo", Path(__file__).resolve().parents[1] / "tools/cydia_repo.py")
repo = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(repo)
BASE = "https://example.github.io/iCloudBridge6/"
SOURCE = "https://github.com/example/iCloudBridge6"


def macho(minimum=0x00060000, cpu=12, subtype=9, kind=6, signed=False):
    """Not a loadable tweak: just the structural fields this validator reads."""
    count = 2 + int(signed)
    command_size = 56 + 16 + (16 if signed else 0)
    header = struct.pack("<7I", 0xFEEDFACE, cpu, subtype, kind, count, command_size, 0)
    total = 28 + command_size + 8
    segment = struct.pack("<2I16s8I", 1, 56, b"__TEXT", 0, total, 0, total, 7, 5, 0, 0)
    version = struct.pack("<4I", 0x25, 16, minimum, 0x00060100)
    signature = struct.pack("<4I", 0x1D, 16, total - 8, 8) if signed else b""
    return header + segment + version + signature + b"FIXTURE!"


def tar_gz(files):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name, payload in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(payload)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(payload))
    return repo.deterministic_gzip(buffer.getvalue())


def ar(files):
    result = b"!<arch>\n"
    for name, payload in files:
        header = (name + "/").ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6)
        header += "100644".ljust(8) + str(len(payload)).ljust(10) + "`\n"
        result += header.encode("ascii") + payload + (b"\n" if len(payload) % 2 else b"")
    return result


def fixture(version="0.1.0", library=None, filters=None, fields=None, control_extra=None, data_extra=None):
    control = {"Package": repo.PACKAGE, "Version": version, "Architecture": repo.ARCHITECTURE,
               "Name": "iCloudBridge6", "Description": "Synthetic test fixture\n For offline testing only.",
               "Maintainer": "Unit Tests", "Depends": "mobilesubstrate, firmware (>= 6.0), firmware (<< 7.0)"}
    control.update(fields or {})
    control_payload = ("\n".join(key + ": " + value for key, value in control.items()) + "\n").encode()
    control_files = {"./control": control_payload, **(control_extra or {})}
    if filters is None:
        filters = {"Filter": {"Executables": sorted(repo.EXECUTABLES)}}
    data = {"./" + repo.LIBRARY: macho() if library is None else library,
            "./" + repo.FILTER: plistlib.dumps(filters), **(data_extra or {})}
    return ar([("debian-binary", b"2.0\n"), ("control.tar.gz", tar_gz(control_files)),
               ("data.tar.gz", tar_gz(data))])


class RepositoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.deb = self.folder / "input.deb"
        self.output = self.folder / "site"

    def generate(self, content=None):
        self.deb.write_bytes(fixture() if content is None else content)
        return repo.generate(self.deb, self.output, BASE, SOURCE)

    def test_generates_consistent_flat_repo_and_preserves_deb_signature_bytes(self):
        original = fixture(library=macho(signed=True))
        result = self.generate(original)
        package_name = repo.PACKAGE + "_0.1.0_iphoneos-arm.deb"
        self.assertEqual((self.output / "pool" / package_name).read_bytes(), original)
        packages = (self.output / "Packages").read_bytes()
        self.assertEqual(gzip.decompress((self.output / "Packages.gz").read_bytes()), packages)
        self.assertEqual(bz2.decompress((self.output / "Packages.bz2").read_bytes()), packages)
        self.assertIn("Name: iCloudBridge6\n", packages.decode())
        self.assertIn("Description: Synthetic test fixture\n For offline testing only.\n", packages.decode())
        self.assertIn("Filename: pool/" + package_name, packages.decode())
        self.assertIn("SHA256: " + hashlib.sha256(original).hexdigest(), packages.decode())
        self.assertEqual(result["packages"], 1)
        self.assertTrue((self.output / ".nojekyll").is_file())
        self.assertFalse((self.output / "Release.gpg").exists())
        self.assertFalse((self.output / "InRelease").exists())
        manifest = json.loads((self.output / "repository.json").read_text())
        self.assertFalse(manifest["signed"])
        self.assertEqual(manifest["packages"][0]["filename"], "pool/" + package_name)
        self.assertEqual(manifest["packages"][0]["sha256"], hashlib.sha256(original).hexdigest())
        self.assertEqual((self.output / "SHA256SUMS").read_text(), hashlib.sha256(original).hexdigest() + "  pool/" + package_name + "\n")

    def test_release_hashes_match_all_three_indexes(self):
        self.generate()
        release = (self.output / "Release").read_text()
        for label, algorithm in (("MD5Sum", "md5"), ("SHA1", "sha1"), ("SHA256", "sha256")):
            block = release.split(label + ":\n", 1)[1].splitlines()[:3]
            for entry, name in zip(block, repo.INDEX_NAMES):
                digest, size, parsed_name = entry.split()
                content = (self.output / name).read_bytes()
                self.assertEqual((parsed_name, size, digest), (name, str(len(content)), hashlib.new(algorithm, content).hexdigest()))

    def test_repeat_generation_is_deterministic(self):
        self.generate()
        before = {path.relative_to(self.output): path.read_bytes() for path in self.output.rglob("*") if path.is_file()}
        self.generate()
        after = {path.relative_to(self.output): path.read_bytes() for path in self.output.rglob("*") if path.is_file()}
        self.assertEqual(before, after)
        self.assertEqual((self.output / "Packages.gz").read_bytes()[4:8], b"\0" * 4)

    def test_preserves_and_indexes_existing_pool_versions(self):
        self.generate()
        self.generate(fixture(version="0.1.1"))
        self.assertEqual(len(list((self.output / "pool").iterdir())), 2)
        self.assertEqual((self.output / "Packages").read_text().count("Package: " + repo.PACKAGE), 2)

    def test_same_version_cannot_silently_change_published_bytes(self):
        self.generate()
        before = (self.output / "Packages").read_bytes()
        with self.assertRaisesRegex(ValueError, "already published version"):
            self.generate(fixture(fields={"Name": "Different bytes"}))
        self.assertEqual((self.output / "Packages").read_bytes(), before)

    def test_rejects_random_deb_without_creating_site(self):
        with self.assertRaisesRegex(ValueError, "not a Debian ar archive"):
            self.generate(b"This is not a package")
        self.assertFalse(self.output.exists())

    def test_rejects_empty_or_foreign_payloads(self):
        for content in (fixture(library=b""), fixture(library=b"not-a-dylib"),
                        fixture(fields={"Architecture": "iphoneos-arm64"}),
                        fixture(fields={"Package": "org.unrelated.tweak"})):
            with self.subTest(content_hash=hashlib.sha256(content).hexdigest()):
                with self.assertRaises(ValueError):
                    repo.validate_deb(content)

    def test_rejects_wrong_macho_architecture_type_or_deployment_target(self):
        for library in (macho(cpu=7), macho(subtype=11), macho(kind=2),
                        macho(minimum=0x00070000), macho(minimum=0), b"\xcf\xfa\xed\xfe" + b"\0" * 64):
            with self.subTest(library=library[:28]):
                with self.assertRaises(ValueError):
                    repo.validate_deb(fixture(library=library))
        self.assertEqual(repo.validate_macho(macho(minimum=0x00060103)), "6.1.3")

    def test_rejects_unreviewed_injection_targets_and_maintainer_scripts(self):
        for filters in ({"Filter": {"Executables": ["Preferences", "accountsd", "apsd"]}},
                        {"Filter": {"Executables": ["accountsd"]}},
                        {"Filter": {"Executables": ["Preferences", "accountsd"], "Bundles": ["any"]}}):
            with self.assertRaisesRegex(ValueError, "allowlist"):
                repo.validate_deb(fixture(filters=filters))
        with self.assertRaisesRegex(ValueError, "maintainer scripts"):
            repo.validate_deb(fixture(control_extra={"./postinst": b"#!/bin/sh\nkillall accountsd\n"}))

    def test_rejects_path_traversal_and_modern_package_compression(self):
        with self.assertRaisesRegex(ValueError, "unsafe tar"):
            repo.validate_deb(fixture(data_extra={"../outside": b"anything"}))
        content = fixture().replace(b"control.tar.gz", b"control.tar.xz", 1)
        with self.assertRaisesRegex(ValueError, "control.tar.gz"):
            repo.validate_deb(content)

    def test_rejects_duplicate_control_fields_and_version_path_injection(self):
        for content in (fixture(fields={"package": repo.PACKAGE}), fixture(version="0.1/../bad"),
                        fixture(fields={"Description": "hello\n\nPackage: forged"})):
            with self.assertRaises(ValueError):
                repo.validate_deb(content)

    def test_refuses_source_checkout_or_stale_signature_output(self):
        self.output.mkdir()
        marker = self.output / "README.md"
        marker.write_text("unrelated file")
        with self.assertRaisesRegex(ValueError, "clean staging"):
            self.generate()
        self.assertEqual(marker.read_text(), "unrelated file")
        marker.unlink()
        (self.output / "Release.gpg").write_bytes(b"stale signature")
        with self.assertRaisesRegex(ValueError, "clean staging"):
            self.generate()

    def test_refuses_corrupted_existing_pool_before_changing_indexes(self):
        self.generate()
        before = (self.output / "Packages").read_bytes()
        next((self.output / "pool").iterdir()).write_bytes(b"corrupt")
        with self.assertRaises(ValueError):
            self.generate(fixture(version="0.1.1"))
        self.assertEqual((self.output / "Packages").read_bytes(), before)

    def test_validates_https_urls_and_renders_cydia_link_without_javascript(self):
        for address in ("http://example.com/", "https://user:pass@example.com/", "https://example.com/?x=1", "javascript:alert(1)"):
            with self.assertRaises(ValueError):
                repo.normalized_url(address)
        self.generate()
        page = (self.output / "index.html").read_text(encoding="utf-8")
        self.assertIn("cydia://url/https://cydia.saurik.com/api/share#?source=", page)
        self.assertIn("https%3A%2F%2Fexample.github.io%2FiCloudBridge6%2F", page)
        self.assertIn("诊断 Alpha", page)
        self.assertNotIn("<script", page)


if __name__ == "__main__":
    unittest.main()
