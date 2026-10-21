#!/usr/bin/env python3
"""Validate an actual iOS 6 package and produce a flat, unsigned Cydia repo.

Python 3 standard library only. Does not extract files, execute maintainer
scripts, alter Mach-O bytes, build a package, or claim device compatibility.
"""
import argparse
import bz2
import gzip
import hashlib
import html
import io
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import struct
import tarfile
import tempfile
from urllib.parse import quote, urlsplit, urlunsplit


PACKAGE = "local.legacyapple.icloudbridge6"
ARCHITECTURE = "iphoneos-arm"
LIBRARY = "Library/MobileSubstrate/DynamicLibraries/iCloudBridge6.dylib"
FILTER = "Library/MobileSubstrate/DynamicLibraries/iCloudBridge6.plist"
EXECUTABLES = {"Preferences", "accountsd", "dataaccessd", "backupd", "ubd",
               "librariand", "mstreamd", "aosnotifyd"}
MAX_DEB = 32 * 1024 * 1024
MAX_TAR = 64 * 1024 * 1024
INDEX_NAMES = ("Packages", "Packages.gz", "Packages.bz2")
GENERATED_NAMES = {*INDEX_NAMES, "Release", "index.html", ".nojekyll", "pool",
                   "SHA256SUMS", "repository.json"}


def bounded_read(path):
    with Path(path).open("rb") as stream:
        content = stream.read(MAX_DEB + 1)
    if len(content) > MAX_DEB:
        raise ValueError("package exceeds the 32 MiB limit")
    return content


def ar_members(content):
    """Read the simple ar format used by dpkg, including odd-byte padding."""
    if not content.startswith(b"!<arch>\n"):
        raise ValueError("not a Debian ar archive")
    members = []
    position = 8
    while position < len(content):
        header = content[position:position + 60]
        if len(header) != 60 or header[58:60] != b"`\n":
            raise ValueError("invalid ar member header")
        try:
            name = header[:16].decode("ascii").rstrip().removesuffix("/")
            size_text = header[48:58].decode("ascii").strip()
            if not size_text.isdecimal():
                raise ValueError
            size = int(size_text)
        except (UnicodeError, ValueError) as error:
            raise ValueError("invalid ar name or size") from error
        if not name or "/" in name or name in {item[0] for item in members}:
            raise ValueError("unsupported or duplicate ar member")
        start = position + 60
        stop = start + size
        if stop > len(content):
            raise ValueError("truncated ar member")
        members.append((name, content[start:stop]))
        position = stop + (size % 2)
        if size % 2 and content[stop:position] != b"\n":
            raise ValueError("invalid ar padding")
    if [name for name, _ in members] != ["debian-binary", "control.tar.gz", "data.tar.gz"]:
        raise ValueError("requires debian-binary, control.tar.gz and data.tar.gz in order")
    if members[0][1] != b"2.0\n":
        raise ValueError("requires Debian package format 2.0")
    return dict(members)


def tar_files(compressed):
    """Read bounded gzip tar members into memory; never write archive paths."""
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as stream:
            raw = stream.read(MAX_TAR + 1)
        if len(raw) > MAX_TAR:
            raise ValueError("uncompressed tar exceeds the 64 MiB limit")
        result = {}
        seen = set()
        with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as archive:
            for member in archive:
                name = member.name
                path = PurePosixPath(name)
                if path.is_absolute() or ".." in path.parts or "\\" in name:
                    raise ValueError("unsafe tar member path")
                normalized = str(path)
                if normalized in seen:
                    raise ValueError("duplicate tar member")
                seen.add(normalized)
                if member.isdir():
                    continue
                if not member.isfile():
                    raise ValueError("only regular files and directories are accepted")
                if member.size > MAX_TAR:
                    raise ValueError("oversized tar member")
                stream = archive.extractfile(member)
                if stream is None:
                    raise ValueError("unreadable tar member")
                result[normalized] = stream.read()
        return result
    except (OSError, EOFError, tarfile.TarError) as error:
        raise ValueError("invalid gzip tar archive") from error


def control_fields(content):
    """Parse one UTF-8 deb822 binary-control stanza without ambiguous fields."""
    try:
        lines = content.decode("utf-8").splitlines()
    except UnicodeError as error:
        raise ValueError("control is not UTF-8") from error
    fields = {}
    names = set()
    current = None
    ended = False
    for line in lines:
        if not line:
            ended = bool(fields)
            continue
        if ended or any(ord(char) < 32 and char != "\t" for char in line):
            raise ValueError("control must contain one stanza without control characters")
        if line.startswith((" ", "\t")):
            if current is None:
                raise ValueError("orphan control continuation")
            fields[current] += "\n" + line
            continue
        name, separator, value = line.partition(":")
        if not separator or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*", name):
            raise ValueError("invalid control field")
        if name.lower() in names or not value.strip():
            raise ValueError("duplicate or empty control field")
        names.add(name.lower())
        fields[name] = value.strip()
        current = name
    canonical = {name.lower(): value for name, value in fields.items()}
    if canonical.get("package") != PACKAGE:
        raise ValueError("unexpected package identifier")
    if canonical.get("architecture") != ARCHITECTURE:
        raise ValueError("requires Architecture: iphoneos-arm")
    version = canonical.get("version", "")
    if not re.fullmatch(r"(?:[0-9]+:)?[0-9][A-Za-z0-9.+~:-]*", version):
        raise ValueError("invalid or missing Version")
    for required in ("description", "maintainer"):
        if required not in canonical:
            raise ValueError("missing required control field: " + required)
    return fields


def validate_macho(content):
    """Validate a thin armv7 MH_DYLIB and its explicit iPhoneOS deployment target."""
    if len(content) < 28 or content[:4] != b"\xce\xfa\xed\xfe":
        raise ValueError("dylib is not a little-endian 32-bit Mach-O")
    _, cpu, subtype, kind, count, commands_size, _ = struct.unpack_from("<7I", content)
    if cpu != 12 or subtype & 0x00FFFFFF != 9 or kind != 6:
        raise ValueError("dylib must be a thin armv7 MH_DYLIB")
    end = 28 + commands_size
    if not count or count > commands_size // 8 or end > len(content):
        raise ValueError("invalid Mach-O load-command table")
    minimums = []
    executable_segment = False
    position = 28
    for _ in range(count):
        if position + 8 > end:
            raise ValueError("truncated Mach-O load command")
        command, size = struct.unpack_from("<2I", content, position)
        if size < 8 or size % 4 or position + size > end:
            raise ValueError("invalid Mach-O load command size")
        if command == 0x25:  # LC_VERSION_MIN_IPHONEOS
            if size != 16:
                raise ValueError("invalid LC_VERSION_MIN_IPHONEOS")
            minimums.append(struct.unpack_from("<I", content, position + 8)[0])
        if command == 0x1:  # LC_SEGMENT (32-bit)
            if size < 56:
                raise ValueError("invalid LC_SEGMENT")
            file_offset, file_size, _, protection, sections = struct.unpack_from(
                "<5I", content, position + 32)
            if size != 56 + sections * 68 or file_offset + file_size > len(content):
                raise ValueError("invalid Mach-O segment bounds")
            if file_size > 0 and protection & 0x4:
                executable_segment = True
        if command == 0x1D:  # LC_CODE_SIGNATURE: retain, but validate its bounds.
            if size != 16:
                raise ValueError("invalid LC_CODE_SIGNATURE")
            offset, length = struct.unpack_from("<2I", content, position + 8)
            if not length or offset + length > len(content):
                raise ValueError("invalid Mach-O code signature bounds")
        position += size
    if position != end or len(minimums) != 1 or not executable_segment:
        raise ValueError("requires one iPhoneOS minimum-version command and executable segment")
    if not 0 < minimums[0] <= 0x00060103:
        raise ValueError("dylib requires a newer system than iOS 6.1.3")
    return ".".join(str(part) for part in
                    (minimums[0] >> 16, (minimums[0] >> 8) & 255, minimums[0] & 255))


def validate_deb(content):
    members = ar_members(content)
    control = tar_files(members["control.tar.gz"])
    if "control" not in control:
        raise ValueError("control archive has no control file")
    # Installation must remain free of automatic daemon restarts and account writes.
    if any(name in control for name in ("preinst", "postinst", "prerm", "postrm")):
        raise ValueError("maintainer scripts require separate review; refusing automatic publication")
    fields = control_fields(control["control"])
    data = tar_files(members["data.tar.gz"])
    if not data.get(LIBRARY) or not data.get(FILTER):
        raise ValueError("package must contain the iCloudBridge6 dylib and matching filter plist")
    minimum = validate_macho(data[LIBRARY])
    try:
        payload = plistlib.loads(data[FILTER])
    except (ValueError, plistlib.InvalidFileException) as error:
        raise ValueError("invalid filter plist") from error
    filters = payload.get("Filter") if isinstance(payload, dict) else None
    targets = filters.get("Executables") if isinstance(filters, dict) else None
    if (not isinstance(targets, list) or not targets
            or any(not isinstance(item, str) or item not in EXECUTABLES for item in targets)
            or not {"Preferences", "accountsd"}.issubset(targets)
            or set(filters) != {"Executables"}):
        raise ValueError("filter must target only the reviewed iCloudBridge6 executable allowlist")
    return fields, minimum


def normalized_url(value, *, github=False):
    parts = urlsplit(value)
    if (parts.scheme != "https" or not parts.hostname or parts.username or parts.password
            or parts.query or parts.fragment or any(char.isspace() for char in value)):
        raise ValueError("URLs must be absolute HTTPS URLs without credentials, queries or fragments")
    if github and (parts.hostname != "github.com" or len(parts.path.strip("/").split("/")) != 2):
        raise ValueError("repository URL must identify a github.com owner/repository")
    return urlunsplit((parts.scheme, parts.netloc, parts.path.rstrip("/") + ("" if github else "/"), "", ""))


def filename(fields):
    lookup = {name.lower(): value for name, value in fields.items()}
    # Keep epochs distinct while remaining a portable Windows/macOS filename.
    return PACKAGE + "_" + lookup["version"].replace(":", "_") + "_" + ARCHITECTURE + ".deb"


def package_stanza(fields, content, relative_path, base_url, repository_url):
    generated = {"filename", "size", "md5sum", "sha1", "sha256", "homepage", "depiction"}
    output = [name + ": " + value for name, value in fields.items() if name.lower() not in generated]
    output.extend([
        "Homepage: " + repository_url,
        "Depiction: " + base_url,
        "Filename: " + relative_path,
        "Size: " + str(len(content)),
        "MD5sum: " + hashlib.md5(content).hexdigest(),
        "SHA1: " + hashlib.sha1(content).hexdigest(),
        "SHA256: " + hashlib.sha256(content).hexdigest(),
    ])
    return "\n".join(output) + "\n\n"


def deterministic_gzip(content):
    stream = io.BytesIO()
    with gzip.GzipFile(fileobj=stream, mode="wb", mtime=0, filename="") as compressor:
        compressor.write(content)
    return stream.getvalue()


def index_page(base_url, repository_url, records):
    esc = html.escape
    add_link = "cydia://url/https://cydia.saurik.com/api/share#?source=" + quote(base_url, safe="")
    packages = "\n".join(
        '<li><a href="pool/' + quote(name, safe="") + '">iCloudBridge6 '
        + esc(next(value for key, value in fields.items() if key.lower() == "version"))
        + '</a> (armv7; minimum iOS ' + esc(minimum) + ')</li>'
        for name, (fields, _, minimum) in sorted(records.items()))
    return ('''<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>iCloudBridge6 Cydia Repo</title>
<style>body{font:17px/1.6 Helvetica,Arial,sans-serif;max-width:680px;margin:24px auto;padding:0 18px;color:#222;background:#fff}a{color:#165dab}h1{font-size:27px}h2{font-size:21px}code,pre{font:13px/1.5 Menlo,monospace;white-space:pre-wrap;word-wrap:break-word}.notice{padding:12px;border:1px solid #aaa;background:#f7f7f7}.button{display:inline-block;border:1px solid #165dab;border-radius:5px;padding:8px 16px}li{margin:8px 0}</style>
</head><body><h1>iCloudBridge6</h1>
<p class="notice">诊断 Alpha：默认仅观察 iOS 6 iCloud 配置流程。尚未完成 iPod touch 5 / iOS 6.1.3 实机验证；不保证恢复同步，不恢复 Apple 已关闭的云端服务。</p>
<p><a class="button" href="''' + esc(add_link, quote=True) + '''">添加到 Cydia</a></p>
<p>源地址：<br><code>''' + esc(base_url) + '''</code></p>
<h2>安装</h2><ol><li>在 Cydia → 软件源 → 编辑 → 添加，粘贴上面的地址。</li>
<li>刷新软件源，搜索 iCloudBridge6，确认版本后安装。需要 iOS 6 rootful 越狱及 MobileSubstrate。</li>
<li>手动重启设备后开始一次正常的登录/续期观察；安装包不会主动杀守护进程。默认不开启响应转换。</li></ol>
<p>此源未提供 GPG 签名；索引中的校验和用于检查文件完整性，不能证明发布者身份。旧设备若无法连接 HTTPS，请先检查现有网络/TLS 支持；勿关闭证书验证或绕过来源核验。</p>
<h2>下载</h2><ul>''' + packages + '''</ul>
<h2>停用与卸载</h2><p>在 Cydia 卸载 iCloudBridge6，然后手动重启。SSH 中也可执行：</p>
<pre>dpkg -r local.legacyapple.icloudbridge6</pre>
<p>若出现崩溃，用 SSH 或越狱安全模式停用本 tweak：将 <code>/Library/MobileSubstrate/DynamicLibraries/iCloudBridge6.dylib</code> 改名为 <code>iCloudBridge6.dylib.disabled</code> 后重启。保留账户和 Keychain，不需退出 Apple ID 或清空凭据。</p>
<p><a href="''' + esc(repository_url, quote=True) + '''">源码、测试矩阵与完整说明</a> · <a href="Packages">Packages</a> · <a href="Release">Release</a></p>
</body></html>
''').encode("utf-8")


def generate(deb, output, base_url, repository_url):
    base_url = normalized_url(base_url)
    repository_url = normalized_url(repository_url, github=True)
    content = bounded_read(deb)
    fields, minimum = validate_deb(content)
    target = Path(output)
    # Require a dedicated destination: never overwrite a source checkout or a signed repo.
    if target.is_symlink() or (target.exists() and not target.is_dir()):
        raise ValueError("output must be a real directory")
    if target.exists():
        unexpected = {path.name for path in target.iterdir()} - GENERATED_NAMES
        if unexpected:
            raise ValueError("output contains files not managed by this generator; use a clean staging directory")
        if any(path.is_symlink() for path in target.iterdir()):
            raise ValueError("output must not contain symbolic links")
        if any(path.name != "pool" and not path.is_file() for path in target.iterdir()):
            raise ValueError("generated output files must be regular files")
    records = {}
    pool = target / "pool"
    if pool.exists():
        if not pool.is_dir():
            raise ValueError("pool must be a directory")
        for package_path in sorted(pool.iterdir()):
            if package_path.is_symlink() or not package_path.is_file() or package_path.suffix != ".deb":
                raise ValueError("pool may contain only regular .deb files")
            previous = bounded_read(package_path)
            previous_fields, previous_minimum = validate_deb(previous)
            if package_path.name != filename(previous_fields):
                raise ValueError("existing pool filename does not match its control metadata")
            records[package_path.name] = (previous_fields, previous, previous_minimum)
    name = filename(fields)
    if name in records and records[name][1] != content:
        raise ValueError("refusing to replace different bytes for an already published version")
    records[name] = (fields, content, minimum)
    packages = "".join(package_stanza(package_fields, package_content, "pool/" + package_name,
                                     base_url, repository_url)
                       for package_name, (package_fields, package_content, _) in sorted(records.items())).encode("utf-8")
    files = {"Packages": packages, "Packages.gz": deterministic_gzip(packages),
             "Packages.bz2": bz2.compress(packages)}
    release = ["Origin: Legacy Apple OS Project", "Label: iCloudBridge6 Alpha",
               "Suite: stable", "Version: 1", "Codename: ios6-alpha",
               "Architectures: " + ARCHITECTURE, "Components: main",
               "Description: iOS 6 diagnostic alpha; unsigned; device validation pending"]
    for title, algorithm in (("MD5Sum", "md5"), ("SHA1", "sha1"), ("SHA256", "sha256")):
        release.append(title + ":")
        for index_name in INDEX_NAMES:
            payload = files[index_name]
            release.append(" " + hashlib.new(algorithm, payload).hexdigest()
                           + " " + str(len(payload)) + " " + index_name)
    files["Release"] = ("\n".join(release) + "\n").encode("utf-8")
    files["index.html"] = index_page(base_url, repository_url, records)
    files[".nojekyll"] = b""
    files["SHA256SUMS"] = "".join(hashlib.sha256(value[1]).hexdigest() + "  pool/" + key + "\n"
                                     for key, value in sorted(records.items())).encode("ascii")
    manifest = []
    for package_name, (package_fields, package_content, package_minimum) in sorted(records.items()):
        lookup = {key.lower(): value for key, value in package_fields.items()}
        manifest.append({"package": PACKAGE, "version": lookup["version"], "architecture": ARCHITECTURE,
                         "minimum_os": package_minimum, "filename": "pool/" + package_name,
                         "size": len(package_content), "sha256": hashlib.sha256(package_content).hexdigest()})
    files["repository.json"] = (json.dumps({"base_url": base_url, "repository_url": repository_url,
                                            "signed": False, "status": "diagnostic-alpha-device-unverified",
                                            "packages": manifest}, indent=2, sort_keys=True) + "\n").encode("utf-8")
    # All validation above precedes writes. Use staging + atomic individual files;
    # publish the complete directory in one Pages deployment, never while editing it.
    target.mkdir(parents=True, exist_ok=True)
    pool.mkdir(exist_ok=True)
    for relative, payload in [("pool/" + name, content), *files.items()]:
        destination = target / relative
        with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(payload)
        try:
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)
    return {"package": PACKAGE, "version": next(value for key, value in fields.items() if key.lower() == "version"),
            "packages": len(records), "minimum_os": minimum, "sha256": hashlib.sha256(content).hexdigest()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deb", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--repository-url", required=True)
    args = parser.parse_args(argv)
    try:
        result = generate(args.deb, args.output, args.base_url, args.repository_url)
    except (OSError, ValueError, struct.error) as error:
        parser.exit(1, "Repository not generated: " + str(error) + "\n")
    print("Validated " + result["package"] + " " + result["version"]
          + "; indexed " + str(result["packages"]) + " package(s); SHA256 " + result["sha256"])


if __name__ == "__main__":
    main()
