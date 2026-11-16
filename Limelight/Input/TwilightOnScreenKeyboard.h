//
//  TwilightOnScreenKeyboard.h
//  Moonlight
//
//  The three-finger keyboard accessory from upstream Moonlight:
//  system keyboard, plus Done, Win, Esc, Tab, Shift, Ctrl, Alt, and Delete.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TwilightOnScreenKey : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *imageName;
@property (nonatomic) short keyCode;
@property (nonatomic) BOOL toggle;
@property (nonatomic) BOOL plainBackground;

@end

@interface TwilightOnScreenKeyboard : NSObject

/// Upstream toolbar, in the order Moonlight shows them.
+ (NSArray<TwilightOnScreenKey *> *)toolbarKeys;

/// Width the accessory should claim. Uses the window's long side on a phone
/// whose bounds are still portrait, so the bar matches the landscape keyboard.
+ (CGFloat)accessoryWidthForView:(UIView *)view;

+ (UIToolbar *)toolbarWithWidth:(CGFloat)width target:(id)target action:(SEL)action;

@end

NS_ASSUME_NONNULL_END
