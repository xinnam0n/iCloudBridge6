#import <Foundation/Foundation.h>

/* All policy functions are side-effect free. No Keychain or Accounts writes. */
FOUNDATION_EXPORT NSString *IB6EndpointForURL(NSURL *url);

/* Fixed keys only; never includes payload keys, identifiers, tokens or text. */
FOUNDATION_EXPORT NSDictionary *IB6SummarizePlist(id plist);

/* Success/schema guard for opt-in in-memory adaptations. No writes. */
FOUNDATION_EXPORT BOOL IB6ResponseCanAdapt(NSData *data,
                                         NSString *endpoint,
                                         NSInteger httpStatus);

/*
 * A no-op or rejected response returns the original NSData object unchanged.
 * The only permitted adaptation is an existing, positive integral numeric DSID
 * to its identical decimal string, inside the successful endpoint's own scope.
 * Config: Mode = "adapt" and NormalizeNumericDSID = true are both required.
 * changed and reason are optional; reason is always a fixed diagnostic code.
 */
FOUNDATION_EXPORT NSData *IB6AdaptResponse(NSData *data,
                                        NSString *endpoint,
                                        NSInteger httpStatus,
                                        NSDictionary *config,
                                        BOOL *changed,
                                        NSString **reason);
