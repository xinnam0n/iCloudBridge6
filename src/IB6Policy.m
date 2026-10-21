#import "IB6Policy.h"
#import <CoreFoundation/CoreFoundation.h>
#include <limits.h>
#include <string.h>

static const NSUInteger IB6MaximumResponseBytes = 2 * 1024 * 1024;

static BOOL IB6IsBoolean(id value) {
    return [value isKindOfClass:[NSNumber class]] &&
           CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

/* No floating conversion: it could round a large DSID or coerce a boolean. */
static BOOL IB6Integer(id value, long long *result) {
    if (![value isKindOfClass:[NSNumber class]] || IB6IsBoolean(value)) return NO;
    if (CFGetTypeID((__bridge CFTypeRef)value) != CFNumberGetTypeID() ||
        CFNumberIsFloatType((__bridge CFNumberRef)value)) return NO;
    const char *type = [value objCType];
    if (!type || type[0] == '\0' || type[1] != '\0') return NO;
    if (strchr("csilq", type[0])) {
        if (result) *result = [value longLongValue];
        return YES;
    }
    if (strchr("CSILQ", type[0])) {
        unsigned long long unsignedValue = [value unsignedLongLongValue];
        if (unsignedValue > (unsigned long long)LLONG_MAX) return NO;
        if (result) *result = (long long)unsignedValue;
        return YES;
    }
    return NO;
}

static NSDictionary *IB6Dictionary(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static id IB6StatusSummary(id value, BOOL httpCode) {
    if (!value) return @"absent";
    long long code = 0;
    if (!IB6Integer(value, &code) || code < INT_MIN || code > INT_MAX)
        return @"invalid";
    if (httpCode && (code < 100 || code > 599)) return @"invalid";
    return [NSNumber numberWithLongLong:code];
}

static NSNumber *IB6TokenCount(NSDictionary *scope) {
    NSDictionary *tokens = IB6Dictionary([scope objectForKey:@"tokens"]);
    /* Cap a summary count; no key or token value is inspected or returned. */
    return [NSNumber numberWithUnsignedInteger:MIN([tokens count], (NSUInteger)65535)];
}

NSString *IB6EndpointForURL(NSURL *url) {
    if (![url isKindOfClass:[NSURL class]] ||
        ![[[url scheme] lowercaseString] isEqualToString:@"https"] ||
        [url user] || [url password]) return nil;
    NSNumber *port = [url port];
    if (port && [port integerValue] != 443) return nil;
    NSString *host = [[url host] lowercaseString];
    NSString *path = [url path];
    /* Reject encoded aliases, dot normalization and path parameters. */
    NSString *absolute = [[url absoluteURL] absoluteString];
    NSRange schemeEnd = [absolute rangeOfString:@"://"];
    if (schemeEnd.location == NSNotFound) return nil;
    NSUInteger authorityStart = NSMaxRange(schemeEnd);
    NSRange rawStart = [absolute rangeOfString:@"/" options:0
        range:NSMakeRange(authorityStart, [absolute length] - authorityStart)];
    if (rawStart.location == NSNotFound) return nil;
    NSRange end = [absolute rangeOfCharacterFromSet:
        [NSCharacterSet characterSetWithCharactersInString:@"?#"] options:0
        range:NSMakeRange(rawStart.location, [absolute length] - rawStart.location)];
    NSUInteger rawEnd = end.location == NSNotFound ? [absolute length] : end.location;
    NSString *rawPath = [absolute substringWithRange:
        NSMakeRange(rawStart.location, rawEnd - rawStart.location)];
    if (![rawPath isEqualToString:path]) return nil;
    if ([host isEqualToString:@"setup.icloud.com"]) {
        if ([path isEqualToString:@"/setup/get_account_settings"]) return @"settings";
        if ([path isEqualToString:@"/setup/iosbuddy/loginDelegates"]) return @"delegates";
        if ([path isEqualToString:@"/setup/login_or_create_account"]) return @"login";
    }
    if ([host isEqualToString:@"gsa.apple.com"] &&
        [path isEqualToString:@"/grandslam/GsService2"]) return @"gsa";
    return nil;
}

NSDictionary *IB6SummarizePlist(id plist) {
    NSDictionary *root = IB6Dictionary(plist);
    NSDictionary *delegates = IB6Dictionary([root objectForKey:@"delegates"]);
    NSDictionary *mobileme = IB6Dictionary([delegates objectForKey:@"com.apple.mobileme"]);
    NSDictionary *rootInfo = IB6Dictionary([root objectForKey:@"appleAccountInfo"]);
    NSDictionary *delegateInfo = IB6Dictionary([mobileme objectForKey:@"appleAccountInfo"]);
    NSDictionary *response = IB6Dictionary([root objectForKey:@"Response"]);
    NSDictionary *proof = response ?: root;
    NSDictionary *status = IB6Dictionary([response objectForKey:@"Status"]);
    if (!status) status = IB6Dictionary([root objectForKey:@"Status"]);
    return @{
        @"root_dictionary": [NSNumber numberWithBool:root != nil],
        @"root_status": IB6StatusSummary([root objectForKey:@"status"], NO),
        @"root_hsc": IB6StatusSummary([root objectForKey:@"hsc"], YES),
        @"root_ec": IB6StatusSummary([root objectForKey:@"ec"], NO),
        @"gsa_hsc": IB6StatusSummary([status objectForKey:@"hsc"], YES),
        @"gsa_ec": IB6StatusSummary([status objectForKey:@"ec"], NO),
        @"mobileme_status": IB6StatusSummary([mobileme objectForKey:@"status"], NO),
        @"root_token_count": IB6TokenCount(root),
        @"mobileme_token_count": IB6TokenCount(mobileme),
        @"root_identity_present": [NSNumber numberWithBool:rootInfo != nil],
        @"root_dsid_present": [NSNumber numberWithBool:[rootInfo objectForKey:@"dsid"] != nil],
        @"mobileme_identity_present": [NSNumber numberWithBool:delegateInfo != nil],
        @"mobileme_dsid_present": [NSNumber numberWithBool:[delegateInfo objectForKey:@"dsid"] != nil],
        @"has_s": [NSNumber numberWithBool:[proof objectForKey:@"s"] != nil],
        @"has_B": [NSNumber numberWithBool:[proof objectForKey:@"B"] != nil],
        @"has_i": [NSNumber numberWithBool:[proof objectForKey:@"i"] != nil],
        @"has_sp": [NSNumber numberWithBool:[proof objectForKey:@"sp"] != nil],
        @"has_c": [NSNumber numberWithBool:[proof objectForKey:@"c"] != nil],
        @"has_M2": [NSNumber numberWithBool:[proof objectForKey:@"M2"] != nil],
        @"has_spd": [NSNumber numberWithBool:[proof objectForKey:@"spd"] != nil],
        @"has_np": [NSNumber numberWithBool:[proof objectForKey:@"np"] != nil]
    };
}

static NSData *IB6Unchanged(NSData *data, NSString **reason, NSString *code) {
    if (reason) *reason = code;
    return data;
}

static BOOL IB6SuccessfulStatus(id value) {
    long long code = 0;
    return IB6Integer(value, &code) && code == 0;
}

/* Error-shaped replies are never candidates, even if stale tokens accompany them. */
static BOOL IB6NoFailureMarkers(NSDictionary *scope) {
    for (NSString *key in @[@"error", @"errors", @"errorCode", @"error-code", @"errorMessage"])
        if ([scope objectForKey:key]) return NO;
    id ec = [scope objectForKey:@"ec"], hsc = [scope objectForKey:@"hsc"];
    long long value = 0;
    if (ec && (!IB6Integer(ec,&value) || value != 0)) return NO;
    if (hsc && (!IB6Integer(hsc,&value) || value < 200 || value > 299)) return NO;
    id status = [scope objectForKey:@"Status"];
    if (status) {
        NSDictionary *dictionary = IB6Dictionary(status);
        if (!dictionary) return NO;
        // One known protocol envelope, no unbounded recursive dictionary walk.
        for (NSString *key in @[@"error", @"errors", @"errorCode", @"error-code", @"errorMessage", @"Status"])
            if ([dictionary objectForKey:key]) return NO;
        id nestedEC = [dictionary objectForKey:@"ec"], nestedHSC = [dictionary objectForKey:@"hsc"];
        if (nestedEC && (!IB6Integer(nestedEC,&value) || value != 0)) return NO;
        if (nestedHSC && (!IB6Integer(nestedHSC,&value) || value < 200 || value > 299)) return NO;
    }
    return YES;
}

/* A canonical positive decimal identity, bounded to the same signed range. */
static BOOL IB6PositiveIdentity(id value) {
    long long integer = 0;
    if (IB6Integer(value, &integer)) return integer > 0;
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *string = value;
    if ([string length] == 0 || [string length] > 19 || [string characterAtIndex:0] == '0')
        return NO;
    unsigned long long identity = 0;
    for (NSUInteger index = 0; index < [string length]; index++) {
        unichar character = [string characterAtIndex:index];
        if (character < '0' || character > '9') return NO;
        unsigned long long digit = character - '0';
        if (identity > ((unsigned long long)LLONG_MAX - digit) / 10) return NO;
        identity = identity * 10 + digit;
    }
    return identity > 0;
}

BOOL IB6ResponseCanAdapt(NSData *data, NSString *endpoint, NSInteger httpStatus) {
    BOOL delegatesEndpoint = [endpoint isEqualToString:@"delegates"];
    if (!delegatesEndpoint && ![endpoint isEqualToString:@"settings"] &&
        ![endpoint isEqualToString:@"login"]) return NO;
    if (![data isKindOfClass:[NSData class]] || [data length] > IB6MaximumResponseBytes ||
        httpStatus < 200 || httpStatus > 299) return NO;
    NSDictionary *root = IB6Dictionary([NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListImmutable format:NULL error:NULL]);
    if (!root || !IB6NoFailureMarkers(root)) return NO;
    id rootStatus = [root objectForKey:@"status"];
    if ((delegatesEndpoint && !rootStatus) ||
        (rootStatus && !IB6SuccessfulStatus(rootStatus))) return NO;
    NSDictionary *scope = root;
    if (delegatesEndpoint) {
        NSDictionary *delegates = IB6Dictionary([root objectForKey:@"delegates"]);
        scope = IB6Dictionary([delegates objectForKey:@"com.apple.mobileme"]);
        if (!scope || !IB6SuccessfulStatus([scope objectForKey:@"status"])) return NO;
    }
    NSDictionary *tokens = IB6Dictionary([scope objectForKey:@"tokens"]);
    NSDictionary *info = IB6Dictionary([scope objectForKey:@"appleAccountInfo"]);
    return IB6NoFailureMarkers(scope) && [tokens count] > 0 && info && IB6PositiveIdentity([info objectForKey:@"dsid"]);
}

NSData *IB6AdaptResponse(NSData *data, NSString *endpoint, NSInteger httpStatus,
                        NSDictionary *config, BOOL *changed, NSString **reason) {
    if (changed) *changed = NO;
    if (reason) *reason = @"unchanged";
    NSDictionary *options = IB6Dictionary(config);
    id mode = [options objectForKey:@"Mode"];
    if (![mode isKindOfClass:[NSString class]] || ![mode isEqualToString:@"adapt"])
        return IB6Unchanged(data, reason, @"observe");
    id enabled = [options objectForKey:@"NormalizeNumericDSID"];
    if (!IB6IsBoolean(enabled) || ![enabled boolValue])
        return IB6Unchanged(data, reason, @"normalization_disabled");
    BOOL delegatesEndpoint = [endpoint isEqualToString:@"delegates"];
    if (!delegatesEndpoint && ![endpoint isEqualToString:@"settings"] &&
        ![endpoint isEqualToString:@"login"])
        return IB6Unchanged(data, reason, @"endpoint_not_adaptable");
    if (![data isKindOfClass:[NSData class]])
        return IB6Unchanged(data, reason, @"invalid_data");
    if ([data length] > IB6MaximumResponseBytes)
        return IB6Unchanged(data, reason, @"response_too_large");
    if (httpStatus < 200 || httpStatus > 299)
        return IB6Unchanged(data, reason, @"http_error");

    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
    id parsed = [NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListMutableContainersAndLeaves format:&format error:NULL];
    NSDictionary *root = IB6Dictionary(parsed);
    if (!root) return IB6Unchanged(data, reason, @"invalid_plist_root");
    id rootStatus = [root objectForKey:@"status"];
    if ((delegatesEndpoint && !rootStatus) ||
        (rootStatus && !IB6SuccessfulStatus(rootStatus)))
        return IB6Unchanged(data, reason, @"root_status_not_success");

    NSDictionary *scope = root;
    if (delegatesEndpoint) {
        NSDictionary *delegates = IB6Dictionary([root objectForKey:@"delegates"]);
        scope = IB6Dictionary([delegates objectForKey:@"com.apple.mobileme"]);
        if (!scope || !IB6SuccessfulStatus([scope objectForKey:@"status"]))
            return IB6Unchanged(data, reason, @"mobileme_status_not_success");
    }
    NSDictionary *tokens = IB6Dictionary([scope objectForKey:@"tokens"]);
    if (![tokens count]) return IB6Unchanged(data, reason, @"missing_tokens");
    NSDictionary *info = IB6Dictionary([scope objectForKey:@"appleAccountInfo"]);
    if (!info) return IB6Unchanged(data, reason, @"missing_identity");
    /* The proxy uses this exact guard before any optional response-URL repair. */
    if (!IB6ResponseCanAdapt(data, endpoint, httpStatus))
        return IB6Unchanged(data, reason, @"response_guard_failed");
    id dsid = [info objectForKey:@"dsid"];
    if ([dsid isKindOfClass:[NSString class]])
        return IB6Unchanged(data, reason, @"dsid_already_string");
    long long identity = 0;
    if (!IB6Integer(dsid, &identity) || identity <= 0)
        return IB6Unchanged(data, reason, @"dsid_not_positive_integer");

    /* One field, in one existing scope. Native AppleAccount owns provisioning. */
    NSMutableDictionary *newInfo = [info mutableCopy];
    [newInfo setObject:[NSString stringWithFormat:@"%lld", identity] forKey:@"dsid"];
    NSMutableDictionary *newScope = [scope mutableCopy];
    [newScope setObject:newInfo forKey:@"appleAccountInfo"];
    NSMutableDictionary *newRoot = [root mutableCopy];
    if (delegatesEndpoint) {
        NSMutableDictionary *newDelegates = [[root objectForKey:@"delegates"] mutableCopy];
        [newDelegates setObject:newScope forKey:@"com.apple.mobileme"];
        [newRoot setObject:newDelegates forKey:@"delegates"];
    } else {
        newRoot = newScope;
    }
    NSData *output = [NSPropertyListSerialization dataWithPropertyList:newRoot
        format:format options:0 error:NULL];
    if (!output || [output length] > IB6MaximumResponseBytes)
        return IB6Unchanged(data, reason, @"serialization_failed");
    if (changed) *changed = YES;
    if (reason) *reason = @"numeric_dsid_normalized";
    return output;
}
