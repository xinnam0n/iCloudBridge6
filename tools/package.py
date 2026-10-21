#!/usr/bin/env python3
"""Create a source-only archive from an explicit allowlist; no private evidence."""
import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FILES = {"README.md", "LICENSE", "Makefile", "control", "iCloudBridge6.plist", ".gitignore"}
FOLDERS = {"src", "docs", "config", "tests", "tools"}


def main():
    selected = []
    for path in sorted(ROOT.rglob("*")):
        relative = path.relative_to(ROOT)
        if path.is_symlink():
            raise ValueError("Symlinks are not permitted in a source package.")
        if not path.is_file() or "__pycache__" in relative.parts:
            continue
        if relative.as_posix() not in FILES and relative.parts[0] not in FOLDERS:
            continue
        if relative.parts[0] in {"tests", "tools", "src", "config"} and len(relative.parts) != 2:
            continue
        if relative.parts[0] == "tests" and path.suffix not in {".m", ".py", ".sh"}:
            continue
        if path.suffix in {".pyc", ".log", ".deb", ".dylib", ".zip"}:
            continue
        if not path.resolve().is_relative_to(ROOT):
            raise ValueError("File outside the source root.")
        selected.append((relative.as_posix(), path.read_bytes()))
    manifest = "".join(f"{hashlib.sha256(data).hexdigest()}  {name}\n" for name, data in selected)
    output = ROOT.parent / "iCloudBridge6-0.1.0-source.zip"
    checksum = output.with_suffix(output.suffix + ".sha256")
    if output.exists() or checksum.exists():
        raise FileExistsError("Use a new version; existing artifacts are never overwritten.")
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in selected + [("MANIFEST.sha256", manifest.encode())]:
            item = zipfile.ZipInfo("iCloudBridge6/" + name, date_time=(2026, 10, 22, 0, 0, 0))
            item.compress_type = zipfile.ZIP_DEFLATED
            item.external_attr = (0o100755 if name.endswith(".sh") else 0o100644) << 16
            archive.writestr(item, data)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError("Archive integrity check failed.")
        for name, data in selected:
            if archive.read("iCloudBridge6/" + name) != data:
                raise ValueError("Archive member mismatch.")
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    checksum.write_text(f"{digest}  {output.name}\n", encoding="ascii")
    print(f"Packaged and verified {len(selected)} source files; no device binary. SHA256 {digest}")


if __name__ == "__main__":
    main()
