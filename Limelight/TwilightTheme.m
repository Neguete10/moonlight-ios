//
//  TwilightTheme.m
//  Twilight
//

#import "TwilightTheme.h"

static UIColor *TwilightDynamic(UIColor *dark, UIColor *light) {
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
        }];
    }
    return dark;
}

static UIColor *TwilightHex(int hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:1.0];
}

@implementation TwilightTheme

+ (UIColor *)accent {
    return TwilightDynamic(TwilightHex(0x9EBEFF), TwilightHex(0x0B57D0));
}

+ (UIColor *)accentInk {
    return TwilightDynamic(TwilightHex(0x07111F), [UIColor whiteColor]);
}

+ (UIColor *)background {
    return TwilightDynamic(TwilightHex(0x12141A), TwilightHex(0xF4F5F8));
}

+ (UIColor *)ink {
    return TwilightDynamic(TwilightHex(0xF5F5F7), TwilightHex(0x1C1C1E));
}

+ (UIColor *)secondary {
    UIColor *ink = [self ink];
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            CGFloat alpha = traits.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.68 : 0.62;
            return [[ink resolvedColorWithTraitCollection:traits] colorWithAlphaComponent:alpha];
        }];
    }
    return [ink colorWithAlphaComponent:0.68];
}

+ (UIColor *)tertiary {
    return [[self ink] colorWithAlphaComponent:0.42];
}

+ (UIColor *)online {
    return TwilightDynamic(TwilightHex(0x32D74B), TwilightHex(0x1B7F34));
}

+ (UIColor *)offline {
    return [[self ink] colorWithAlphaComponent:0.35];
}

+ (UIColor *)warn {
    return TwilightDynamic(TwilightHex(0xFFB340), TwilightHex(0xC45500));
}

+ (UIColor *)danger {
    return TwilightDynamic(TwilightHex(0xFF6961), TwilightHex(0xD70015));
}

+ (UIColor *)fill {
    UIColor *ink = [self ink];
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            CGFloat alpha = traits.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.08 : 0.05;
            return [[ink resolvedColorWithTraitCollection:traits] colorWithAlphaComponent:alpha];
        }];
    }
    return [ink colorWithAlphaComponent:0.08];
}

+ (UIColor *)fillStrong {
    UIColor *ink = [self ink];
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            CGFloat alpha = traits.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.14 : 0.08;
            return [[ink resolvedColorWithTraitCollection:traits] colorWithAlphaComponent:alpha];
        }];
    }
    return [ink colorWithAlphaComponent:0.14];
}

+ (UIColor *)stroke {
    UIColor *ink = [self ink];
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            CGFloat alpha = traits.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.16 : 0.12;
            return [[ink resolvedColorWithTraitCollection:traits] colorWithAlphaComponent:alpha];
        }];
    }
    return [ink colorWithAlphaComponent:0.16];
}

+ (UIColor *)glass {
    return TwilightDynamic([UIColor colorWithRed:0.09 green:0.10 blue:0.13 alpha:0.72],
                           [UIColor colorWithWhite:1 alpha:0.74]);
}

+ (UIColor *)elevated {
    return TwilightDynamic([UIColor colorWithRed:0.12 green:0.13 blue:0.16 alpha:0.96],
                           [UIColor colorWithRed:0.99 green:0.99 blue:1 alpha:0.97]);
}

+ (UIColor *)sidebar {
    return TwilightDynamic([UIColor colorWithRed:0.07 green:0.08 blue:0.10 alpha:0.92],
                           [UIColor colorWithWhite:1 alpha:0.92]);
}

+ (UIColor *)scrim {
    return TwilightDynamic([UIColor colorWithWhite:0 alpha:0.46],
                           [UIColor colorWithWhite:0 alpha:0.28]);
}

+ (UIColor *)selection {
    UIColor *accent = [self accent];
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            CGFloat alpha = traits.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.22 : 0.14;
            return [[accent resolvedColorWithTraitCollection:traits] colorWithAlphaComponent:alpha];
        }];
    }
    return [accent colorWithAlphaComponent:0.22];
}

+ (UIColor *)field {
    return TwilightDynamic([UIColor colorWithWhite:1 alpha:0.06],
                           [UIColor colorWithWhite:0 alpha:0.04]);
}

+ (UIFont *)fontForStyle:(UIFontTextStyle)style weight:(UIFontWeight)weight {
    UIFont *base = [UIFont preferredFontForTextStyle:style];
    UIFont *weighted = [UIFont systemFontOfSize:base.pointSize weight:weight];
    UIFontMetrics *metrics = [UIFontMetrics metricsForTextStyle:style];
    CGFloat cap = base.pointSize * 1.35;
    if (@available(iOS 11.0, tvOS 11.0, *)) {
        return [metrics scaledFontForFont:weighted maximumPointSize:cap];
    }
    return weighted;
}

+ (UIImage *)symbolNamed:(NSString *)name pointSize:(CGFloat)pointSize {
    UIImage *image = nil;
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightRegular];
        image = [UIImage systemImageNamed:name withConfiguration:config];
    }
    return image;
}

+ (void)applyToNavigationBar:(UINavigationBar *)bar {
    if (bar == nil) {
        return;
    }
    bar.tintColor = [self accent];
    bar.barTintColor = [self background];
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [self background];
        appearance.shadowColor = [self stroke];
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: [self ink],
            NSFontAttributeName: [self fontForStyle:UIFontTextStyleHeadline weight:UIFontWeightSemibold],
        };
        bar.standardAppearance = appearance;
        bar.scrollEdgeAppearance = appearance;
        if (@available(iOS 15.0, tvOS 15.0, *)) {
            bar.compactAppearance = appearance;
        }
    }
    bar.titleTextAttributes = @{ NSForegroundColorAttributeName: [self ink] };
}

+ (void)applyBorderToLayer:(CALayer *)layer width:(CGFloat)width traitCollection:(UITraitCollection *)traits {
    layer.borderWidth = width;
    UIColor *color = [self stroke];
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        color = [color resolvedColorWithTraitCollection:traits];
    }
    layer.borderColor = color.CGColor;
}

@end

@interface TwilightBlockButton : UIButton
@property (nonatomic, copy) TwilightAction action;
@end

@implementation TwilightBlockButton
- (void)twilightFire {
    if (self.action != nil) {
        self.action();
    }
}
@end

static TwilightBlockButton *TwilightButton(NSString *title, UIColor *fill, UIColor *ink, TwilightAction action) {
    TwilightBlockButton *button = [TwilightBlockButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:ink forState:UIControlStateNormal];
    button.titleLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleSubheadline weight:UIFontWeightSemibold];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.backgroundColor = fill;
    button.layer.cornerRadius = 12;
    button.action = action;
    [button addTarget:button action:@selector(twilightFire) forControlEvents:UIControlEventPrimaryActionTriggered];
    return button;
}

@implementation TwilightLaunchCard {
    UIImageView *_symbol;
    UILabel *_stage;
    UILabel *_hint;
    UIView *_track;
    UIView *_bar;
}

+ (instancetype)cardWithStage:(NSString *)stage hint:(NSString *)hint {
    TwilightLaunchCard *card = [[TwilightLaunchCard alloc] initWithFrame:CGRectMake(0, 0, 360, 180)];
    [card setStageText:stage];
    [card setHintText:hint];
    return card;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    self.backgroundColor = [TwilightTheme glass];
    self.layer.cornerRadius = 22;
    [TwilightTheme applyBorderToLayer:self.layer width:1 traitCollection:self.traitCollection];

    _symbol = [[UIImageView alloc] initWithImage:[TwilightTheme symbolNamed:@"moon.stars" pointSize:28]];
    if (_symbol.image == nil) {
        _symbol.image = [TwilightTheme symbolNamed:@"moon" pointSize:28];
    }
    _symbol.tintColor = [TwilightTheme accent];
    _symbol.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_symbol];

    _stage = [[UILabel alloc] init];
    _stage.font = [TwilightTheme fontForStyle:UIFontTextStyleTitle2 weight:UIFontWeightSemibold];
    _stage.adjustsFontForContentSizeCategory = YES;
    _stage.textColor = [TwilightTheme ink];
    _stage.numberOfLines = 2;
    [self addSubview:_stage];

    _hint = [[UILabel alloc] init];
    _hint.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightRegular];
    _hint.adjustsFontForContentSizeCategory = YES;
    _hint.textColor = [TwilightTheme secondary];
    _hint.numberOfLines = 3;
    [self addSubview:_hint];

    _track = [[UIView alloc] init];
    _bar = [[UIView alloc] init];
    _bar.backgroundColor = [TwilightTheme accent];
    _bar.layer.cornerRadius = 2;
    [_track addSubview:_bar];
    [self addSubview:_track];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_bar.layer removeAnimationForKey:@"twilight-slide"];
    if (self.window == nil) {
        return;
    }
    CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"position.x"];
    slide.fromValue = @(8);
    slide.toValue = @(MAX(self.bounds.size.width - 80, 40));
    slide.duration = 0.9;
    slide.autoreverses = YES;
    slide.repeatCount = HUGE_VALF;
    slide.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_bar.layer addAnimation:slide forKey:@"twilight-slide"];
}

- (void)setStageText:(NSString *)stage {
    _stage.text = stage;
    [self setNeedsLayout];
}

- (void)setHintText:(NSString *)hint {
    _hint.text = hint;
    [self setNeedsLayout];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [TwilightTheme applyBorderToLayer:self.layer width:1 traitCollection:self.traitCollection];
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat width = MIN(440, MAX(260, size.width));
    return CGSizeMake(width, 196);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat pad = 24;
    CGFloat width = self.bounds.size.width - pad * 2;
    _symbol.frame = CGRectMake(pad, pad, 32, 32);
    _stage.frame = CGRectMake(pad, CGRectGetMaxY(_symbol.frame) + 8, width, 56);
    _hint.frame = CGRectMake(pad, CGRectGetMaxY(_stage.frame) + 4, width, 44);
    _track.frame = CGRectMake(pad, CGRectGetMaxY(_hint.frame) + 12, width, 4);
    _bar.frame = CGRectMake(0, 0, width * 0.35, 3);
}

@end

@implementation TwilightLibraryHeader {
    UILabel *_hostLabel;
    UILabel *_subtitleLabel;
    UIView *_banner;
    UIImageView *_art;
    UILabel *_desktopTitle;
    UILabel *_desktopHint;
    TwilightBlockButton *_streamButton;
    TwilightBlockButton *_quitButton;
    CGFloat _leading;
    BOOL _hasDesktop;
    BOOL _running;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    self.backgroundColor = [UIColor clearColor];

    _hostLabel = [[UILabel alloc] init];
    // Large Title is not part of the tvOS text styles.
#if TARGET_OS_TV
    _hostLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleTitle1 weight:UIFontWeightSemibold];
#else
    _hostLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleLargeTitle weight:UIFontWeightSemibold];
#endif
    _hostLabel.adjustsFontForContentSizeCategory = YES;
    _hostLabel.adjustsFontSizeToFitWidth = YES;
    _hostLabel.minimumScaleFactor = 0.6;
    _hostLabel.textColor = [TwilightTheme ink];
    [self addSubview:_hostLabel];

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightRegular];
    _subtitleLabel.adjustsFontForContentSizeCategory = YES;
    _subtitleLabel.textColor = [TwilightTheme secondary];
    [self addSubview:_subtitleLabel];

    _banner = [[UIView alloc] init];
    _banner.backgroundColor = [TwilightTheme glass];
    _banner.layer.cornerRadius = 18;
    _banner.clipsToBounds = YES;
    [self addSubview:_banner];

    _art = [[UIImageView alloc] init];
    _art.contentMode = UIViewContentModeScaleAspectFit;
    _art.backgroundColor = [TwilightTheme fill];
    [_banner addSubview:_art];

    _desktopTitle = [[UILabel alloc] init];
    _desktopTitle.font = [TwilightTheme fontForStyle:UIFontTextStyleTitle2 weight:UIFontWeightSemibold];
    _desktopTitle.adjustsFontForContentSizeCategory = YES;
    _desktopTitle.textColor = [TwilightTheme ink];
    [_banner addSubview:_desktopTitle];

    _desktopHint = [[UILabel alloc] init];
    _desktopHint.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightRegular];
    _desktopHint.adjustsFontForContentSizeCategory = YES;
    _desktopHint.textColor = [TwilightTheme secondary];
    _desktopHint.numberOfLines = 2;
    [_banner addSubview:_desktopHint];

    _streamButton = TwilightButton(@"Stream", [TwilightTheme accent], [TwilightTheme accentInk], nil);
    _quitButton = TwilightButton(@"Quit", [TwilightTheme danger], [UIColor whiteColor], nil);
    [_banner addSubview:_streamButton];
    [_banner addSubview:_quitButton];
    return self;
}

- (void)configureWithHostName:(NSString *)hostName
                     subtitle:(NSString *)subtitle
                  desktopName:(NSString *)desktopName
                  desktopHint:(NSString *)desktopHint
                          art:(UIImage *)art
                      running:(BOOL)running
                 leadingInset:(CGFloat)leadingInset
                       stream:(TwilightAction)stream
                         quit:(TwilightAction)quit {
    _leading = leadingInset;
    _hasDesktop = desktopName.length > 0;
    _running = running;
    _hostLabel.text = hostName;
    _subtitleLabel.text = subtitle;
    _hostLabel.hidden = hostName.length == 0;
    _subtitleLabel.hidden = subtitle.length == 0;
    _banner.hidden = !_hasDesktop;
    _desktopTitle.text = desktopName.length > 0 ? desktopName : @"Desktop";
    _desktopHint.text = desktopHint;
    _art.image = art;
    _streamButton.action = stream;
    [_streamButton setTitle:running ? @"Resume" : @"Stream" forState:UIControlStateNormal];
    _quitButton.action = quit;
    _quitButton.hidden = !running;
    [TwilightTheme applyBorderToLayer:_banner.layer width:1 traitCollection:self.traitCollection];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat textX = _leading;
    CGFloat textW = MAX(0, width - textX - 20);
    CGFloat y = 0;
    if (!_hostLabel.hidden) {
        _hostLabel.frame = CGRectMake(textX, 0, textW, 40);
        _subtitleLabel.frame = CGRectMake(textX, 42, textW, 22);
        y = 80;
    }
    if (_banner.hidden) {
        return;
    }
    _banner.frame = CGRectMake(textX, y, textW, 148);
    BOOL narrow = textW < 460;
    if (narrow) {
        _banner.frame = CGRectMake(textX, y, textW, 210);
        _art.frame = CGRectMake(0, 0, textW, 96);
        _desktopTitle.frame = CGRectMake(16, 104, textW - 32, 28);
        _desktopHint.frame = CGRectMake(16, 132, textW - 32, 32);
        _streamButton.frame = CGRectMake(16, 168, 110, 36);
        _quitButton.frame = CGRectMake(134, 168, 72, 36);
    }
    else {
        _art.frame = CGRectMake(0, 0, 220, 148);
        _streamButton.frame = CGRectMake(textW - 128, 40, 108, 40);
        _quitButton.frame = CGRectMake(textW - 128, 88, 108, 32);
        CGFloat labelX = 236;
        CGFloat labelW = MAX(40, _streamButton.frame.origin.x - labelX - 12);
        _desktopTitle.frame = CGRectMake(labelX, 44, labelW, 30);
        _desktopHint.frame = CGRectMake(labelX, 78, labelW, 36);
    }
}

@end

@implementation TwilightHudBar {
    UILabel *_fps;
    UILabel *_rate;
    UILabel *_rtt;
    TwilightBlockButton *_end;
    UIView *_fpsChip;
    UIView *_rateChip;
    UIView *_rttChip;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    self.backgroundColor = [TwilightTheme glass];
    self.layer.cornerRadius = 22;
    [TwilightTheme applyBorderToLayer:self.layer width:1 traitCollection:self.traitCollection];

    _fpsChip = [self chip];
    _rateChip = [self chip];
    _rttChip = [self chip];
    _fps = [self metricLabel];
    _rate = [self metricLabel];
    _rtt = [self metricLabel];
    [_fpsChip addSubview:_fps];
    [_rateChip addSubview:_rate];
    [_rttChip addSubview:_rtt];
    [self addSubview:_fpsChip];
    [self addSubview:_rateChip];
    [self addSubview:_rttChip];

    _end = TwilightButton(@"End", [TwilightTheme fillStrong], [TwilightTheme ink], nil);
    _end.layer.cornerRadius = 14;
    [self addSubview:_end];
    return self;
}

- (UIView *)chip {
    UIView *chip = [[UIView alloc] init];
    chip.backgroundColor = [TwilightTheme fillStrong];
    chip.layer.cornerRadius = 14;
    return chip;
}

- (UILabel *)metricLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = [TwilightTheme fontForStyle:UIFontTextStyleCaption1 weight:UIFontWeightSemibold];
    label.textColor = [TwilightTheme ink];
    label.textAlignment = NSTextAlignmentCenter;
    return label;
}

- (void)setEndAction:(TwilightAction)endAction {
    _endAction = [endAction copy];
    _end.action = _endAction;
}

- (void)setFps:(NSString *)fps bitrate:(NSString *)bitrate rtt:(NSString *)rtt {
    _fps.text = [NSString stringWithFormat:@"FPS  %@", fps.length ? fps : @"—"];
    _rate.text = [NSString stringWithFormat:@"RATE  %@", bitrate.length ? bitrate : @"—"];
    _rtt.text = [NSString stringWithFormat:@"RTT  %@", rtt.length ? rtt : @"—"];
    [self setNeedsLayout];
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(MIN(size.width, 460), 44);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat gap = 8;
    CGFloat height = 32;
    CGFloat y = 6;
    CGFloat x = 8;
    CGFloat inner = self.bounds.size.width - 16;
    CGFloat chipW = MAX(72, (inner - 88 - gap * 3) / 3.0);
    _fpsChip.frame = CGRectMake(x, y, chipW, height);
    _rateChip.frame = CGRectMake(CGRectGetMaxX(_fpsChip.frame) + gap, y, chipW, height);
    _rttChip.frame = CGRectMake(CGRectGetMaxX(_rateChip.frame) + gap, y, chipW, height);
    _end.frame = CGRectMake(self.bounds.size.width - 8 - 72, y, 72, height);
    _fps.frame = _fpsChip.bounds;
    _rate.frame = _rateChip.bounds;
    _rtt.frame = _rttChip.bounds;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [TwilightTheme applyBorderToLayer:self.layer width:1 traitCollection:self.traitCollection];
}

@end
