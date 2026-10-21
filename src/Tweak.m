#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#ifndef IB6_TESTING
#import <substrate.h>
#endif
#import <dlfcn.h>
#import <pthread.h>
#import <unistd.h>
#import <string.h>
#import <stdlib.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>
#import "IB6Policy.h"

// Only constant labels and numeric/boolean metrics may reach this logger.
static NSDictionary *IB6Config;
static pthread_mutex_t IB6Lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned IB6Sequence, IB6Session;
static const NSUInteger IB6Limit = 2 * 1024 * 1024;
#ifndef IB6_TESTING
static pthread_key_t IB6SecurityGuard;
static unsigned IB6Transaction;
static char IB6ProxyKey;
#endif
static BOOL IB6Option(NSString *key) {
    id value = [IB6Config objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] &&
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() && [value boolValue];
}

#ifndef IB6_TESTING
static unsigned IB6NextTransaction(void) {
    pthread_mutex_lock(&IB6Lock);
    unsigned tx = ++IB6Transaction;
    pthread_mutex_unlock(&IB6Lock);
    return tx;
}
#endif
static void IB6Log(NSString *event, unsigned tx, NSString *detail) {
    pthread_mutex_lock(&IB6Lock);
    unsigned seq = ++IB6Sequence;
    pthread_mutex_unlock(&IB6Lock);
    if (seq > 2001) return;
    if (seq == 2001) { event = @"budget_exhausted"; detail = @""; tx = 0; }
    NSLog(@"IB6 session=%08x seq=%u tx=%u event=%@ %@", IB6Session, seq, tx, event, detail ?: @"");
}
static NSString *IB6Metrics(NSData *data) {
    if ([data length] > IB6Limit) return @"body=oversize";
    id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    NSDictionary *summary = IB6SummarizePlist(plist);
    NSMutableArray *fields = [NSMutableArray array];
    for (NSString *key in [[summary allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        // Policy emits a closed vocabulary and bounded NSNumber values only.
        id value = [summary objectForKey:key];
        if ([value isKindOfClass:[NSNumber class]] || [value isEqual:@"absent"] || [value isEqual:@"invalid"])
            [fields addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
    }
    return [fields componentsJoinedByString:@" "];
}

@interface IB6ClientProxy : NSObject <NSURLProtocolClient>
@property(nonatomic, strong) id<NSURLProtocolClient> target;
@property(nonatomic, copy) NSString *endpoint;
@property(nonatomic, strong) NSURL *originalURL;
@property(nonatomic) unsigned tx;
@property(nonatomic) BOOL holding, overflow, terminal;
@property(nonatomic) NSURLCacheStoragePolicy cachePolicy;
@property(nonatomic, strong) NSURLResponse *response;
@property(nonatomic, strong) NSMutableData *body;
- (void)cancel;
@end

@implementation IB6ClientProxy
- (void)flushOriginal:(NSURLProtocol *)protocol {
    BOOL held = self.holding;
    NSData *prefix = self.body; NSURLResponse *response = self.response;
    self.holding = NO;
    self.body = nil;
    if (held && response) {
        [self.target URLProtocol:protocol didReceiveResponse:response cacheStoragePolicy:self.cachePolicy];
        if (!self.terminal && [prefix length]) [self.target URLProtocol:protocol didLoadData:prefix];
    }
}
- (void)URLProtocol:(NSURLProtocol *)protocol didReceiveResponse:(NSURLResponse *)response cacheStoragePolicy:(NSURLCacheStoragePolicy)policy {
    @synchronized(self) {
    if (self.terminal) return;
    if (self.response) { [self flushOriginal:protocol]; self.overflow = YES; }
    if (self.terminal) return;
    self.response = response;
    self.cachePolicy = policy;
    NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
    self.holding = [[IB6Config objectForKey:@"Mode"] isEqual:@"adapt"] &&
        (IB6Option(@"NormalizeNumericDSID") || IB6Option(@"RestoreRequestURL")) && !self.overflow &&
        ![self.endpoint isEqual:@"gsa"] && status >= 200 && status < 300;
    self.body = [NSMutableData data];
    IB6Log(@"delivery_response", self.tx, [NSString stringWithFormat:@"endpoint=%@ http=%ld", self.endpoint, (long)status]);
    if (!self.holding) [self.target URLProtocol:protocol didReceiveResponse:response cacheStoragePolicy:policy];
    }
}
- (void)URLProtocol:(NSURLProtocol *)protocol didLoadData:(NSData *)data {
    @synchronized(self) {
    if (self.terminal) return;
    if (!self.overflow && [data length] <= IB6Limit - [self.body length]) {
        [self.body appendData:data];
    } else if (!self.overflow) {
        // Held bytes precede this chunk; the overflow chunk is forwarded once.
        self.overflow = YES;
        [self flushOriginal:protocol];
        IB6Log(@"delivery_overflow", self.tx, @"");
    }
    if (!self.holding && !self.terminal) [self.target URLProtocol:protocol didLoadData:data];
    }
}
- (void)URLProtocolDidFinishLoading:(NSURLProtocol *)protocol {
    @synchronized(self) {
    if (self.terminal) return;
    IB6Log(@"delivery_body", self.tx, self.overflow ? @"body=oversize" : IB6Metrics(self.body ?: [NSData data]));
    if (self.holding) {
        NSInteger status = [self.response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)self.response statusCode] : 0;
        BOOL changed = NO; NSString *reason = nil;
        NSData *output = IB6AdaptResponse(self.body, self.endpoint, status, IB6Config, &changed, &reason);
        NSURLResponse *response = self.response;
        BOOL restoreURL = IB6Option(@"RestoreRequestURL") &&
            [self.endpoint isEqual:@"login"] && [IB6EndpointForURL([response URL]) isEqual:@"settings"] &&
            IB6ResponseCanAdapt(self.body,self.endpoint,status);
        NSURL *responseURL = restoreURL ? self.originalURL : [response URL];
        BOOL anyChange = changed || restoreURL;
        if (anyChange && [response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSMutableDictionary *headers = [[(NSHTTPURLResponse *)response allHeaderFields] mutableCopy];
            for (NSString *key in (changed ? [[headers allKeys] copy] : @[])) {
                NSString *lower = [key lowercaseString];
                if ([lower isEqual:@"content-length"] || [lower isEqual:@"transfer-encoding"] ||
                    [lower isEqual:@"content-encoding"] || [lower isEqual:@"etag"] ||
                    [lower isEqual:@"content-md5"] || [lower isEqual:@"digest"]) [headers removeObjectForKey:key];
            }
            if (changed) {
                [headers setObject:[NSString stringWithFormat:@"%lu", (unsigned long)[output length]] forKey:@"Content-Length"];
                // Policy preserves XML/binary format. Preserve its MIME type too.
            }
            response = [[NSHTTPURLResponse alloc] initWithURL:responseURL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:headers];
        }
        // reason is deliberately not logged: retain a closed logging vocabulary.
        IB6Log(@"adapter", self.tx, [NSString stringWithFormat:@"changed=%d dsid=%d url=%d",anyChange,changed,restoreURL]);
        [self.target URLProtocol:protocol didReceiveResponse:response cacheStoragePolicy:anyChange ? NSURLCacheStorageNotAllowed : self.cachePolicy];
        if (!self.terminal && [output length]) [self.target URLProtocol:protocol didLoadData:output];
    }
    if (!self.terminal) { self.terminal = YES; [self.target URLProtocolDidFinishLoading:protocol]; }
    self.body = nil; self.response = nil; self.target = nil;
    }
}
- (void)URLProtocol:(NSURLProtocol *)protocol didFailWithError:(NSError *)error {
    @synchronized(self) {
    if (self.terminal) return;
    [self flushOriginal:protocol];
    IB6Log(@"delivery_failure", self.tx, @"");
    if (!self.terminal) { self.terminal = YES; [self.target URLProtocol:protocol didFailWithError:error]; }
    self.response = nil; self.target = nil;
    }
}
- (void)URLProtocol:(NSURLProtocol *)protocol wasRedirectedToRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
    @synchronized(self) {
    if (self.terminal) return;
    // Do not carry adaptation authority across redirects.
    [self flushOriginal:protocol]; self.overflow = YES;
    IB6Log(@"delivery_redirect", self.tx, @"");
    if (!self.terminal) [self.target URLProtocol:protocol wasRedirectedToRequest:request redirectResponse:response];
    }
}
- (void)URLProtocol:(NSURLProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    @synchronized(self) { if (self.terminal) return;
    [self.target URLProtocol:protocol didReceiveAuthenticationChallenge:challenge];
    }
}
- (void)URLProtocol:(NSURLProtocol *)protocol didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    @synchronized(self) { if (self.terminal) return;
    [self.target URLProtocol:protocol didCancelAuthenticationChallenge:challenge];
    }
}
- (void)URLProtocol:(NSURLProtocol *)protocol cachedResponseIsValid:(NSCachedURLResponse *)response {
    @synchronized(self) { if (self.terminal) return;
    [self.target URLProtocol:protocol cachedResponseIsValid:response];
    }
}
- (void)cancel {
    @synchronized(self) { if (self.terminal) return;
    self.terminal = YES; self.holding = NO; self.body = nil; self.response = nil; self.target = nil;
    IB6Log(@"delivery_cancel", self.tx, @"");
    }
}
@end

#ifndef IB6_TESTING
static id (*OrigClient)(id, SEL);
static void (*OrigStop)(id, SEL);
static id HookClient(id self, SEL cmd) {
    NSString *endpoint = IB6EndpointForURL([[(NSURLProtocol *)self request] URL]);
    if (!endpoint) return OrigClient(self, cmd);
    @synchronized(self) {
        IB6ClientProxy *proxy = objc_getAssociatedObject(self, &IB6ProxyKey);
        if (!proxy) {
            proxy = [IB6ClientProxy new]; proxy.target = OrigClient(self, cmd);
            proxy.endpoint = endpoint; proxy.originalURL = [[(NSURLProtocol *)self request] URL]; proxy.tx = IB6NextTransaction();
            objc_setAssociatedObject(self, &IB6ProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return proxy;
    }
}
static void HookStop(id self, SEL cmd) {
    // Keep a terminal tombstone: upstream queued work can still call self.client.
    (void)HookClient(self,@selector(client));
    IB6ClientProxy *proxy = objc_getAssociatedObject(self, &IB6ProxyKey);
    [proxy cancel];
    OrigStop(self, cmd);
}

static NSData *(*OrigSync)(id, SEL, NSURLRequest *, NSURLResponse **, NSError **);
static NSData *HookSync(id self, SEL cmd, NSURLRequest *request, NSURLResponse **response, NSError **error) {
    NSURLResponse *__autoreleasing localResponse = nil;
    NSData *data = OrigSync(self, cmd, request, response ?: &localResponse, error);
    NSString *endpoint = IB6EndpointForURL([request URL]);
    if (endpoint) {
        NSURLResponse *r = response ? *response : localResponse;
        NSInteger status = [r isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)r statusCode] : 0;
        IB6Log(@"transport_body", IB6NextTransaction(), [NSString stringWithFormat:@"endpoint=%@ http=%ld %@", endpoint, (long)status, IB6Metrics(data ?: [NSData data])]);
    }
    return data;
}

// Runtime ABI checks use declared argument types; no object descriptions or KVC.
static char IB6Type(const char *s) {
    while (*s && strchr("rnNoORV", *s)) s++;
    return *s;
}
static BOOL IB6Signature(Class cls, const char *name, char result, const char *args) {
    if (!cls) return NO;
    SEL selector = sel_registerName(name); Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != strlen(args) + 2) return NO;
    char type[128]; method_getReturnType(method, type, sizeof(type));
    if (IB6Type(type) != result) return NO;
    for (unsigned i = 0; i < strlen(args); i++) {
        method_getArgumentType(method, i + 2, type, sizeof(type));
        if (IB6Type(type) != args[i]) return NO;
    }
    return YES;
}
static BOOL IB6Hook(Class cls, const char *name, char result, const char *args, IMP replacement, IMP *original) {
    if (!IB6Signature(cls,name,result,args)) return NO;
    MSHookMessageEx(cls, sel_registerName(name), replacement, original);
    return YES;
}
static BOOL IB6BoolHook(Class cls, const char *name, IMP replacement, IMP *original) {
    Method m = cls ? class_getInstanceMethod(cls, sel_registerName(name)) : NULL;
    if (!m) return NO;
    char t[32]; method_getReturnType(m, t, sizeof(t)); char code = IB6Type(t);
    return (code == 'c' || code == 'B') && IB6Hook(cls, name, code, "", replacement, original);
}

#define IB6_VOID1(NAME, EVENT) \
static void (*Orig##NAME)(id,SEL,id); \
static void Hook##NAME(id self, SEL cmd, id arg) { \
    IB6Log(@EVENT "_begin",0,@""); Orig##NAME(self,cmd,arg); IB6Log(@EVENT "_end",0,@""); }
#define IB6_VOID0(NAME, EVENT) \
static void (*Orig##NAME)(id,SEL); \
static void Hook##NAME(id self, SEL cmd) { \
    IB6Log(@EVENT "_begin",0,@""); Orig##NAME(self,cmd); IB6Log(@EVENT "_end",0,@""); }

static NSInteger IB6CollectionCount(id value) {
    return ([value isKindOfClass:[NSSet class]] || [value isKindOfClass:[NSArray class]]) ? (NSInteger)[value count] : -1;
}
static void (*OrigEnabled)(id,SEL,id);
static void HookEnabled(id self,SEL cmd,id value) {
    IB6Log(@"account_enabled_begin",0,[NSString stringWithFormat:@"count=%ld",(long)IB6CollectionCount(value)]);
    OrigEnabled(self,cmd,value); IB6Log(@"account_enabled_end",0,@"");
}
static void (*OrigProvisioned)(id,SEL,id);
static void HookProvisioned(id self,SEL cmd,id value) {
    IB6Log(@"account_provisioned_begin",0,[NSString stringWithFormat:@"count=%ld",(long)IB6CollectionCount(value)]);
    OrigProvisioned(self,cmd,value); IB6Log(@"account_provisioned_end",0,@"");
}
static void (*OrigEnabledOne)(id,SEL,BOOL,id);
static void HookEnabledOne(id self,SEL cmd,BOOL enabled,id dataclass) {
    IB6Log(@"account_enabled_one",0,enabled ? @"enabled=1" : @"enabled=0");
    OrigEnabledOne(self,cmd,enabled,dataclass);
}
IB6_VOID1(DSID, "account_dsid")
IB6_VOID1(Credential, "account_credential")
IB6_VOID1(ProvisionResponse, "provision_response")
IB6_VOID1(DelegateTokens, "delegate_tokens")
IB6_VOID1(DelegateComplete, "delegate_complete")
IB6_VOID0(SaveTokens, "native_save_tokens")
IB6_VOID0(SavePassword, "native_save_password")

static BOOL (*OrigConfigured)(id,SEL);
static BOOL HookConfigured(id self, SEL cmd) {
    BOOL result = OrigConfigured(self, cmd);
    IB6Log(@"configured_sync",0,result ? @"success=1" : @"success=0"); return result;
}
static void (*OrigSave)(id,SEL,id,id);
static void HookSave(id self, SEL cmd, id account, void (^completion)(BOOL,NSError *)) {
    IB6Log(@"account_save_begin",0,@"");
    if (!completion) { OrigSave(self,cmd,account,nil); return; }
    void (^wrapped)(BOOL,NSError *) = ^(BOOL success, NSError *error) {
        IB6Log(@"account_save_result",0,success ? @"success=1" : @"success=0");
        completion(success,error);
    };
    OrigSave(self,cmd,account,wrapped);
}
static void (*OrigSaveVerified)(id,SEL,id,id);
static void HookSaveVerified(id self, SEL cmd, id account, void (^completion)(BOOL,NSError *)) {
    IB6Log(@"account_save_verified_begin",0,@"");
    if (!completion) { OrigSaveVerified(self,cmd,account,nil); return; }
    void (^wrapped)(BOOL,NSError *) = ^(BOOL success, NSError *error) {
        IB6Log(@"account_save_verified_result",0,success ? @"success=1" : @"success=0");
        completion(success,error);
    };
    OrigSaveVerified(self,cmd,account,wrapped);
}
static id (*OrigGetCredential)(id,SEL,id);
static id HookGetCredential(id self,SEL cmd,id account) {
    id result = OrigGetCredential(self,cmd,account);
    IB6Log(@"account_read_credential",0,result ? @"present=1" : @"present=0"); return result;
}

static NSString *IB6ItemClass(CFDictionaryRef query) {
    if (!query || CFGetTypeID(query) != CFDictionaryGetTypeID()) return @"unknown";
    CFTypeRef c = CFDictionaryGetValue(query,kSecClass);
    if (c && CFEqual(c,kSecClassGenericPassword)) return @"generic";
    if (c && CFEqual(c,kSecClassInternetPassword)) return @"internet";
    if (c && CFEqual(c,kSecClassIdentity)) return @"identity";
    if (c && CFEqual(c,kSecClassCertificate)) return @"certificate";
    if (c && CFEqual(c,kSecClassKey)) return @"key";
    return @"unknown";
}
static OSStatus (*OrigSecCopy)(CFDictionaryRef,CFTypeRef *);
static OSStatus (*OrigSecAdd)(CFDictionaryRef,CFTypeRef *);
static OSStatus (*OrigSecUpdate)(CFDictionaryRef,CFDictionaryRef);
static OSStatus HookSecCopy(CFDictionaryRef query,CFTypeRef *result) {
    if (pthread_getspecific(IB6SecurityGuard)) return OrigSecCopy(query,result);
    pthread_setspecific(IB6SecurityGuard,(void *)1);
    OSStatus status = OrigSecCopy(query,result);
    IB6Log(@"keychain_copy",0,[NSString stringWithFormat:@"item=%@ osstatus=%ld",IB6ItemClass(query),(long)status]);
    pthread_setspecific(IB6SecurityGuard,NULL); return status;
}
static OSStatus HookSecAdd(CFDictionaryRef query,CFTypeRef *result) {
    if (pthread_getspecific(IB6SecurityGuard)) return OrigSecAdd(query,result);
    pthread_setspecific(IB6SecurityGuard,(void *)1);
    OSStatus status = OrigSecAdd(query,result);
    IB6Log(@"keychain_add",0,[NSString stringWithFormat:@"item=%@ osstatus=%ld",IB6ItemClass(query),(long)status]);
    pthread_setspecific(IB6SecurityGuard,NULL); return status;
}
static OSStatus HookSecUpdate(CFDictionaryRef query,CFDictionaryRef updates) {
    if (pthread_getspecific(IB6SecurityGuard)) return OrigSecUpdate(query,updates);
    pthread_setspecific(IB6SecurityGuard,(void *)1);
    OSStatus status = OrigSecUpdate(query,updates);
    IB6Log(@"keychain_update",0,[NSString stringWithFormat:@"item=%@ osstatus=%ld",IB6ItemClass(query),(long)status]);
    pthread_setspecific(IB6SecurityGuard,NULL); return status;
}

static void IB6Changed(NSNotification *note) { (void)note; IB6Log(@"account_store_changed",0,@""); }
@interface IB6Notifications : NSObject
- (void)changed:(NSNotification *)note;
@end
@implementation IB6Notifications
- (void)changed:(NSNotification *)note { IB6Changed(note); }
@end
static IB6Notifications *IB6Observer;

static void IB6Install(void) {
    static BOOL protocolInstalled, accountsInstalled, appleInstalled, delegateInstalled;
    Class protocol = NSClassFromString(@"GSAPortProtocol");
    if (!protocolInstalled && protocol && [protocol isSubclassOfClass:[NSURLProtocol class]]) {
        // Validate the pair before installing either interception boundary.
        BOOL valid = IB6Signature(protocol,"client",'@',"") && IB6Signature(protocol,"stopLoading",'v',"");
        if (valid) {
            IB6Hook(protocol,"client",'@',"",(IMP)HookClient,(IMP *)&OrigClient);
            IB6Hook(protocol,"stopLoading",'v',"",(IMP)HookStop,(IMP *)&OrigStop);
            protocolInstalled = YES;
        }
        IB6Log(@"cap_protocol",0,valid ? @"client=1 stop=1" : @"client=0 stop=0");
    }
    Class account = NSClassFromString(@"ACAccount"), store = NSClassFromString(@"ACAccountStore");
    static BOOL observingChanges;
    if (!observingChanges && store && IB6Observer) {
        NSString *__unsafe_unretained *name = (NSString *__unsafe_unretained *)dlsym(RTLD_DEFAULT,"ACAccountStoreDidChangeNotification");
        if (name && *name) {
            [[NSNotificationCenter defaultCenter] addObserver:IB6Observer selector:@selector(changed:) name:*name object:nil];
            observingChanges = YES;
            IB6Log(@"cap_notification",0,@"hooks=1");
        }
    }
    if (!accountsInstalled && account && store) {
        accountsInstalled = YES; unsigned count = 0;
        count += IB6Hook(account,"setEnabledDataclasses:",'v',"@",(IMP)HookEnabled,(IMP *)&OrigEnabled);
        count += IB6Hook(account,"setProvisionedDataclasses:",'v',"@",(IMP)HookProvisioned,(IMP *)&OrigProvisioned);
        count += IB6Hook(account,"setDSID:",'v',"@",(IMP)HookDSID,(IMP *)&OrigDSID);
        count += IB6Hook(account,"setCredential:",'v',"@",(IMP)HookCredential,(IMP *)&OrigCredential);
        if (IB6Signature(account,"setEnabled:forDataclass:",'v',"c@"))
            count += IB6Hook(account,"setEnabled:forDataclass:",'v',"c@",(IMP)HookEnabledOne,(IMP *)&OrigEnabledOne);
        else if (IB6Signature(account,"setEnabled:forDataclass:",'v',"B@"))
            count += IB6Hook(account,"setEnabled:forDataclass:",'v',"B@",(IMP)HookEnabledOne,(IMP *)&OrigEnabledOne);
        count += IB6Hook(store,"saveAccount:withCompletionHandler:",'v',"@@",(IMP)HookSave,(IMP *)&OrigSave);
        count += IB6Hook(store,"saveVerifiedAccount:withCompletionHandler:",'v',"@@",(IMP)HookSaveVerified,(IMP *)&OrigSaveVerified);
        count += IB6Hook(store,"credentialForAccount:",'@',"@",(IMP)HookGetCredential,(IMP *)&OrigGetCredential);
        IB6Log(@"cap_accounts",0,[NSString stringWithFormat:@"hooks=%u",count]);
    }
    Class aa = NSClassFromString(@"AAAccount");
    if (!appleInstalled && aa) {
        appleInstalled = YES; unsigned count = 0;
        count += IB6Hook(aa,"updateAccountWithProvisioningResponse:",'v',"@",(IMP)HookProvisionResponse,(IMP *)&OrigProvisionResponse);
        count += IB6Hook(aa,"saveTokensInKeychain",'v',"",(IMP)HookSaveTokens,(IMP *)&OrigSaveTokens);
        count += IB6Hook(aa,"savePasswordInKeychain",'v',"",(IMP)HookSavePassword,(IMP *)&OrigSavePassword);
        count += IB6BoolHook(aa,"becomeConfiguredSyncAccount",(IMP)HookConfigured,(IMP *)&OrigConfigured);
        IB6Log(@"cap_appleaccount",0,[NSString stringWithFormat:@"hooks=%u",count]);
    }
    Class delegate = NSClassFromString(@"AADelegateAccountSetupHelper");
    if (!delegateInstalled && delegate) {
        delegateInstalled = YES; unsigned count = 0;
        count += IB6Hook(delegate,"_storeDelegateTokensWithResponse:",'v',"@",(IMP)HookDelegateTokens,(IMP *)&OrigDelegateTokens);
        count += IB6Hook(delegate,"_completeDelegateSetupWithResponse:",'v',"@",(IMP)HookDelegateComplete,(IMP *)&OrigDelegateComplete);
        IB6Log(@"cap_delegate",0,[NSString stringWithFormat:@"hooks=%u",count]);
    }
}
static BOOL IB6InstallQueued;
static void IB6ImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    pthread_mutex_lock(&IB6Lock);
    if (IB6InstallQueued) { pthread_mutex_unlock(&IB6Lock); return; }
    IB6InstallQueued = YES; pthread_mutex_unlock(&IB6Lock);
    // Do not inspect classes or hook while dyld holds its image loader lock.
    dispatch_async(dispatch_get_main_queue(),^{
        pthread_mutex_lock(&IB6Lock); IB6InstallQueued = NO; pthread_mutex_unlock(&IB6Lock);
        IB6Install();
    });
}
__attribute__((constructor)) static void IB6Init(void) {
    @autoreleasepool {
        NSString *systemVersion = [[NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"] objectForKey:@"ProductVersion"];
        if (![systemVersion isKindOfClass:[NSString class]] || ![systemVersion hasPrefix:@"6."]) return;
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/local.legacyapple.icloudbridge6.plist"];
        if ([[prefs objectForKey:@"Enabled"] isEqual:@NO]) return;
        IB6Config = [prefs copy] ?: @{ @"Mode": @"observe" };
        IB6Session = arc4random();
        IB6Log(@"loaded",0,[[IB6Config objectForKey:@"Mode"] isEqual:@"adapt"] ? @"mode=adapt" : @"mode=observe");
        BOOL transport = IB6Hook(object_getClass([NSURLConnection class]),"sendSynchronousRequest:returningResponse:error:",'@',"@^^",(IMP)HookSync,(IMP *)&OrigSync);
        IB6Log(@"cap_transport",0,transport ? @"hooks=1" : @"hooks=0");
        if (IB6Option(@"ObserveSecurity")) {
            if (pthread_key_create(&IB6SecurityGuard,NULL) == 0) {
                MSHookFunction((void *)SecItemCopyMatching,(void *)HookSecCopy,(void **)&OrigSecCopy);
                MSHookFunction((void *)SecItemAdd,(void *)HookSecAdd,(void **)&OrigSecAdd);
                MSHookFunction((void *)SecItemUpdate,(void *)HookSecUpdate,(void **)&OrigSecUpdate);
                IB6Log(@"cap_security",0,@"hooks=3");
            } else IB6Log(@"cap_security",0,@"hooks=0");
        }
        IB6Observer = [IB6Notifications new];
        IB6Install();
        _dyld_register_func_for_add_image(IB6ImageAdded);
        // Frameworks can load after the tweak constructor. Bounded discovery,
        // on the main queue, never enumerate accounts or load private frameworks.
        for (unsigned i=1;i<=5;i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)i * 3 * NSEC_PER_SEC),dispatch_get_main_queue(),^{ IB6Install(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,16 * NSEC_PER_SEC),dispatch_get_main_queue(),^{
            IB6Log(@"cap_missing",0,[NSString stringWithFormat:@"protocol_class=%d account_class=%d apple_class=%d delegate_class=%d",
                NSClassFromString(@"GSAPortProtocol") != Nil,NSClassFromString(@"ACAccount") != Nil,
                NSClassFromString(@"AAAccount") != Nil,NSClassFromString(@"AADelegateAccountSetupHelper") != Nil]);
        });
    }
}
#endif
