# iCloudBridge6 Implementation Plan

> **For agentic workers:** Execute in this session with parallel source research and independent final review. User explicitly requested plan then implementation; no extra design approval is required.

**Goal:** Produce an iOS 6.1.3 diagnostic compatibility tweak with a strictly bounded metadata adapter.

**Architecture:** Observe the post-GSAPort delivery boundary and native provisioning/credential transitions. Keep credential ownership with AppleAccount and Accounts; offer independent opt-in response-URL alignment and numeric DSID representation conversion.

**Tech Stack:** Objective-C, Foundation, Security, MobileSubstrate, Theos, Python standard library for offline log audit.

**Spec:** DESIGN.md

## Global constraints

- `sources/` and existing PoC are read-only for this task; all work under iCloudBridge6/.
- No hardcoded credentials, no raw payload/identifier logging, no blind database or Keychain writes.
- armv7, rootful iOS 6.1.3; runtime ABI gates on all private hooks.
- Diagnostic default, explicit adapt preference, failure passthrough, reversible removal.

## Review focus

- Different GSA transactions must remain separate; no successful init implies successful complete.
- A failed or malformed response must never be made successful.
- A proxy must preserve callbacks, failure/cancellation, response headers and overflow bytes.
- A hook must not call a private selector with an unverified signature or change a BOOL/void return ABI.
- Logs must remain safe even when a server injects secrets into dictionary keys/error descriptions.

## Tasks

1. [x] Inventory original artifacts, read prior chat, record missing attachments, pin upstream and exact-version headers. Files: docs/DESIGN.md, docs/UPSTREAM.md, docs/ARCHITECTURE.md.
2. [x] Implement `IB6Policy.h/.m`: exact endpoint classification, fixed-schema summaries, `IB6AdaptResponse` with strict success/type/token-presence guards and native fixture tests. Source and fixtures complete; native execution remains pending on a Mac.
3. [x] Implement `Tweak.m`: GSAPort client proxy with bounded buffering only in adapt; ABI-gated Accounts and AppleAccount transition hooks; OSStatus-only Security observation. Add Theos Makefile, filter, control and default preferences. Native build/device validation remain pending.
4. [x] Implement offline audit of sanitized event logs and optional raw-log evidence extraction without echoing secrets; test mixed transactions, error precedence and output privacy on this host.
5. [x] Document build/install/disable/uninstall, daemon refresh through native account actions, service-by-service test matrix, failure decision tree and evidence collection.
6. [x] Independent code review, fix actionable issues and execute available host tests. Source packaging tool verifies archive contents and writes a checksum; packaging result is recorded in VALIDATION.md.

## Execution record

- Workspace is a project mirror without a Git repository; preserve it and deliver a standalone directory/archive instead of initializing/changing repository state.
- macOS/Xcode/Theos/iOS SDK and live iPod are unavailable in this Windows session. Do not substitute source scans for a native build result.
- Independent review corrections: cancelled/finished proxy tombstone, synchronized callbacks, reentrant terminal suppression, unchanged cache/MIME preservation, strict Boolean opt-in and test/header consistency. Native fixtures added; no native PASS claim.
- User supplied `1.1`; public TLSFix version matches, but package identity remains unconfirmed. See VERSION_1_1.md.
