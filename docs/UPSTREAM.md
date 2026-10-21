# Upstream source reconnaissance

Inspected on 2026-10-22. These are public upstream snapshots, not a reconstruction of the user's installed binaries or missing uploaded logs. Source facts, upstream author reports, and recommendations are separated below. No Apple-account identifiers, authentication material, or body dumps were saved for this research.

## Versions and scope

| Project | Pinned commit | Relevance and limits |
| --- | --- | --- |
| [Epixx512/GSAPort](https://github.com/Epixx512/GSAPort/tree/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d) | `a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d`, 2026-10-20 | iOS implementation; exact installed build must be established before assuming identical response rewriting. |
| [ObscureMosquito/TLSFix](https://github.com/ObscureMosquito/TLSFix/tree/d98825f45322f9a743fc3703eedc77098bec7efc) | `d98825f45322f9a743fc3703eedc77098bec7efc`, 2026-07-14 | iOS Secure Transport hooks. The repository credits nfzerox as original author. |
| [Wowfunhappy/AquaTransport](https://github.com/Wowfunhappy/AquaTransport/tree/4af032dbba7f57715523abed75fba406110ab614) | `4af032dbba7f57715523abed75fba406110ab614`, 2026-10-20 | Former `Wowfunhappy/TLSFix`; current Mac port targets OS X 10.6-10.9, with its GSA adapter for 10.7-10.9. It is a useful comparison, not iOS ABI evidence. |
| [victorlobe/iCloudMailFix-Tweak](https://github.com/victorlobe/iCloudMailFix-Tweak/tree/229f836e9cae3cf02408ff6f777f01ab822ba1ac) | `229f836e9cae3cf02408ff6f777f01ab822ba1ac`, 2026-09-25 | Mail transport workaround. Its README explicitly limits the current setup to manually added accounts. |

## GSAPort already changes provisioning responses

**Source fact:** this snapshot does more than SRP. [Tweak.x lines 993-1049](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x#L993-L1049) treats `/setup/login_or_create_account` as a sequence:

1. Complete GSA and obtain a password-equivalent token (PET).
2. Authenticate against `/setup/authenticate/<account>`.
3. Read `appleAccountInfo.dsid` and `tokens.mmeAuthToken` from that response.
4. POST `/setup/get_account_settings` using those server-issued credentials.
5. Deliver the **get_account_settings response body** to the original login_or_create_account caller.

The original client identity and APNs token headers are copied into the account-settings request; several locale/timezone fields are set explicitly. The outer original request and inner endpoint therefore differ. A capture of the inner response alone does not establish what the legacy Accounts consumer accepted.

**Source fact:** [Tweak.x lines 1052-1149](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x#L1052-L1149) also rewrites the body of `/setup/iosbuddy/loginDelegates`: it substitutes ADSID/PET into the outgoing plist; after a reply containing `delegates.com.apple.mobileme.tokens`, it separately performs authenticate + get_account_settings and replaces the MobileMe delegate's **entire `tokens` dictionary** with the account-settings `tokens` dictionary when available. It then serializes and delivers that modified body.

The code does not perform analogous dataclass or account-ID adaptation there. Existence of a tokens dictionary is the branch condition; the branch does not itself prove successful native provisioning, service-scoped token sufficiency, or successful persistence. Treat this as a compatibility hypothesis already in upstream and test its effect before adding a competing token mapper.

**Inference:** the observed gap could be a native consumer/schema mismatch, an incorrect token family, an incomplete service-data structure, caller sequencing, saved credential selection, or subsequent service authentication. The cached conversation alone does not distinguish these. A generic conclusion that all authentication/TLS issues are solved and only local credential writes remain is too strong.

**Source fact:** the GSA code distinguishes init and complete, sends M1 in complete, requires returned M2, verifies it, and decrypts SPD. See [init/complete lines 777-921](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x#L777-L921). This supports preserving the user's successful-transaction evidence. It does not prove all later transactions succeeded.

## Safest concrete interception boundary

**Source fact:** the relevant class is `GSAPortProtocol : NSURLProtocol`. Its [`+canInitWithRequest:` selector](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x#L421-L449) recognizes exact setup paths and excludes requests marked with the `GSAPortHandled` NSURLProtocol property. It has `-startLoading`, a currently empty `-stopLoading`, and a constructor that registers the class. The final setup delivery is through `self.client`, followed by the standard NSURLProtocolClient response/data/finish messages. See [login final delivery](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x#L1046-L1048) and [delegate final delivery](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x#L1147-L1149).

**Recommendation:** observe that final callback boundary without registering another protocol that claims the same setup URLs. Intercepting the inherited `-client` getter only on known `GSAPortProtocol` instances allows a forwarding NSURLProtocolClient proxy to see exactly the reply delivered to the legacy consumer, after upstream substitutions. A subclass-local method override avoids changing the getter for unrelated protocol classes. Check the runtime superclass chain, argument count, return/argument types and selector availability before installing. If a different GSAPort build has no such class or callback path, log hook-unavailable and leave it untouched.

| Boundary | Objective-C signature | Runtime validation |
| --- | --- | --- |
| `-[NSURLProtocol client]` | `- (id<NSURLProtocolClient>)client` | Object return; 2 runtime arguments including self/_cmd. This is inherited by the inspected GSAPort class. |
| `-[GSAPortProtocol startLoading]` | `- (void)startLoading` | Void return; 2 runtime arguments. Optional lifecycle observation only. |
| `URLProtocol:didReceiveResponse:cacheStoragePolicy:` | `- (void)URLProtocol:(NSURLProtocol *)protocol didReceiveResponse:(NSURLResponse *)response cacheStoragePolicy:(NSURLCacheStoragePolicy)policy` | Preserve native integer width (`NSUInteger` on this platform) and callback ordering. |
| `URLProtocol:didLoadData:` | `- (void)URLProtocol:(NSURLProtocol *)protocol didLoadData:(NSData *)data` | Preserve exact bytes in observe mode; bounded reassembly required if a later build emits multiple chunks. |
| `URLProtocolDidFinishLoading:` / `URLProtocol:didFailWithError:` | Void callbacks with protocol and optional NSError | Release transient parse state at terminal callbacks. Log numerical error/status, not NSError descriptions or userInfo. |

The [Apple NSURLProtocol documentation](https://developer.apple.com/documentation/foundation/urlprotocol) defines the client property and registration model. The [Apple NSURLProtocolClient documentation](https://developer.apple.com/documentation/foundation/urlprotocolclient) lists redirects, cached responses, authentication challenges, response, data, failure and finish. A proxy must forward **all** these selectors. It must keep the original callback thread and challenge sender intact. Apple's modern documentation describes the same public boundary; deployed iOS 6 method metadata remains the ABI authority.

**Recommendation:** do not swizzle `NSPropertyListSerialization` globally. It sees authentication payloads from unrelated calls and loses endpoint/caller context. Do not replay GSA or use copied passwords to reconstruct account settings. Do not put PETs or service tokens in preferences or diagnostic files.

## Injection and hook ordering

**Source fact:** the inspected [GSAPort.plist](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/GSAPort.plist#L5-L19) includes Preferences plus accountsd, gamed, imagent and Find My app bundles. It does not inject GSAPort into every sync daemon. Its [Makefile](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Makefile#L1-L15) targets legacy iOS and armv7/arm64. This does not prove a particular installed package has the same filter.

**Recommendation:** native class observation in dataaccessd, backupd, ubd, librariand, mstreamd and aosnotifyd belongs to this bridge's own narrowly scoped injection filter. Discover and report the presence/encoding of candidate selectors on the target, then enable only proven signatures. A dylib filename does not guarantee constructor/class-registration order; retry hook discovery after relevant images load without forcing them to load or repeating a successful hook. A miss must not become a guessed ABI call.

## TLSFix boundary and APNs/IDS

**Source fact:** iOS TLSFix hooks exported Secure Transport functions using `MSHookFunction`, including SSL handshake/read/write, peer trust/certificates and client certificate setup. See [tlsfix_hooks.c lines 177-216](https://github.com/ObscureMosquito/TLSFix/blob/d98825f45322f9a743fc3703eedc77098bec7efc/src/tlsfix_hooks.c#L177-L216). Its client-identity path obtains a SecKey reference from a SecIdentity and signs via `SecKeyRawSign`; chain validation invokes `SecTrustEvaluate`. See [engine lines 95-136](https://github.com/ObscureMosquito/TLSFix/blob/d98825f45322f9a743fc3703eedc77098bec7efc/src/tlsfix_engine.c#L95-L136) and [trust validation](https://github.com/ObscureMosquito/TLSFix/blob/d98825f45322f9a743fc3703eedc77098bec7efc/src/tlsfix_engine.c#L195-L213).

This establishes a transport/client-identity mechanism. It does not establish APNs enrollment, valid push topics, IDS profile/identity registration, service-token scope, or account provisioning. GSAPort's setup forwarding preserves `X-APNS-Token` when present ([lines 1025-1027](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x#L1025-L1027), [1063-1065](https://github.com/Epixx512/GSAPort/blob/a4ef5dddecd48e1a5839980d3f5f39e6650fbd7d/Tweak.x#L1063-L1065)); this is not evidence the token is registered or current.

**Recommendation:** the bridge should not hook SSL functions, change trust results, extract private keys, or mint APNs/IDS tokens. Observe account/service outcomes independently from transport outcome.

## What AquaTransport can and cannot contribute

**Source fact:** the [AquaTransport README](https://github.com/Wowfunhappy/AquaTransport/blob/4af032dbba7f57715523abed75fba406110ab614/README.md#L1-L5) identifies it as a Mac port based on iOS TLSFix. Its Mac GSA code follows authenticate -> account settings for legacy iCloud creation ([lines 505-526](https://github.com/Wowfunhappy/AquaTransport/blob/4af032dbba7f57715523abed75fba406110ab614/src/mac/aquatransport_gsa.m#L505-L526)). Its delegate route preserves the returned body rather than doing the inspected GSAPort token replacement ([lines 492-503](https://github.com/Wowfunhappy/AquaTransport/blob/4af032dbba7f57715523abed75fba406110ab614/src/mac/aquatransport_gsa.m#L492-L503)). This difference is worth testing, not assuming either strategy is correct for iOS 6.

Its DAV adapter narrowly recognizes iCloud CalDAV/Contacts hosts, translates only legacy DAV ports 8443/8843 to 443, adds device authentication headers, and forwards native authentication challenges. See [DAV host/port logic lines 593-623](https://github.com/Wowfunhappy/AquaTransport/blob/4af032dbba7f57715523abed75fba406110ab614/src/mac/aquatransport_gsa.m#L593-L623) and [challenge forwarding lines 705-740](https://github.com/Wowfunhappy/AquaTransport/blob/4af032dbba7f57715523abed75fba406110ab614/src/mac/aquatransport_gsa.m#L705-L740). The documentation reports actual Mavericks DAV HTTP 401 with only a saved token and HTTP 207 after device headers. This is an **upstream author report about Mavericks**, not a result on this iPod.

Its Mail adapter hooks `_MCAppleTokenSaslClient -initialResponse`, keeps the native three ATOKEN fields, then adds device fields for exact iCloud mail hosts ([lines 748-822](https://github.com/Wowfunhappy/AquaTransport/blob/4af032dbba7f57715523abed75fba406110ab614/src/mac/aquatransport_gsa.m#L748-L822)). The installed Mac selector and authentication format do not establish an iOS 6 selector or wire contract. Do not ship that selector as an iOS 6 fix without target headers/runtime inspection and isolated proof.

**Inference:** even after a correct Keychain lookup, modern DAV or Mail servers may require additional device/authentication data. Therefore a fix for -25300 is only one gate. Authentication failure after successful lookup must be diagnosed as a separate service stage rather than met with repeated Keychain writes.

## iCloudMailFix is a transport alternative

The pinned [README setup note](https://github.com/victorlobe/iCloudMailFix-Tweak/blob/229f836e9cae3cf02408ff6f777f01ab822ba1ac/README.md#L68-L108) describes manual Mail accounts and excludes the Settings -> iCloud default account. The [implementation](https://github.com/victorlobe/iCloudMailFix-Tweak/blob/229f836e9cae3cf02408ff6f777f01ab822ba1ac/iCloudMailFix/Tweak.xm#L48-L153) recognizes mail hosts and redirects their connection to loopback. This is evidence of a Mail transport workaround, not evidence of Accounts/MobileMe dataclass provisioning or of a universal account repair.

## Implementation decision supported by this reconnaissance

1. Start with endpoint-scoped, post-GSAPort response schema observation and runtime method inventory.
2. Correlate one user-initiated login attempt with native account validation/save and Keychain status-only events; the bridge must generate no login attempts itself.
3. Parse only bounded plists at that boundary, logging an allowlist of known key presence/type/counts and numerical statuses. Unknown keys may contain identifiers and must not be printed.
4. Keep observe mode byte preserving. In optional adaptation mode, change only a reviewed structural mismatch while retaining all valid fields and status values. Never fabricate success, capability, dataclass consent or service-token equivalence.
5. Let the native account plugin write its own credentials and issue its own refresh notifications first. A generic SecItemAdd template cannot be derived from the inspected upstream sources. Add a service-specific credential writer only after an exact iOS 6 native query/persistence contract and access group are proven; preserve existing items, use server-issued service credentials, and test rollback.
6. Gate each service independently: account persistence -> expected enabled dataclasses -> correct Keychain match -> native store construction -> foreground fetch -> push/refresh. Backup, ubiquity, Photo Stream and Find My need separate protocol support evidence.

No upstream source examined here proves the exact iOS 6 internal dataclass/credential schema or daemon notification strings. Those require target runtime evidence; importing later OS selectors or broadcast names as facts would be unsafe.
