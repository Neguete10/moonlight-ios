//
//  TwilightOnScreenKeyboard.m
//  Moonlight
//

#import "TwilightOnScreenKeyboard.h"
#if !TARGET_OS_TV
#import <objc/runtime.h>

@implementation TwilightOnScreenKey
@end

@interface TwilightKeyboardBar : UIView
@property (nonatomic, copy) NSArray<UIButton *> *keyButtons;
@end

@implementation TwilightKeyboardBar

- (UIEdgeInsets)keySafeInsets {
    UIEdgeInsets insets = self.safeAreaInsets;
    if (self.window != nil) {
        UIEdgeInsets windowInsets = self.window.safeAreaInsets;
        insets.left = MAX(insets.left, windowInsets.left);
        insets.right = MAX(insets.right, windowInsets.right);
    }
    return insets;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    NSUInteger count = self.keyButtons.count;
    if (count == 0 || self.bounds.size.width < 1) {
        return;
    }
    // Landscape iPhone puts the notch in the left or right inset. A button
    // that starts at x=8 sits under that inset, so Done's center is around
    // x=34 and the tap never reaches the control.
    UIEdgeInsets safe = [self keySafeInsets];
    CGFloat left = MAX(8.0, safe.left + 4.0);
    CGFloat right = MAX(8.0, safe.right + 4.0);
    CGFloat gap = 6;
    CGFloat available = self.bounds.size.width - left - right - gap * (count - 1);
    if (available < count * 28.0) {
        left = 8;
        right = 8;
        available = self.bounds.size.width - left - right - gap * (count - 1);
    }
    CGFloat buttonWidth = MIN(52, MAX(28, floor(available / count)));
    CGFloat buttonHeight = MIN(32, MAX(24, self.bounds.size.height - 8));
    CGFloat y = (self.bounds.size.height - buttonHeight) / 2.0;
    CGFloat x = left;
    for (UIButton *button in self.keyButtons) {
        button.frame = CGRectMake(x, y, buttonWidth, buttonHeight);
        x += buttonWidth + gap;
    }
}

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
    // The system keyboard sizes the accessory to its own width. Start from the
    // window's current width so the bar is not wider than the keys can be hit.
    CGFloat width = view.bounds.size.width;
    if (view.window != nil && view.window.bounds.size.width > width) {
        width = view.window.bounds.size.width;
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

+ (UIButton *)buttonForKey:(TwilightOnScreenKey *)key target:(id)target action:(SEL)action {
    UIImage *image = [self imageForKey:key];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.accessibilityIdentifier = key.identifier;
    button.accessibilityLabel = key.name;
    button.translatesAutoresizingMaskIntoConstraints = YES;
    if (image != nil) {
        [button setImage:image forState:UIControlStateNormal];
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        button.contentEdgeInsets = UIEdgeInsetsMake(4, 4, 4, 4);
    }
    else {
        // A missing catalog image used to leave an empty chip, which reads
        // as a missing key. The title is the upstream key name.
        [button setTitle:key.name forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
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
    return button;
}

+ (UIView *)toolbarWithWidth:(CGFloat)width target:(id)target action:(SEL)action {
    CGFloat barWidth = MAX(width, 320.0);
    TwilightKeyboardBar *bar = [[TwilightKeyboardBar alloc] initWithFrame:CGRectMake(0, 0, barWidth, 44)];
    bar.accessibilityIdentifier = @"twilight.keyboardToolbar";
    bar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (TwilightOnScreenKey *key in [self toolbarKeys]) {
        UIButton *button = [self buttonForKey:key target:target action:action];
        [bar addSubview:button];
        [buttons addObject:button];
    }
    bar.keyButtons = buttons;
    [bar layoutIfNeeded];
    return bar;
}

@end
#endif
