//
//  KeyboardSupport.h
//  Moonlight
//
//  Created by Diego Waxemberg on 8/25/18.
//  Copyright © 2018 Moonlight Game Streaming Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface KeyboardSupport : NSObject

struct KeyEvent {
    u_short keycode;
    u_short modifierKeycode;
    u_char modifier;
};

+ (BOOL)sendKeyEventForPress:(UIPress*)press down:(BOOL)down API_AVAILABLE(ios(13.4));
+ (BOOL)sendKeyEvent:(UIKey*)key down:(BOOL)down API_AVAILABLE(ios(13.4));
/// Win32 VK_* for a UIKeyboardHIDUsage value. Returns 0 when the usage is not mapped.
/// Keypad Enter also sets MODIFIER_EXTENDED on extendedModifier when that pointer is non-NULL.
+ (short)virtualKeyCodeForHIDUsage:(NSUInteger)usage extendedModifier:(char *_Nullable)extendedModifier API_AVAILABLE(ios(13.4));
+ (struct KeyEvent) translateKeyEvent:(unichar) inputChar withModifierFlags:(UIKeyModifierFlags)modifierFlags;

@end
