#!/usr/bin/env python3
"""Give each GitHub workflow attempt a distinct Debian package version."""
import argparse
import os
from pathlib import Path
import re


def package_version(control: str, run_number: str, run_attempt: str) -> str:
    versions = [line.partition(":")[2].strip() for line in control.splitlines()
                if line.partition(":")[0].lower() == "version"]
    if len(versions) != 1 or not re.fullmatch(r"(?:[0-9]+:)?[0-9][A-Za-z0-9.+~:-]*", versions[0]):
        raise ValueError("control must contain one valid base Version")
    for value in (run_number, run_attempt):
        if not re.fullmatch(r"[1-9][0-9]*", value):
            raise ValueError("GitHub run number and attempt must be positive decimal integers")
    return f"{versions[0]}+ci.{run_number}.{run_attempt}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("control", type=Path)
    args = parser.parse_args()
    try:
        print(package_version(args.control.read_text(encoding="utf-8"),
                              os.environ.get("GITHUB_RUN_NUMBER", ""),
                              os.environ.get("GITHUB_RUN_ATTEMPT", "")))
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
