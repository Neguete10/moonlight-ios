//
//  TwilightOnScreenKeyboard.m
//  Moonlight
//

#import "TwilightOnScreenKeyboard.h"
#import <objc/runtime.h>

@implementation TwilightOnScreenKey
@end

@implementation TwilightOnScreenKeyboard

+ (TwilightOnScreenKey *)keyNamed:(NSString *)name
                        identifier:(NSString *)identifier
                             image:(NSString *)image
                           keyCode:(short)keyCode
                            toggle:(BOOL)toggle
                              plain:(BOOL)plain {
    TwilightOnScreenKey *key = [[TwilightOnScreenKey alloc] init];
    key.name = name;
    key.identifier = identifier;
    key.imageName = image;
    key.keyCode = keyCode;
    key.toggle = toggle;
    key.plainBackground = plain;
    return key;
}

+ (NSArray<TwilightOnScreenKey *> *)toolbarKeys {
    // Same keys, codes, and order as upstream StreamView: Done, Win, Esc,
    // Tab, Shift, Ctrl, Alt, Delete. Arrows and function keys stay on the
    // hardware / UIKey path in KeyboardSupport, as they do upstream.
    return @[
        [self keyNamed:@"Done" identifier:@"twilight.key.done" image:@"DoneIcon" keyCode:0x00 toggle:NO plain:YES],
        [self keyNamed:@"Win" identifier:@"twilight.key.win" image:@"WindowsIcon" keyCode:0x5B toggle:YES plain:NO],
        [self keyNamed:@"Esc" identifier:@"twilight.key.esc" image:@"EscapeIcon" keyCode:0x1B toggle:NO plain:NO],
        [self keyNamed:@"Tab" identifier:@"twilight.key.tab" image:@"TabIcon" keyCode:0x09 toggle:NO plain:NO],
        [self keyNamed:@"Shift" identifier:@"twilight.key.shift" image:@"ShiftIcon" keyCode:0xA0 toggle:YES plain:NO],
        [self keyNamed:@"Ctrl" identifier:@"twilight.key.ctrl" image:@"ControlIcon" keyCode:0xA2 toggle:YES plain:NO],
        [self keyNamed:@"Alt" identifier:@"twilight.key.alt" image:@"AltIcon" keyCode:0xA4 toggle:YES plain:NO],
        [self keyNamed:@"Del" identifier:@"twilight.key.del" image:@"DeleteIcon" keyCode:0x2E toggle:NO plain:NO],
    ];
}

+ (CGFloat)accessoryWidthForView:(UIView *)view {
    CGSize windowSize = view.window != nil ? view.window.bounds.size : CGSizeZero;
    CGSize viewSize = view.bounds.size;
    CGFloat width = windowSize.width > 1.0 ? windowSize.width : viewSize.width;
    BOOL phone = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone;
    // UIWindow.bounds can still be portrait for a frame after a landscape-only
    // phone is asked to rotate. The landscape keyboard spans the long side.
    if (phone && windowSize.height > windowSize.width && windowSize.height > 1.0) {
        width = windowSize.height;
    }
    else if (phone && viewSize.height > viewSize.width && viewSize.height > width) {
        width = viewSize.height;
    }
    return MAX(width, 320.0);
}

+ (UIImage *)imageForKey:(TwilightOnScreenKey *)key {
    UIImage *image = [UIImage imageNamed:key.imageName];
    if (image == nil) {
        // Upstream asked for the name with a .png suffix. Asset catalogs are
        // registered without it, so try both.
        image = [UIImage imageNamed:[key.imageName stringByAppendingPathExtension:@"png"]];
    }
    return image;
}

+ (UIBarButtonItem *)buttonForKey:(TwilightOnScreenKey *)key target:(id)target action:(SEL)action {
    UIImage *image = [self imageForKey:key];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.accessibilityIdentifier = key.identifier;
    button.accessibilityLabel = key.name;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintEqualToConstant:36.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:32.0].active = YES;
    if (image != nil) {
        [button setImage:image forState:UIControlStateNormal];
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        button.imageEdgeInsets = UIEdgeInsetsMake(5, 5, 5, 5);
    }
    else {
        // A missing catalog image used to leave an empty 30pt chip, which
        // reads as a missing key. The title is the upstream key name.
        [button setTitle:key.name forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.6;
    }
    UIColor *background = key.plainBackground ? [UIColor clearColor] : [UIColor blackColor];
    button.backgroundColor = background;
    button.layer.cornerRadius = 8.0;
    button.clipsToBounds = YES;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, "keyCode", @(key.keyCode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "isToggleable", @(key.toggle), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "isOn", @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "keyName", key.name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return [[UIBarButtonItem alloc] initWithCustomView:button];
}

+ (UIToolbar *)toolbarWithWidth:(CGFloat)width target:(id)target action:(SEL)action {
    CGFloat barWidth = MAX(width, 320.0);
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, barWidth, 44)];
    toolbar.accessibilityIdentifier = @"twilight.keyboardToolbar";
    toolbar.insetsLayoutMarginsFromSafeArea = NO;
    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];
    for (TwilightOnScreenKey *key in [self toolbarKeys]) {
        [items addObject:[self buttonForKey:key target:target action:action]];
    }
    [items addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]];
    [toolbar setItems:items];
    return toolbar;
}

@end
