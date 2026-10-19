//
//  Utils.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@interface Utils : NSObject

typedef NS_ENUM(int, PairState) {
    PairStateUnknown,
    PairStateUnpaired,
    PairStatePaired
};

typedef NS_ENUM(int, State) {
    StateUnknown,
    StateOffline,
    StateOnline
};

FOUNDATION_EXPORT NSString *const deviceName;

+ (NSData*) randomBytes:(NSInteger)length;
+ (NSString*) bytesToHex:(NSData*)data;
+ (NSData*) hexToBytes:(NSString*) hex;
+ (void) addHelpOptionToDialog:(UIAlertController*)dialog;
+ (BOOL) isActiveNetworkVPN;
+ (BOOL) parseAddressPortString:(NSString*)addressPort address:(NSRange*)address port:(NSRange*)port;
+ (NSString*) addressPortStringToAddress:(NSString*)addressPort;
+ (unsigned short) addressPortStringToPort:(NSString*)addressPort;
+ (NSString*) addressAndPortToAddressPortString:(NSString*)address port:(unsigned short)port;

// Hardware AV1 decode (A17 Pro / M3 and later). Runtime check, not a device list.
+ (BOOL)av1HardwareDecodeSupported;

// The current display can present HDR10. Runtime check, not a device list.
+ (BOOL)displaySupportsHDR10;

#if !TARGET_OS_TV
+ (void) launchUrl:(NSString*)urlString;
#endif

@end

@interface NSString (NSStringWithTrim)

- (NSString*) trim;

@end
