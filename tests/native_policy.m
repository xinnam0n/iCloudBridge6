#import <Foundation/Foundation.h>
#import "IB6Policy.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

static NSUInteger Checks;
static void Check(BOOL condition, const char *label) {
    Checks++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", label);
        exit(1);
    }
}

static NSDictionary *AdaptConfig(void) {
    return @{@"Mode": @"adapt", @"NormalizeNumericDSID": @YES};
}

static NSData *Serialize(id plist, NSPropertyListFormat format) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
        format:format options:0 error:NULL];
    Check(data != nil, "fixture serializes");
    return data;
}

static id Parse(NSData *data) {
    return [NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListImmutable format:NULL error:NULL];
}

static NSMutableDictionary *Root(id dsid) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (dsid) [info setObject:dsid forKey:@"dsid"];
    return [@{@"status": @0,
              @"appleAccountInfo": info,
              @"tokens": @{@"mmeAuthToken": @"fixture-only-token"},
              @"dataclasses": @{@"com.apple.Dataclass.Calendars": @NO}}
            mutableCopy];
}

static void ExpectNoChange(NSData *data, NSString *endpoint, NSInteger status,
                           NSDictionary *config, const char *label) {
    BOOL changed = YES;
    NSString *reason = nil;
    NSData *output = IB6AdaptResponse(data, endpoint, status, config, &changed, &reason);
    Check(output == data, label);
    Check(!changed, "no-op reports unchanged");
    Check([reason length] > 0, "no-op has fixed reason");
}

static void TestEndpoints(void) {
    NSDictionary *valid = @{
        @"https://setup.icloud.com/setup/get_account_settings": @"settings",
        @"https://setup.icloud.com/setup/iosbuddy/loginDelegates": @"delegates",
        @"https://setup.icloud.com:443/setup/login_or_create_account": @"login",
        @"https://gsa.apple.com/grandslam/GsService2": @"gsa"
    };
    for (NSString *url in valid)
        Check([IB6EndpointForURL([NSURL URLWithString:url]) isEqual:valid[url]],
              "exact endpoint classified");
    NSArray *invalid = @[
        @"http://setup.icloud.com/setup/get_account_settings",
        @"https://setup.icloud.com.evil.invalid/setup/get_account_settings",
        @"https://setup.icloud.com/setup/get_account_settings/",
        @"https://setup.icloud.com/setup/get_account_settings;parameter",
        @"https://setup.icloud.com/setup/%67et_account_settings",
        @"https://setup.icloud.com/setup/./get_account_settings",
        @"https://setup.icloud.com:444/setup/get_account_settings",
        @"https://user:pass@setup.icloud.com/setup/get_account_settings",
        @"https://setup.icloud.com/setup/other",
        @"https://gsa.apple.com/grandslam/Other"
    ];
    for (NSString *url in invalid)
        Check(IB6EndpointForURL([NSURL URLWithString:url]) == nil, "other endpoint rejected");
    Check(IB6EndpointForURL(nil) == nil, "nil endpoint rejected");
}

static void TestPrivacy(void) {
    NSString *secret = @"NEVER_ECHO_THIS_KEY_OR_VALUE_347129831";
    NSDictionary *fixture = @{
        secret: secret,
        @"status": secret,
        @"hsc": @YES,
        @"ec": @1.25,
        @"appleAccountInfo": @{@"dsid": secret, @"appleId": secret},
        @"tokens": @{secret: secret, @"mmeAuthToken": secret},
        @"Response": @{@"Status": @{@"hsc": @200, @"ec": @(-22406)},
                       @"M2": secret, @"spd": secret, @"np": secret},
        @"delegates": @{@"com.apple.mobileme": @{@"status": @0,
            @"tokens": @{secret: secret}, @"appleAccountInfo": @{@"dsid": secret}}}
    };
    NSDictionary *summary = IB6SummarizePlist(fixture);
    Check([[summary description] rangeOfString:secret].location == NSNotFound,
          "summary never echoes untrusted keys or values");
    Check([summary count] == 21, "summary has fixed number of keys");
    Check([summary[@"root_status"] isEqual:@"invalid"], "string status rejected");
    Check([summary[@"root_hsc"] isEqual:@"invalid"], "boolean hsc rejected");
    Check([summary[@"root_ec"] isEqual:@"invalid"], "floating ec rejected");
    Check([summary[@"gsa_hsc"] isEqual:@200], "integer hsc retained");
    Check([summary[@"gsa_ec"] isEqual:@(-22406)], "integer error retained");
    Check([summary[@"root_token_count"] isEqual:@2], "only token count retained");
    Check([summary[@"mobileme_token_count"] isEqual:@1], "delegate token count retained");
    Check([summary[@"has_M2"] boolValue] && [summary[@"has_spd"] boolValue] &&
          [summary[@"has_np"] boolValue], "complete field presence retained");
    Check([IB6SummarizePlist(@[secret])[@"root_dictionary"] isEqual:@NO],
          "non-dictionary summary safe");
    Check([IB6SummarizePlist(@{@"hsc": @999})[@"root_hsc"] isEqual:@"invalid"],
          "out-of-range hsc rejected");
    Check([IB6SummarizePlist(@{@"ec": @(ULLONG_MAX)})[@"root_ec"] isEqual:@"invalid"],
          "out-of-range error rejected");
}

static void TestResponseGuard(void) {
    for (id identity in @[@1234, @"1234", @(LLONG_MAX), @"9223372036854775807"]) {
        NSData *data = Serialize(Root(identity), NSPropertyListBinaryFormat_v1_0);
        Check(IB6ResponseCanAdapt(data, @"settings", 200), "valid identity passes response guard");
        Check(!IB6ResponseCanAdapt(data, @"settings", 403), "HTTP error fails response guard");
        Check(!IB6ResponseCanAdapt(data, @"gsa", 200), "GSA fails response guard");
    }
    for (id identity in @[@YES, @NO, @0, @(-1), @1.0, @(ULLONG_MAX), @"", @"0",
                          @"00123", @"-1", @"+1", @"1.0", @" 123", @"123 ",
                          @"9223372036854775808", @"12345678901234567890", @"１２３"]) {
        Check(!IB6ResponseCanAdapt(Serialize(Root(identity), NSPropertyListBinaryFormat_v1_0),
                                  @"settings", 200), "invalid identity fails response guard");
    }
    for (id status in @[@1, @YES, @0.0, @"0"]) {
        NSMutableDictionary *root = Root(@1234);
        root[@"status"] = status;
        Check(!IB6ResponseCanAdapt(Serialize(root, NSPropertyListXMLFormat_v1_0),
                                  @"settings", 200), "invalid application status fails guard");
    }
    NSMutableDictionary *scope = Root(@"1234");
    Check(IB6ResponseCanAdapt(Serialize(@{@"status": @0,
        @"delegates": @{@"com.apple.mobileme": scope}}, NSPropertyListBinaryFormat_v1_0),
        @"delegates", 200), "valid delegate scope passes guard");
    [scope removeObjectForKey:@"status"];
    Check(!IB6ResponseCanAdapt(Serialize(@{@"status": @0,
        @"delegates": @{@"com.apple.mobileme": scope}}, NSPropertyListBinaryFormat_v1_0),
        @"delegates", 200), "missing delegate status fails guard");
    Check(!IB6ResponseCanAdapt([@"malformed" dataUsingEncoding:NSUTF8StringEncoding],
                              @"settings", 200), "malformed plist fails guard");
    Check(!IB6ResponseCanAdapt([NSMutableData dataWithLength:2 * 1024 * 1024 + 1],
                              @"settings", 200), "oversize data fails guard");
}

static void TestBoundaries(void) {
    NSDictionary *config = AdaptConfig();
    NSData *data = Serialize(Root(@123456789012345LL), NSPropertyListXMLFormat_v1_0);
    ExpectNoChange(data, @"settings", 200, nil, "observe is default");
    ExpectNoChange(data, @"settings", 200, @{@"Mode": @"observe", @"NormalizeNumericDSID": @YES},
                   "observe cannot mutate");
    ExpectNoChange(data, @"settings", 200, @{@"Mode": @"adapt"}, "opt-in flag required");
    ExpectNoChange(data, @"settings", 200, @{@"Mode": @"adapt", @"NormalizeNumericDSID": @"true"},
                   "string flag cannot enable writes");
    ExpectNoChange(data, @"settings", 200, @{@"Mode": @"adapt", @"NormalizeNumericDSID": @1},
                   "numeric flag cannot enable writes");
    ExpectNoChange(data, @"gsa", 200, config, "GSA never adapted");
    ExpectNoChange(data, @"other", 200, config, "unknown endpoint never adapted");
    ExpectNoChange(data, @"settings", 401, config, "HTTP failure preserved");
    ExpectNoChange(data, @"settings", 300, config, "redirect preserved");
    ExpectNoChange([@"not a plist" dataUsingEncoding:NSUTF8StringEncoding],
                   @"settings", 200, config, "malformed plist preserved");
    ExpectNoChange(Serialize(@[@1], NSPropertyListBinaryFormat_v1_0),
                   @"settings", 200, config, "array root preserved");
    ExpectNoChange([NSMutableData dataWithLength:2 * 1024 * 1024 + 1],
                   @"settings", 200, config, "oversize data preserved");
    ExpectNoChange(nil, @"settings", 200, config, "nil data preserved");
    for (id status in @[@1, @(-22406), @YES, @0.0, @"0", @[], @{}]) {
        NSMutableDictionary *fixture = Root(@1234);
        fixture[@"status"] = status;
        ExpectNoChange(Serialize(fixture, NSPropertyListXMLFormat_v1_0),
                       @"settings", 200, config, "application failure or malformed status preserved");
    }
    NSMutableDictionary *missingTokens = Root(@1234);
    [missingTokens removeObjectForKey:@"tokens"];
    ExpectNoChange(Serialize(missingTokens, NSPropertyListXMLFormat_v1_0),
                   @"settings", 200, config, "missing tokens preserved");
    for (id badTokens in @[@{}, @[], @"token"]) {
        NSMutableDictionary *fixture = Root(@1234);
        fixture[@"tokens"] = badTokens;
        ExpectNoChange(Serialize(fixture, NSPropertyListXMLFormat_v1_0),
                       @"settings", 200, config, "invalid tokens preserved");
    }
    for (id identity in @[@"1234", @YES, @NO, @1.5, @0.0, @0, @(-1),
                         @(ULLONG_MAX), [NSNumber numberWithDouble:1.0]]) {
        ExpectNoChange(Serialize(Root(identity), NSPropertyListBinaryFormat_v1_0),
                       @"settings", 200, config, "unsafe or already-string DSID unchanged");
    }
    ExpectNoChange(Serialize(Root(nil), NSPropertyListXMLFormat_v1_0),
                   @"settings", 200, config, "missing DSID not invented");
}

static void TestSingleAdaptation(void) {
    for (NSString *endpoint in @[@"settings", @"login", @"delegates"]) {
        for (NSNumber *formatNumber in @[@(NSPropertyListXMLFormat_v1_0),
                                         @(NSPropertyListBinaryFormat_v1_0)]) {
            NSPropertyListFormat format = [formatNumber unsignedIntegerValue];
            NSDictionary *scope = Root(@123456789012345LL);
            NSDictionary *fixture = scope;
            if ([endpoint isEqualToString:@"delegates"]) {
                fixture = @{@"status": @0, @"appleAccountInfo": @{@"dsid": @777},
                    @"tokens": @{@"root-token": @"unchanged"},
                    @"delegates": @{@"com.apple.mobileme": scope,
                                     @"other.delegate": Root(@888)}};
            }
            NSData *data = Serialize(fixture, format);
            BOOL changed = NO;
            NSString *reason = nil;
            NSData *output = IB6AdaptResponse(data, endpoint, 200, AdaptConfig(), &changed, &reason);
            Check(changed && output != data, "opt-in changes safe numeric DSID");
            Check([reason isEqual:@"numeric_dsid_normalized"], "fixed adaptation reason");
            NSMutableDictionary *expected = [fixture mutableCopy];
            NSMutableDictionary *expectedScope = [scope mutableCopy];
            NSMutableDictionary *expectedInfo = [scope[@"appleAccountInfo"] mutableCopy];
            expectedInfo[@"dsid"] = @"123456789012345";
            expectedScope[@"appleAccountInfo"] = expectedInfo;
            if ([endpoint isEqualToString:@"delegates"]) {
                NSMutableDictionary *expectedDelegates = [fixture[@"delegates"] mutableCopy];
                expectedDelegates[@"com.apple.mobileme"] = expectedScope;
                expected[@"delegates"] = expectedDelegates;
            } else expected = expectedScope;
            Check([Parse(output) isEqual:expected], "exactly one value changes; tokens/dataclasses unchanged");
            Check([Parse(data) isEqual:fixture], "input bytes and source objects untouched");
            NSPropertyListFormat outputFormat = 0;
            [NSPropertyListSerialization propertyListWithData:output options:0
                format:&outputFormat error:NULL];
            Check(outputFormat == format, "plist format preserved");
            ExpectNoChange(output, endpoint, 200, AdaptConfig(), "adaptation idempotent");
        }
    }
    for (id status in @[@1, @YES, @0.0, @"0"]) {
        NSMutableDictionary *scope = Root(@1234);
        scope[@"status"] = status;
        NSDictionary *fixture = @{@"status": @0,
            @"delegates": @{@"com.apple.mobileme": scope}};
        ExpectNoChange(Serialize(fixture, NSPropertyListXMLFormat_v1_0), @"delegates", 200,
                       AdaptConfig(), "delegate failure or malformed status preserved");
    }
    NSMutableDictionary *scope = Root(@1234);
    [scope removeObjectForKey:@"status"];
    ExpectNoChange(Serialize(@{@"status": @0, @"delegates": @{@"com.apple.mobileme": scope}},
                            NSPropertyListXMLFormat_v1_0),
                   @"delegates", 200, AdaptConfig(), "delegate status required");
    ExpectNoChange(Serialize(@{@"delegates": @{@"com.apple.mobileme": Root(@1234)}},
                            NSPropertyListXMLFormat_v1_0),
                   @"delegates", 200, AdaptConfig(), "root delegate status required");
    NSMutableDictionary *noRootStatus = Root(@1234);
    [noRootStatus removeObjectForKey:@"status"];
    BOOL changed = NO;
    IB6AdaptResponse(Serialize(noRootStatus, NSPropertyListXMLFormat_v1_0), @"settings",
                     200, AdaptConfig(), &changed, NULL);
    Check(changed, "settings permits absent root status with all other guards");
}

static void TestFailureMarkers(void) {
    NSArray *markers = @[@{@"ec": @(-22406)}, @{@"hsc": @401},
        @{@"Status": @{@"ec": @(-22406), @"hsc": @401}},
        @{@"Status": @"malformed"}, @{@"error": @"fixture-only"},
        @{@"errorCode": @0}, @{@"errors": @[]}, @{@"errorMessage": @""}];
    for (NSDictionary *marker in markers) {
        NSMutableDictionary *root = Root(@1234);
        [root addEntriesFromDictionary:marker];
        NSData *data = Serialize(root,NSPropertyListXMLFormat_v1_0);
        Check(!IB6ResponseCanAdapt(data,@"login",200),"explicit failure markers block metadata changes");
        ExpectNoChange(data,@"login",200,AdaptConfig(),"failure marker preserves exact original bytes");
    }
}

int main(void) {
    @autoreleasepool {
        TestEndpoints();
        TestPrivacy();
        TestResponseGuard();
        TestBoundaries();
        TestSingleAdaptation();
        TestFailureMarkers();
        printf("PASS: %lu native policy checks\n", (unsigned long)Checks);
    }
    return 0;
}
