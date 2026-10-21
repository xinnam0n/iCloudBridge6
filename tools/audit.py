#!/usr/bin/env python3
"""Offline evidence report. Never emits source lines, identifiers or tokens."""
import argparse
import collections
import hashlib
import json
import plistlib
import re
from pathlib import Path

LIMIT = 16 * 1024 * 1024
EVENTS = set("""loaded budget_exhausted delivery_response delivery_body delivery_overflow
delivery_failure delivery_redirect delivery_cancel adapter transport_body cap_protocol
cap_accounts cap_appleaccount cap_delegate account_enabled_begin account_enabled_end
account_provisioned_begin account_provisioned_end account_dsid_begin account_dsid_end
account_credential_begin account_credential_end provision_response_begin provision_response_end
delegate_tokens_begin delegate_tokens_end delegate_complete_begin delegate_complete_end
native_save_tokens_begin native_save_tokens_end native_save_password_begin native_save_password_end
configured_sync account_save_begin account_save_result account_save_verified_begin
account_save_verified_result account_read_credential keychain_copy keychain_add keychain_update
account_store_changed account_enabled_one cap_transport cap_missing cap_notification cap_security""".split())
PREFIX = re.compile(r"\bIB6 session=([0-9a-f]{8}) seq=(\d{1,10}) tx=(\d{1,10}) event=([a-z_]+)(?: |$)")
SYMPTOMS = {
    "required_dataclasses": re.compile(r"required dataclasses for syncing", re.I),
    "keychain_item_not_found": re.compile(r"(?<!\d)-25300(?!\d)"),
    "missing_store": re.compile(r"Can['’]t find store with id", re.I),
    "backup_account_id_null": re.compile(r"accountID\s*=\s*\(null\)", re.I),
    "gsa_init_attempt": re.compile(r"making gsa init request", re.I),
    "gsa_complete_attempt": re.compile(r"making gsa complete request", re.I),
}


def read_bounded(path):
    with Path(path).open("rb") as stream:
        data = stream.read(LIMIT + 1)
    if len(data) > LIMIT:
        raise ValueError("input_too_large")
    return data


def identity(data):
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def analyze_syslog(data):
    result = {**identity(data), "symptoms": {}, "bridge_event_counts": {},
              "bridge_session_count": 0, "bridge_keychain_status_counts": {},
              "limits": ["Events with tx=0 have no account or transaction correlation.",
                         "OSStatus alone does not identify a CalDAV item or its access group.",
                         "A native save call ending does not prove persistence or sync."]}
    symptoms = {key: [] for key in SYMPTOMS}
    events, statuses, sessions = collections.Counter(), collections.Counter(), set()
    for number, line in enumerate(data.decode("utf-8", errors="replace").splitlines(), 1):
        for key, pattern in SYMPTOMS.items():
            if pattern.search(line):
                symptoms[key].append(number)
        match = PREFIX.search(line)
        if not match or match.group(4) not in EVENTS:
            continue
        event = match.group(4)
        events[event] += 1
        sessions.add(match.group(1))  # Count only; do not echo even transient IDs.
        if event.startswith("keychain_"):
            status = re.search(r"(?:^| )osstatus=(-?\d{1,10})(?: |$)", line[match.end():])
            if status:
                statuses[str(int(status.group(1)))] += 1
    result["symptoms"] = {key: {"count": len(lines), "lines_first_50": lines[:50]}
                           for key, lines in symptoms.items()}
    result["bridge_event_counts"] = dict(sorted(events.items()))
    result["bridge_session_count"] = len(sessions)
    result["bridge_keychain_status_counts"] = dict(sorted(statuses.items()))
    return result


def load_capture(data):
    if data.startswith(b"bplist"):
        return plistlib.loads(data)
    start, end = data.find(b"<plist"), data.rfind(b"</plist>")
    if start < 0 or end < start:
        raise ValueError("not_a_plist_capture")
    return plistlib.loads(data[start:end + len(b"</plist>")])


def integer(value):
    return value if type(value) is int and -(2**31) <= value < 2**31 else None


def dictionary(value):
    return value if isinstance(value, dict) else {}


def analyze_gsa(data):
    root = dictionary(load_capture(data))
    response = dictionary(root.get("Response"))
    status = dictionary(response.get("Status"))
    hsc, ec = integer(status.get("hsc")), integer(status.get("ec"))
    complete = all(isinstance(response.get(key), (str, bytes)) and bool(response[key])
                   for key in ("M2", "spd", "np"))
    init = all(key in response for key in ("s", "B", "i", "sp", "c"))
    return {**identity(data), "hsc": hsc, "ec": ec,
            "init_shape": init, "complete_shape": complete,
            "server_reported_complete_success": hsc == 200 and ec == 0 and complete,
            "limits": ["This inspects one response, not the client's M2 verification.",
                       "It cannot prove success of another transaction or local provisioning."]}


def analyze_delegates(data):
    root = dictionary(load_capture(data))
    mobileme = dictionary(dictionary(root.get("delegates")).get("com.apple.mobileme"))
    tokens = dictionary(mobileme.get("tokens"))
    status, substatus = integer(root.get("status")), integer(mobileme.get("status"))
    return {**identity(data), "root_status": status, "mobileme_status": substatus,
            "mobileme_token_count": len(tokens),
            "limits": ["Token presence does not validate token audience, expiry or native persistence."]}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--syslog", type=Path)
    parser.add_argument("--gsa-plist", type=Path)
    parser.add_argument("--delegate-plist", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    if not any((args.syslog, args.gsa_plist, args.delegate_plist)):
        parser.error("Provide at least one input.")
    result = {"schema": 1, "contains_raw_values": False}
    for role, path, analyze in (("syslog", args.syslog, analyze_syslog),
                                ("gsa", args.gsa_plist, analyze_gsa),
                                ("delegates", args.delegate_plist, analyze_delegates)):
        if path:
            try:
                result[role] = analyze(read_bounded(path))
            except Exception:
                # Exception text and filenames may include sensitive data. Never echo them.
                result[role] = {"error": "read_or_parse_failed"}
    rendered = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        # Never replace evidence or an existing report; use a new output path.
        with args.output.open("x", encoding="utf-8") as stream:
            stream.write(rendered)
    else:
        print(rendered, end="")
    return 1 if any(isinstance(v, dict) and "error" in v for v in result.values()) else 0


if __name__ == "__main__":
    raise SystemExit(main())
