//
//  TwilightTheme.h
//  Twilight
//
//  UIKit colors and chrome for the Twilight 7.1.0 shell (ThemeV2).
//  Colors follow the system appearance. There is no Qt dependency.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TwilightAction)(void);

@interface TwilightTheme : NSObject

+ (UIColor *)accent;
+ (UIColor *)accentInk;
+ (UIColor *)background;
+ (UIColor *)ink;
+ (UIColor *)secondary;
+ (UIColor *)tertiary;
+ (UIColor *)online;
+ (UIColor *)offline;
+ (UIColor *)warn;
+ (UIColor *)danger;
+ (UIColor *)fill;
+ (UIColor *)fillStrong;
+ (UIColor *)stroke;
+ (UIColor *)glass;
+ (UIColor *)elevated;
+ (UIColor *)sidebar;
+ (UIColor *)scrim;
+ (UIColor *)selection;
+ (UIColor *)field;

+ (UIFont *)fontForStyle:(UIFontTextStyle)style weight:(UIFontWeight)weight;
+ (UIImage *)symbolNamed:(NSString *)name pointSize:(CGFloat)pointSize;

+ (void)applyToNavigationBar:(UINavigationBar *)bar;
+ (void)applyBorderToLayer:(CALayer *)layer width:(CGFloat)width traitCollection:(UITraitCollection *)traits;
+ (UIButton *)buttonWithTitle:(NSString *)title fill:(UIColor *)fill ink:(UIColor *)ink action:(nullable TwilightAction)action;

@end

/// Glass card used while a stream is starting. Matches StreamSegueV2.
@interface TwilightLaunchCard : UIView

+ (instancetype)cardWithStage:(NSString *)stage hint:(NSString *)hint;
- (void)setStageText:(NSString *)stage;
- (void)setHintText:(NSString *)hint;

@end

/// Library title plus the Desktop banner. Matches ShellV2's library header.
@interface TwilightLibraryHeader : UICollectionReusableView

- (void)configureWithHostName:(nullable NSString *)hostName
                     subtitle:(nullable NSString *)subtitle
                  desktopName:(nullable NSString *)desktopName
                  desktopHint:(nullable NSString *)desktopHint
                        art:(nullable UIImage *)art
                      running:(BOOL)running
                 leadingInset:(CGFloat)leadingInset
                trailingInset:(CGFloat)trailingInset
                       stream:(nullable TwilightAction)stream
                         quit:(nullable TwilightAction)quit
                         host:(nullable TwilightAction)host
                         pair:(nullable TwilightAction)pair;

@end

/// In-stream FPS / RATE / RTT chips plus End. Matches HudChipsV2.
@interface TwilightHudBar : UIView

- (void)setFps:(NSString *)fps bitrate:(NSString *)bitrate rtt:(NSString *)rtt;
@property (nonatomic, copy, nullable) TwilightAction endAction;

@end

NS_ASSUME_NONNULL_END
