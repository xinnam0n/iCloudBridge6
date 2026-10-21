# Version clarification: the reported “1.1”

Checked against public upstream source on 2026-10-22. This is source reconnaissance, not inspection of the installed iPod binaries.

## What the answer establishes

The user replied `1.1` to a question that asked for both GSAPort and TLSFix versions. That reply does not identify which package it describes.

**Verified source fact:** the pinned iOS TLSFix [control file](https://github.com/ObscureMosquito/TLSFix/blob/d98825f45322f9a743fc3703eedc77098bec7efc/control#L1-L4) declares package `com.skyglow.tlsfix`, name TLSFix, version **1.1**. The answer is therefore consistent with TLSFix 1.1. It does not establish that the device has this exact commit or build.

**Verified source fact:** the current public GSAPort `main` history does not supply a version-1.1 source snapshot. The [control history](https://api.github.com/repos/Epixx512/GSAPort/commits?path=control&per_page=100) returned six commits that change that file; their version fields are shown below. The public branch listing returned only `main`; [release metadata](https://api.github.com/repos/Epixx512/GSAPort/releases) and [tag refs](https://api.github.com/repos/Epixx512/GSAPort/git/matching-refs/tags/) both returned empty arrays. A commit-message search for `1.1` also returned no matches. These are the results of this repository inspection, not proof that a separately distributed or repackaged GSAPort 1.1 never existed.

| Commit that changes `control` | Version in that source snapshot | Source |
| --- | --- | --- |
| `70f45b44f549bb4765f57e612d4c51d883c4f9ce` | 1.0 | [initial control](https://github.com/Epixx512/GSAPort/blob/70f45b44f549bb4765f57e612d4c51d883c4f9ce/control#L1-L4) |
| `548dc22235ebbcfe5a62d8070f4ca14b541c9df6` | 1.0 | [polyfill-era control](https://github.com/Epixx512/GSAPort/blob/548dc22235ebbcfe5a62d8070f4ca14b541c9df6/control#L1-L4) |
| `0a1523e67b828ba13f86c05cc2345a74be2e1df2` | 2.0 | [2.0 control](https://github.com/Epixx512/GSAPort/blob/0a1523e67b828ba13f86c05cc2345a74be2e1df2/control#L1-L4) |
| `795464b9b70e5481a352bcc3f564547712d68cb8` | 2.1 | [2.1 control](https://github.com/Epixx512/GSAPort/blob/795464b9b70e5481a352bcc3f564547712d68cb8/control#L1-L4) |
| `5f9b2ea52d9c8808c1a66819364f085b3cdee32e` | 2.2 | [2.2 control](https://github.com/Epixx512/GSAPort/blob/5f9b2ea52d9c8808c1a66819364f085b3cdee32e/control#L1-L4) |
| `e3c4362303031fa2330901c63e4c47ca8e4548e2` | 2.3 | [2.3 control](https://github.com/Epixx512/GSAPort/blob/e3c4362303031fa2330901c63e4c47ca8e4548e2/control#L1-L4) |

The reconnaissance pin `a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d` still declares [GSAPort 2.3](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/control#L1-L4). A version label therefore does not identify a unique commit even within the inspected public history.

## Known historical GSAPort behavior compared with the current pin

Because no public 1.1 snapshot was identified, the historical comparison below uses the **explicitly labeled 1.0** initial snapshot. It must not be relabeled as the user's 1.1 build.

| Boundary | Public GSAPort 1.0 snapshot | Pinned GSAPort 2.3 snapshot | Consequence for this bridge |
| --- | --- | --- | --- |
| Protocol class | `GSAPortProtocol : NSURLProtocol` | Same class and superclass | The class-local client proxy is a plausible common observation boundary; runtime discovery remains mandatory. |
| Setup endpoints claimed by `+canInitWithRequest:` | `/setup/login_or_create_account`, `/setup/iosbuddy/loginDelegates`, `/setup/get_account_settings`, and the broken authenticate placeholder path | Same endpoint list | Exact endpoint classification applies to both inspected source generations. |
| Recursion guard | `GSAPortHandled` property | Same property | Registering a competing protocol is unnecessary. |
| iCloud login response | Authenticate with server-issued PET, retrieve DSID/mmeAuthToken, fetch account settings, deliver its response/body to the original login caller | Same transformation | The response URL can be the inner account-settings URL while the caller requested login. |
| MobileMe delegate response | Substitute ADSID/PET in the request; when possible replace the returned MobileMe tokens dictionary with the account-settings tokens dictionary | Same transformation | Observe the final delivered body; do not add a competing token mapper. |
| Final setup delivery | `self.client` response → data → finish callbacks | Same callback sequence | No private provisioning selector is needed to inspect the final response. |
| `-stopLoading` | Empty method | Empty method | The bridge cannot claim it has repaired upstream cancellation. |
| Injection filter | Preferences, Find My bundles, accountsd and gamed | Adds imagent | IDS behavior and observed processes depend on the installed filter. |

Source locations: [1.0 class/endpoints/lifecycle](https://github.com/Epixx512/GSAPort/blob/70f45b44f549bb4765f57e612d4c51d883c4f9ce/Tweak.x#L365-L410), [2.3 class/endpoints/lifecycle](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x#L421-L466), [1.0 login/delegate transformations](https://github.com/Epixx512/GSAPort/blob/70f45b44f549bb4765f57e612d4c51d883c4f9ce/Tweak.x#L928-L1086), [2.3 login/delegate transformations](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x#L993-L1151), [1.0 filter](https://github.com/Epixx512/GSAPort/blob/70f45b44f549bb4765f57e612d4c51d883c4f9ce/GSAPort.plist#L5-L18), [2.3 filter](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/GSAPort.plist#L5-L19).

**Verified comparison:** the complete login/delegate implementation blocks at old lines 928–1086 and pinned lines 993–1151 were compared as text and are identical. This does not mean the whole files are identical: current source has other changes, including iOS 5 support, IM/FaceTime routing, GSA transport/retry/header work and two-factor handling. Their effect on an unknown installed package is unverified.

Neither inspected class defines its own `-client` implementation; it obtains the inherited NSURLProtocol client. At that public boundary the getter returns an object with two runtime arguments (`self`, `_cmd`); `-startLoading` and `-stopLoading` return void with the same argument count. The response callback takes a native-width `NSURLCacheStoragePolicy`; data and terminal callbacks retain their public NSURLProtocolClient signatures. Source similarity supports this hook design but does not substitute for checking the deployed method metadata and superclass chain.

Both inspected delegate branches can construct HTTP 200 when upstream has body data but no HTTP response object. The bridge sees the result **after** this upstream behavior; its logs cannot reconstruct an absent original server status. It must preserve its own strict HTTP/application-status guards and describe events as post-GSAPort observations. See [1.0 fallback](https://github.com/Epixx512/GSAPort/blob/70f45b44f549bb4765f57e612d4c51d883c4f9ce/Tweak.x#L1006-L1012) and [2.3 fallback](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x#L1071-L1077).

## Practical interpretation

**Inference:** TLSFix is the more direct match for the reported 1.1, because a verified public TLSFix control file has exactly that version. This is a working interpretation only; no package identity should be filled in automatically.

Keep the first device run in observe mode. Record GSAPort and TLSFix package IDs and versions separately, the package source/repository, and the installed GSAPort dylib checksum if available. These read-only package queries contain no account credentials:

```sh
dpkg-query -W -f='${Package}\t${Version}\n' com.podpod123.gsaport com.skyglow.tlsfix
```

If the local `dpkg-query` lacks this format, use `dpkg -s` for each package and retain only Package/Version/Status fields. Package IDs may differ in a repack. The bridge's hook-capability events then establish whether `GSAPortProtocol` and its public delivery boundary actually exist on the iPod. A missing or mismatched hook must remain a no-op. Do not upgrade or replace the user's working authentication stack merely to match the research pin.
