#!/usr/bin/env python3
"""Export explicit source groups as Git tree entries, excluding private/build data."""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOP = {"README.md", "LICENSE", "Makefile", "control", "iCloudBridge6.plist", ".gitignore"}
EXTENSIONS = {"src": {".m", ".h"}, "tests": {".m", ".py", ".sh"},
              "tools": {".py", ".sh"}, "config": {".plist"}, "docs": {".md"},
              ".github": {".yml", ".yaml"}}


def entries():
    result = []
    for path in sorted(ROOT.rglob("*")):
        relative = path.relative_to(ROOT)
        if path.is_symlink():
            raise ValueError("Refuse symlinks in publication source.")
        if not path.is_file() or "__pycache__" in relative.parts:
            continue
        allowed = relative.as_posix() in TOP or (relative.parts[0] in EXTENSIONS and
                   path.suffix in EXTENSIONS[relative.parts[0]] and
                   (len(relative.parts) == 2 or relative.parts[0] == ".github"))
        if not allowed:
            continue
        data = path.read_bytes()
        if len(data) > 1_000_000 or b"\x00" in data:
            raise ValueError("Only small UTF-8 source files may be published.")
        result.append({"path": relative.as_posix(), "mode": "100755" if path.suffix == ".sh" else "100644",
                       "type": "blob", "content": data.decode("utf-8")})
    return result


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--group", choices=("core", "docs", "ci", "all"), default="all")
    args = parser.parse_args()
    selected = entries()
    if args.group != "all":
        selected = [e for e in selected if
                    (args.group == "docs" and e["path"].startswith("docs/")) or
                    (args.group == "ci" and e["path"].startswith(".github/")) or
                    (args.group == "core" and not e["path"].startswith(("docs/", ".github/")))]
    print("IB6_GIT_ENTRIES=" + json.dumps(selected, ensure_ascii=False))
