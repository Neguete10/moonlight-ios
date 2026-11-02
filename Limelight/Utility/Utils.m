//
//  Utils.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "Utils.h"

#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netdb.h>

@implementation Utils
NSString *const deviceName = @"roth";

+ (NSData*) randomBytes:(NSInteger)length {
    char* bytes = malloc(length);
    arc4random_buf(bytes, length);
    NSData* randomData = [NSData dataWithBytes:bytes length:length];
    free(bytes);
    return randomData;
}

+ (NSData*) hexToBytes:(NSString*) hex {
    unsigned long len = [hex length];
    NSMutableData* data = [NSMutableData dataWithCapacity:len / 2];
    char byteChars[3] = {'\0','\0','\0'};
    unsigned long wholeByte;
    
    const char *chars = [hex UTF8String];
    int i = 0;
    while (i < len) {
        byteChars[0] = chars[i++];
        byteChars[1] = chars[i++];
        wholeByte = strtoul(byteChars, NULL, 16);
        [data appendBytes:&wholeByte length:1];
    }
    
    return data;
}

+ (NSString*) bytesToHex:(NSData*)data {
    const unsigned char* bytes = [data bytes];
    NSMutableString *hex = [[NSMutableString alloc] init];
    for (int i = 0; i < [data length]; i++) {
        [hex appendFormat:@"%02X" , bytes[i]];
    }
    return hex;
}

+ (BOOL)isActiveNetworkVPN {
    NSDictionary *dict = CFBridgingRelease(CFNetworkCopySystemProxySettings());
    NSArray *keys = [dict[@"__SCOPED__"] allKeys];
    for (NSString *key in keys) {
        if ([key containsString:@"tap"] ||
            [key containsString:@"tun"] ||
            [key containsString:@"ppp"] ||
            [key containsString:@"ipsec"]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)av1HardwareDecodeSupported {
    if (@available(iOS 16.0, tvOS 16.0, *)) {
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1);
    }
    return NO;
}

+ (BOOL)displaySupportsHDR10 {
    return (AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10) != 0;
}

#if !TARGET_OS_TV
+ (void) launchUrl:(NSString*)urlString {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString] options:@{} completionHandler:nil];
}
#endif

+ (void) addHelpOptionToDialog:(UIAlertController*)dialog {
    // Twilight does not attach a browser link. Callers still share this hook.
    (void)dialog;
}

+ (BOOL) parseAddressPortString:(NSString*)addressPort address:(NSRange*)address port:(NSRange*)port {
    if (![addressPort containsString:@":"]) {
        // If there's no port or IPv6 separator, the whole thing is an address
        *address = NSMakeRange(0, [addressPort length]);
        *port = NSMakeRange(NSNotFound, 0);
        return TRUE;
    }
    
    NSInteger locationOfOpeningBracket = [addressPort rangeOfString:@"["].location;
    NSInteger locationOfClosingBracket = [addressPort rangeOfString:@"]"].location;
    if (locationOfOpeningBracket != NSNotFound || locationOfClosingBracket != NSNotFound) {
        // If we have brackets, it's an IPv6 address
        if (locationOfOpeningBracket == NSNotFound || locationOfClosingBracket == NSNotFound ||
            locationOfClosingBracket < locationOfOpeningBracket) {
            // Invalid address format
            return FALSE;
        }
        
        // Cut at the brackets
        *address = NSMakeRange(locationOfOpeningBracket + 1, locationOfClosingBracket - locationOfOpeningBracket - 1);
    }
    else {
        // It's an IPv4 address, so just cut at the port separator
        *address = NSMakeRange(0, [addressPort rangeOfString:@":"].location);
    }
    
    NSUInteger remainingStringLocation = address->location + address->length;
    NSRange remainingStringRange = NSMakeRange(remainingStringLocation, [addressPort length] - remainingStringLocation);
    NSInteger locationOfPortSeparator = [addressPort rangeOfString:@":" options:0 range:remainingStringRange].location;
    if (locationOfPortSeparator != NSNotFound) {
        *port = NSMakeRange(locationOfPortSeparator + 1, [addressPort length] - locationOfPortSeparator - 1);
    }
    else {
        *port = NSMakeRange(NSNotFound, 0);
    }
    
    return TRUE;
}

+ (NSString*) addressPortStringToAddress:(NSString*)addressPort {
    NSRange addressRange, portRange;
    if (![self parseAddressPortString:addressPort address:&addressRange port:&portRange]) {
        return nil;
    }
    
    return [addressPort substringWithRange:addressRange];
}

+ (unsigned short) addressPortStringToPort:(NSString*)addressPort {
    NSRange addressRange, portRange;
    if (![self parseAddressPortString:addressPort address:&addressRange port:&portRange] || portRange.location == NSNotFound) {
        return 47989;
    }
    
    return [[addressPort substringWithRange:portRange] integerValue];
}

+ (NSString*) addressAndPortToAddressPortString:(NSString*)address port:(unsigned short)port {
    if ([address containsString:@":"]) {
        // IPv6 addresses require escaping
        return [NSString stringWithFormat:@"[%@]:%u", address, port];
    }
    else {
        return [NSString stringWithFormat:@"%@:%u", address, port];
    }
}

#if !TARGET_OS_TV
+ (UIInterfaceOrientationMask)twilightLibraryOrientations {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        return UIInterfaceOrientationMaskLandscape;
    }
    return UIInterfaceOrientationMaskAll;
}

+ (UIInterfaceOrientationMask)twilightStreamOrientations {
    return [self twilightLibraryOrientations];
}

+ (void)twilightRequestGeometryUpdateForViewController:(UIViewController *)viewController orientations:(UIInterfaceOrientationMask)orientations {
    if (viewController == nil) {
        return;
    }
    if (@available(iOS 16.0, *)) {
        UIViewController *cursor = viewController;
        while (cursor != nil) {
            [cursor setNeedsUpdateOfSupportedInterfaceOrientations];
            cursor = cursor.parentViewController;
        }
        UIWindowScene *scene = viewController.view.window.windowScene;
        if (scene == nil) {
            for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
                if ([candidate isKindOfClass:[UIWindowScene class]]) {
                    scene = (UIWindowScene *)candidate;
                    break;
                }
            }
        }
        if (scene == nil) {
            return;
        }
        UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:orientations];
        [scene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
            Log(LOG_W, @"Interface orientation update failed: %@", error);
        }];
        return;
    }

    // iOS 15 has no scene geometry update. Match the device when several
    // orientations are allowed, and pick a landscape side when only those are.
    UIDeviceOrientation device = UIDevice.currentDevice.orientation;
    UIInterfaceOrientation target = UIInterfaceOrientationPortrait;
    BOOL landscapeOnly = (orientations & UIInterfaceOrientationMaskPortrait) == 0;
    if (landscapeOnly) {
        target = device == UIDeviceOrientationLandscapeLeft ? UIInterfaceOrientationLandscapeRight : UIInterfaceOrientationLandscapeLeft;
    }
    else if (device == UIDeviceOrientationLandscapeLeft) {
        target = UIInterfaceOrientationLandscapeRight;
    }
    else if (device == UIDeviceOrientationLandscapeRight) {
        target = UIInterfaceOrientationLandscapeLeft;
    }
    [[UIDevice currentDevice] setValue:@(target) forKey:@"orientation"];
    [UIViewController attemptRotationToDeviceOrientation];
}
#endif

@end

@implementation NSString (NSStringWithTrim)

- (NSString *)trim {
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
