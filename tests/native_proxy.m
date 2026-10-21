/* Native Foundation callback tests; synthetic fixtures only, no network.
 * Compile on macOS with IB6Policy.m. The production hook installer is excluded.
 */
#define IB6_TESTING 1
#import "../src/Tweak.m"
#include <stdio.h>

static unsigned IB6Tests, IB6Failures;
static void Check(BOOL condition, const char *name) {
    IB6Tests++;
    if (!condition) { IB6Failures++; fprintf(stderr, "FAIL %s\n", name); }
}

@interface IB6TestProtocol : NSURLProtocol
@end
@implementation IB6TestProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { (void)request; return NO; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {}
- (void)stopLoading {}
@end

@interface IB6ChallengeSender : NSObject <NSURLAuthenticationChallengeSender>
@end
@implementation IB6ChallengeSender
- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge { (void)credential; (void)challenge; }
- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge { (void)challenge; }
- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge { (void)challenge; }
@end

@interface IB6Recorder : NSObject <NSURLProtocolClient>
@property(nonatomic, strong) NSMutableArray *events;
@property(nonatomic, strong) NSMutableArray *responses;
@property(nonatomic, strong) NSMutableArray *policies;
@property(nonatomic, strong) NSMutableArray *chunks;
@property(nonatomic, strong) NSMutableArray *errors;
@property(nonatomic, strong) NSMutableArray *challenges;
@property(nonatomic, weak) NSURLProtocol *expectedProtocol;
@property(nonatomic, strong) NSThread *expectedThread;
@property(nonatomic) BOOL wrongProtocol, wrongThread;
@property(nonatomic, copy) void (^afterEvent)(NSString *event);
@end

@implementation IB6Recorder
- (instancetype)init {
    if ((self = [super init])) {
        self.events = [NSMutableArray array]; self.responses = [NSMutableArray array];
        self.policies = [NSMutableArray array]; self.chunks = [NSMutableArray array];
        self.errors = [NSMutableArray array]; self.challenges = [NSMutableArray array];
        self.expectedThread = [NSThread currentThread];
    }
    return self;
}
- (void)record:(NSString *)event protocol:(NSURLProtocol *)protocol {
    if (protocol != self.expectedProtocol) self.wrongProtocol = YES;
    if ([NSThread currentThread] != self.expectedThread) self.wrongThread = YES;
    [self.events addObject:event];
    if (self.afterEvent) self.afterEvent(event);
}
- (void)URLProtocol:(NSURLProtocol *)protocol didReceiveResponse:(NSURLResponse *)response cacheStoragePolicy:(NSURLCacheStoragePolicy)policy {
    [self.responses addObject:response]; [self.policies addObject:@(policy)];
    [self record:@"response" protocol:protocol];
}
- (void)URLProtocol:(NSURLProtocol *)protocol didLoadData:(NSData *)data {
    [self.chunks addObject:[data copy]]; [self record:@"data" protocol:protocol];
}
- (void)URLProtocolDidFinishLoading:(NSURLProtocol *)protocol { [self record:@"finish" protocol:protocol]; }
- (void)URLProtocol:(NSURLProtocol *)protocol didFailWithError:(NSError *)error {
    [self.errors addObject:error]; [self record:@"failure" protocol:protocol];
}
- (void)URLProtocol:(NSURLProtocol *)protocol wasRedirectedToRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
    (void)request; (void)response; [self record:@"redirect" protocol:protocol];
}
- (void)URLProtocol:(NSURLProtocol *)protocol didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    [self.challenges addObject:challenge]; [self record:@"challenge" protocol:protocol];
}
- (void)URLProtocol:(NSURLProtocol *)protocol didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    [self.challenges addObject:challenge]; [self record:@"challenge_cancel" protocol:protocol];
}
- (void)URLProtocol:(NSURLProtocol *)protocol cachedResponseIsValid:(NSCachedURLResponse *)response {
    (void)response; [self record:@"cache_valid" protocol:protocol];
}
@end

@interface IB6Harness : NSObject
@property(nonatomic, strong) IB6ClientProxy *proxy;
@property(nonatomic, strong) IB6Recorder *recorder;
@property(nonatomic, strong) NSURLProtocol *protocol;
@end
@implementation IB6Harness
@end

static NSData *Bytes(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; }
static IB6Harness *Harness(NSDictionary *config, NSString *endpoint) {
    IB6Config = [config copy];
    IB6Harness *h = [IB6Harness new]; h.recorder = [IB6Recorder new];
    NSString *path = [endpoint isEqual:@"delegates"] ? @"iosbuddy/loginDelegates" :
        [endpoint isEqual:@"settings"] ? @"get_account_settings" : @"login_or_create_account";
    NSURL *url = [NSURL URLWithString:[@"https://setup.icloud.com/setup/" stringByAppendingString:path]];
    h.protocol = [[IB6TestProtocol alloc] initWithRequest:[NSURLRequest requestWithURL:url]
        cachedResponse:nil client:h.recorder];
    h.recorder.expectedProtocol = h.protocol;
    h.proxy = [IB6ClientProxy new]; h.proxy.target = h.recorder;
    h.proxy.endpoint = endpoint; h.proxy.originalURL = url; h.proxy.tx = 1;
    return h;
}
static NSHTTPURLResponse *Response(NSString *path, NSInteger status) {
    return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:
        [@"https://setup.icloud.com/setup/" stringByAppendingString:path]]
        statusCode:status HTTPVersion:@"HTTP/1.1"
        headerFields:@{ @"Content-Type": @"text/x-xml-plist", @"ETag": @"fixture-etag", @"X-Test": @"fixture" }];
}
static NSData *Fixture(NSInteger status) {
    return [NSPropertyListSerialization dataWithPropertyList:@{
        @"status": @(status), @"appleAccountInfo": @{ @"dsid": @"42" },
        @"tokens": @{ @"mmeAuthToken": @"synthetic-fixture-token" }
    } format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
}
static NSDictionary *HeldConfig(void) {
    return @{ @"Mode": @"adapt", @"NormalizeNumericDSID": @YES, @"RestoreRequestURL": @NO };
}
static NSURLAuthenticationChallenge *Challenge(void) {
    NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:@"fixture.invalid"
        port:443 protocol:@"https" realm:nil authenticationMethod:NSURLAuthenticationMethodDefault];
    return [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space proposedCredential:nil
        previousFailureCount:0 failureResponse:nil error:nil sender:[IB6ChallengeSender new]];
}
static void SendLateCallbacks(IB6Harness *h) {
    NSHTTPURLResponse *response = Response(@"login_or_create_account",200);
    NSData *data = Bytes(@"late");
    [h.proxy URLProtocol:h.protocol didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    [h.proxy URLProtocol:h.protocol didLoadData:data];
    [h.proxy URLProtocol:h.protocol didFailWithError:[NSError errorWithDomain:@"fixture" code:7 userInfo:nil]];
    [h.proxy URLProtocol:h.protocol wasRedirectedToRequest:[NSURLRequest requestWithURL:[response URL]] redirectResponse:response];
    NSURLAuthenticationChallenge *challenge = Challenge();
    [h.proxy URLProtocol:h.protocol didReceiveAuthenticationChallenge:challenge];
    [h.proxy URLProtocol:h.protocol didCancelAuthenticationChallenge:challenge];
    [h.proxy URLProtocol:h.protocol cachedResponseIsValid:[[NSCachedURLResponse alloc] initWithResponse:response data:data]];
    [h.proxy URLProtocolDidFinishLoading:h.protocol];
}
static void CheckIdentity(IB6Harness *h, const char *name) {
    Check(!h.recorder.wrongProtocol && !h.recorder.wrongThread, name);
}

static void TestObserve(void) {
    IB6Harness *h = Harness(@{ @"Mode": @"observe" },@"login");
    NSHTTPURLResponse *response = Response(@"login_or_create_account",200);
    NSData *a = Bytes(@"first"), *b = Bytes(@"second");
    [h.proxy URLProtocol:h.protocol didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowedInMemoryOnly];
    [h.proxy URLProtocol:h.protocol didLoadData:a]; [h.proxy URLProtocol:h.protocol didLoadData:b];
    [h.proxy URLProtocolDidFinishLoading:h.protocol];
    Check([h.recorder.events isEqualToArray:@[@"response",@"data",@"data",@"finish"]],"observe callback order");
    Check([h.recorder.chunks isEqualToArray:@[a,b]],"observe exact chunks");
    Check([h.recorder.responses count] == 1 && [h.recorder.responses objectAtIndex:0] == response,"observe original response identity");
    Check([[h.recorder.policies objectAtIndex:0] unsignedIntegerValue] == NSURLCacheStorageAllowedInMemoryOnly,"observe original cache policy");
    Check(h.proxy.terminal && !h.proxy.target && !h.proxy.body && !h.proxy.response,"finish clears transient state");
    NSUInteger count = [h.recorder.events count]; SendLateCallbacks(h);
    Check([h.recorder.events count] == count,"finish drops every late callback");
    CheckIdentity(h,"observe preserves protocol and callback thread");
}

static void TestCancel(void) {
    IB6Harness *h = Harness(HeldConfig(),@"login");
    [h.proxy URLProtocol:h.protocol didReceiveResponse:Response(@"login_or_create_account",200) cacheStoragePolicy:NSURLCacheStorageAllowed];
    [h.proxy URLProtocol:h.protocol didLoadData:Bytes(@"held")];
    Check([h.recorder.events count] == 0,"adapt buffers before cancellation");
    [h.proxy cancel]; SendLateCallbacks(h); [h.proxy cancel];
    Check([h.recorder.events count] == 0,"cancel drops future response data and terminal callbacks");
    Check(h.proxy.terminal && !h.proxy.target && !h.proxy.body && !h.proxy.response,"cancel clears held state");

    IB6Harness *reentrant = Harness(HeldConfig(),@"login");
    __weak IB6ClientProxy *weakProxy = reentrant.proxy;
    reentrant.recorder.afterEvent = ^(NSString *event) { if ([event isEqual:@"response"]) [weakProxy cancel]; };
    [reentrant.proxy URLProtocol:reentrant.protocol didReceiveResponse:Response(@"login_or_create_account",200) cacheStoragePolicy:NSURLCacheStorageAllowed];
    [reentrant.proxy URLProtocol:reentrant.protocol didLoadData:Fixture(0)];
    [reentrant.proxy URLProtocolDidFinishLoading:reentrant.protocol];
    Check([reentrant.recorder.events isEqualToArray:@[@"response"]],"reentrant cancel suppresses body and finish");
}

static void TestOverflow(void) {
    IB6Harness *h = Harness(HeldConfig(),@"login");
    NSHTTPURLResponse *response = Response(@"login_or_create_account",200);
    NSData *prefix = [NSMutableData dataWithLength:IB6Limit-3], *overflow = Bytes(@"overflow"), *tail = Bytes(@"tail");
    [h.proxy URLProtocol:h.protocol didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    [h.proxy URLProtocol:h.protocol didLoadData:prefix];
    [h.proxy URLProtocol:h.protocol didLoadData:overflow];
    [h.proxy URLProtocol:h.protocol didLoadData:tail];
    [h.proxy URLProtocolDidFinishLoading:h.protocol];
    Check([h.recorder.events isEqualToArray:@[@"response",@"data",@"data",@"data",@"finish"]],"overflow original sequence");
    Check([h.recorder.chunks isEqualToArray:@[prefix,overflow,tail]],"overflow prefix chunk and tail once each");
    Check([h.recorder.responses objectAtIndex:0] == response,"overflow original response");
    Check([[h.recorder.policies objectAtIndex:0] unsignedIntegerValue] == NSURLCacheStorageAllowed,"overflow original cache policy");
    CheckIdentity(h,"overflow callback identity");
}

static void TestFailure(void) {
    IB6Harness *h = Harness(HeldConfig(),@"login");
    NSHTTPURLResponse *response = Response(@"login_or_create_account",200);
    NSData *prefix = Bytes(@"partial"); NSError *error = [NSError errorWithDomain:@"fixture" code:9 userInfo:nil];
    [h.proxy URLProtocol:h.protocol didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    [h.proxy URLProtocol:h.protocol didLoadData:prefix];
    [h.proxy URLProtocol:h.protocol didFailWithError:error];
    Check([h.recorder.events isEqualToArray:@[@"response",@"data",@"failure"]],"failure flushes original sequence");
    Check([h.recorder.chunks isEqualToArray:@[prefix]] && [h.recorder.responses objectAtIndex:0] == response,"failure preserves buffered bytes and response");
    Check([h.recorder.errors objectAtIndex:0] == error,"failure preserves NSError identity");
    NSUInteger count = [h.recorder.events count]; SendLateCallbacks(h);
    Check([h.recorder.events count] == count,"failure drops later callbacks");
}

static void TestRepeatedResponse(void) {
    IB6Harness *h = Harness(HeldConfig(),@"login");
    NSHTTPURLResponse *first = Response(@"login_or_create_account",200), *second = Response(@"get_account_settings",200);
    NSData *a = Bytes(@"first-part"), *b = Bytes(@"second-part");
    [h.proxy URLProtocol:h.protocol didReceiveResponse:first cacheStoragePolicy:NSURLCacheStorageAllowed];
    [h.proxy URLProtocol:h.protocol didLoadData:a];
    [h.proxy URLProtocol:h.protocol didReceiveResponse:second cacheStoragePolicy:NSURLCacheStorageAllowedInMemoryOnly];
    [h.proxy URLProtocol:h.protocol didLoadData:b]; [h.proxy URLProtocolDidFinishLoading:h.protocol];
    Check([h.recorder.events isEqualToArray:@[@"response",@"data",@"response",@"data",@"finish"]],"repeated response fallback order");
    Check([h.recorder.chunks isEqualToArray:@[a,b]],"repeated response loses no bytes");
    Check([h.recorder.responses isEqualToArray:@[first,second]],"repeated response preserves responses");
    Check([h.recorder.policies isEqualToArray:@[@(NSURLCacheStorageAllowed),@(NSURLCacheStorageAllowedInMemoryOnly)]],"repeated response preserves policies");
}

static void TestUnchanged(void) {
    IB6Harness *h = Harness(HeldConfig(),@"login"); NSHTTPURLResponse *response = Response(@"login_or_create_account",200);
    NSData *data = Fixture(0);
    [h.proxy URLProtocol:h.protocol didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    [h.proxy URLProtocol:h.protocol didLoadData:data]; [h.proxy URLProtocolDidFinishLoading:h.protocol];
    Check([h.recorder.events isEqualToArray:@[@"response",@"data",@"finish"]],"unchanged held response order");
    Check([h.recorder.responses objectAtIndex:0] == response && [h.recorder.chunks isEqualToArray:@[data]],"unchanged response exact passthrough");
    Check([[h.recorder.policies objectAtIndex:0] unsignedIntegerValue] == NSURLCacheStorageAllowed,"unchanged held cache policy");

    IB6Harness *malformed = Harness(HeldConfig(),@"login"); NSData *bad = Bytes(@"not a plist");
    [malformed.proxy URLProtocol:malformed.protocol didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    [malformed.proxy URLProtocol:malformed.protocol didLoadData:bad]; [malformed.proxy URLProtocolDidFinishLoading:malformed.protocol];
    Check([malformed.recorder.responses objectAtIndex:0] == response && [malformed.recorder.chunks isEqualToArray:@[bad]],"parse error preserves response and bytes");
}

static void TestRestoreURL(void) {
    NSDictionary *config = @{ @"Mode": @"adapt", @"NormalizeNumericDSID": @NO, @"RestoreRequestURL": @YES };
    IB6Harness *h = Harness(config,@"login"); NSHTTPURLResponse *inner = Response(@"get_account_settings",200);
    NSData *data = Fixture(0);
    [h.proxy URLProtocol:h.protocol didReceiveResponse:inner cacheStoragePolicy:NSURLCacheStorageAllowed];
    [h.proxy URLProtocol:h.protocol didLoadData:data]; [h.proxy URLProtocolDidFinishLoading:h.protocol];
    NSHTTPURLResponse *delivered = [h.recorder.responses objectAtIndex:0];
    Check([[delivered URL] isEqual:h.proxy.originalURL] && [delivered statusCode] == 200,"restore outer request URL only on eligible reply");
    Check([h.recorder.chunks isEqualToArray:@[data]],"URL restore preserves body bytes");
    Check([[h.recorder.policies objectAtIndex:0] unsignedIntegerValue] == NSURLCacheStorageNotAllowed,"adapted response forbids cache");
    Check([[[delivered allHeaderFields] objectForKey:@"X-Test"] isEqual:@"fixture"],"restore preserves unrelated header");
    Check([[delivered allHeaderFields] isEqual:[inner allHeaderFields]],"URL-only restore preserves byte-format and header metadata");

    IB6Harness *failed = Harness(config,@"login"); NSData *failedBody = Fixture(1);
    [failed.proxy URLProtocol:failed.protocol didReceiveResponse:inner cacheStoragePolicy:NSURLCacheStorageAllowed];
    [failed.proxy URLProtocol:failed.protocol didLoadData:failedBody]; [failed.proxy URLProtocolDidFinishLoading:failed.protocol];
    Check([failed.recorder.responses objectAtIndex:0] == inner && [failed.recorder.chunks isEqualToArray:@[failedBody]],"failed status prevents URL rewrite");
    Check([[failed.recorder.policies objectAtIndex:0] unsignedIntegerValue] == NSURLCacheStorageAllowed,"failed status preserves cache policy");

    IB6Harness *integerFlag = Harness(@{ @"Mode": @"adapt", @"RestoreRequestURL": @1 },@"login");
    [integerFlag.proxy URLProtocol:integerFlag.protocol didReceiveResponse:inner cacheStoragePolicy:NSURLCacheStorageAllowed];
    [integerFlag.proxy URLProtocol:integerFlag.protocol didLoadData:data];
    [integerFlag.proxy URLProtocolDidFinishLoading:integerFlag.protocol];
    Check([integerFlag.recorder.responses objectAtIndex:0] == inner &&
        [[integerFlag.recorder.policies objectAtIndex:0] unsignedIntegerValue] == NSURLCacheStorageAllowed,
        "integer one cannot enable URL adaptation");
}

static void TestBodyHeaders(void) {
    for (NSNumber *formatNumber in @[@(NSPropertyListXMLFormat_v1_0), @(NSPropertyListBinaryFormat_v1_0)]) {
        NSPropertyListFormat format = (NSPropertyListFormat)[formatNumber unsignedIntegerValue];
        NSDictionary *fixture = @{@"status": @0,@"appleAccountInfo": @{@"dsid": @42},
            @"tokens": @{@"mmeAuthToken": @"synthetic-fixture-token"}};
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:fixture format:format options:0 error:NULL];
        NSString *mime = format == NSPropertyListBinaryFormat_v1_0 ? @"application/x-plist" : @"text/x-xml-plist";
        IB6Harness *h = Harness(HeldConfig(),@"login");
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:h.proxy.originalURL statusCode:200 HTTPVersion:@"HTTP/1.1"
            headerFields:@{@"Content-Type":mime,@"Content-Length":@"1",@"Content-Encoding":@"gzip",
                @"Transfer-Encoding":@"chunked",@"ETag":@"stale",@"Content-MD5":@"stale",@"Digest":@"stale",@"X-Test":@"fixture"}];
        [h.proxy URLProtocol:h.protocol didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
        [h.proxy URLProtocol:h.protocol didLoadData:data]; [h.proxy URLProtocolDidFinishLoading:h.protocol];
        NSHTTPURLResponse *delivered = [h.recorder.responses objectAtIndex:0];
        NSData *body = [h.recorder.chunks objectAtIndex:0];
        NSDictionary *headers = [delivered allHeaderFields];
        Check([[headers objectForKey:@"Content-Length"] unsignedIntegerValue] == [body length],"body edit recomputes exact content length");
        Check([[headers objectForKey:@"Content-Type"] isEqual:mime],"body edit preserves binary or XML MIME type");
        Check(!headers[@"Content-Encoding"] && !headers[@"Transfer-Encoding"] && !headers[@"ETag"] && !headers[@"Content-MD5"] && !headers[@"Digest"],"body edit removes stale encodings and digests");
        NSDictionary *parsed = [NSPropertyListSerialization propertyListWithData:body options:0 format:NULL error:NULL];
        Check([parsed[@"appleAccountInfo"][@"dsid"] isEqual:@"42"] && [parsed[@"tokens"] isEqual:fixture[@"tokens"]],"proxy passes one identity representation edit with tokens intact");
        Check([[h.recorder.policies objectAtIndex:0] unsignedIntegerValue] == NSURLCacheStorageNotAllowed,"body edits are not cached");
    }
}

static void TestForwarding(void) {
    IB6Harness *h = Harness(@{ @"Mode": @"observe" },@"login"); NSHTTPURLResponse *r = Response(@"login_or_create_account",200);
    NSURLAuthenticationChallenge *challenge = Challenge(); id sender = [challenge sender];
    [h.proxy URLProtocol:h.protocol didReceiveAuthenticationChallenge:challenge];
    [h.proxy URLProtocol:h.protocol didCancelAuthenticationChallenge:challenge];
    [h.proxy URLProtocol:h.protocol cachedResponseIsValid:[[NSCachedURLResponse alloc] initWithResponse:r data:Bytes(@"cache")]];
    [h.proxy URLProtocol:h.protocol wasRedirectedToRequest:[NSURLRequest requestWithURL:[r URL]] redirectResponse:r];
    Check([h.recorder.events isEqualToArray:@[@"challenge",@"challenge_cancel",@"cache_valid",@"redirect"]],"forwards auxiliary client callbacks");
    Check([h.recorder.challenges isEqualToArray:@[challenge,challenge]] && [challenge sender] == sender,"challenge identity and native sender preserved");
    CheckIdentity(h,"auxiliary callback identity"); [h.proxy cancel];
}

static void TestTerminalReentrancy(void) {
    IB6Harness *h = Harness(@{ @"Mode": @"observe" },@"login");
    __weak IB6ClientProxy *weakProxy = h.proxy; __weak NSURLProtocol *weakProtocol = h.protocol;
    __block BOOL retried = NO;
    h.recorder.afterEvent = ^(NSString *event) {
        if ([event isEqual:@"finish"] && !retried) {
            retried = YES; [weakProxy URLProtocolDidFinishLoading:weakProtocol];
        }
    };
    [h.proxy URLProtocol:h.protocol didReceiveResponse:Response(@"login_or_create_account",200) cacheStoragePolicy:NSURLCacheStorageAllowed];
    [h.proxy URLProtocolDidFinishLoading:h.protocol];
    Check([h.recorder.events isEqualToArray:@[@"response",@"finish"]],"reentrant finish delivered once");

    IB6Harness *failed = Harness(HeldConfig(),@"login");
    __weak IB6ClientProxy *weakFailed = failed.proxy; __weak NSURLProtocol *weakFailedProtocol = failed.protocol;
    __block BOOL failureRetried = NO;
    NSError *error = [NSError errorWithDomain:@"fixture" code:11 userInfo:nil];
    failed.recorder.afterEvent = ^(NSString *event) {
        if ([event isEqual:@"failure"] && !failureRetried) {
            failureRetried = YES; [weakFailed URLProtocol:weakFailedProtocol didFailWithError:error];
        }
    };
    [failed.proxy URLProtocol:failed.protocol didFailWithError:error];
    Check([failed.recorder.events isEqualToArray:@[@"failure"]],"reentrant failure delivered once");
}

int main(void) {
    @autoreleasepool {
        TestObserve(); TestCancel(); TestOverflow(); TestFailure(); TestRepeatedResponse();
        TestUnchanged(); TestRestoreURL(); TestBodyHeaders(); TestForwarding(); TestTerminalReentrancy();
        fprintf(stderr,"native_proxy: %u checks, %u failures\n",IB6Tests,IB6Failures);
    }
    return IB6Failures ? 1 : 0;
}
