//
//  UIAppView.m
//  Twilight
//

#import "UIAppView.h"
#import "AppAssetManager.h"
#import "TwilightTheme.h"

static const float REFRESH_CYCLE = 1.0f;

@implementation UIAppView {
    TemporaryApp* _app;
    UILabel* _appLabel;
    UILabel* _liveBadge;
    UIImageView* _appImage;
    NSCache* _artCache;
    id<AppCallback> _callback;
    BOOL _noAppImage;
}

static UIImage* noImage;

+ (CGSize)preferredSize {
#if TARGET_OS_TV
    return CGSizeMake(220, 280);
#else
    BOOL wide = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
    if (@available(iOS 17.0, *)) {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomVision) {
            wide = YES;
        }
    }
    CGFloat art = wide ? 168 : 150;
    return CGSizeMake(art, art + 36);
#endif
}

- (id) initWithApp:(TemporaryApp*)app cache:(NSCache*)cache andCallback:(id<AppCallback>)callback {
    self = [super init];
    _app = app;
    _callback = callback;
    _artCache = cache;

    if (noImage == nil) {
        noImage = [UIImage imageNamed:@"NoAppImage"];
    }

    self.bounds = (CGRect){CGPointZero, [UIAppView preferredSize]};
    self.backgroundColor = [UIColor clearColor];
    [self setAlpha:app.hidden ? 0.4 : 1.0];

    CGFloat art = self.bounds.size.width;
    _appImage = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, art, art)];
    _appImage.image = noImage;
    _appImage.contentMode = UIViewContentModeScaleAspectFill;
    _appImage.clipsToBounds = YES;
    _appImage.layer.cornerRadius = 14;
    _appImage.backgroundColor = [TwilightTheme fill];
    [self addSubview:_appImage];

    _liveBadge = [[UILabel alloc] init];
    _liveBadge.text = @"Live";
    _liveBadge.textAlignment = NSTextAlignmentCenter;
    _liveBadge.font = [TwilightTheme fontForStyle:UIFontTextStyleCaption2 weight:UIFontWeightSemibold];
    _liveBadge.textColor = [TwilightTheme accentInk];
    _liveBadge.backgroundColor = [TwilightTheme accent];
    _liveBadge.layer.cornerRadius = 8;
    _liveBadge.clipsToBounds = YES;
    _liveBadge.hidden = YES;
    [_appImage addSubview:_liveBadge];

    _appLabel = [[UILabel alloc] init];
    _appLabel.textColor = [TwilightTheme ink];
    _appLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightSemibold];
    _appLabel.adjustsFontForContentSizeCategory = YES;
    _appLabel.adjustsFontSizeToFitWidth = YES;
    _appLabel.minimumScaleFactor = 0.7;
    _appLabel.numberOfLines = 2;
    _appLabel.text = app.name;
    [self addSubview:_appLabel];

#if !TARGET_OS_TV
    if (@available(iOS 13.0, *)) {
        UIContextMenuInteraction* rightClickInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:rightClickInteraction];
    }
    else
#endif
    {
        UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(appLongClicked:)];
        [self addGestureRecognizer:longPressRecognizer];
    }

    [self addTarget:self action:@selector(appClicked:) forControlEvents:UIControlEventPrimaryActionTriggered];
    [self addTarget:self action:@selector(buttonSelected:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(buttonDeselected:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

#if TARGET_OS_TV
    _appImage.adjustsImageWhenAncestorFocused = YES;
#else
    if (@available(iOS 13.4.1, *)) {
        self.pointerInteractionEnabled = YES;
    }
#endif

    [self updateAppImage];
    return self;
}

- (void)didMoveToSuperview {
    if (self.superview != nil) {
        [self updateLoop];
    }
}

- (void) appClicked:(UIView *)view {
    [_callback appClicked:_app view:view];
}

- (void) appLongClicked:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [_callback appLongClicked:_app view:self];
    }
}

#if !TARGET_OS_TV
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    [self cancelTrackingWithEvent:nil];
    [_callback appLongClicked:_app view:self];
    return nil;
}
#endif

- (BOOL)isRunning {
    return _app.host.currentGame.length > 0 && [_app.id isEqualToString:_app.host.currentGame];
}

- (void) updateAppImage {
    UIImage* appImage = [_artCache objectForKey:_app];
    if (appImage == nil) {
        appImage = [UIImage imageWithContentsOfFile:[AppAssetManager boxArtPathForApp:_app]];
        if (appImage != nil) {
            [_artCache setObject:appImage forKey:_app];
        }
    }

    _noAppImage = YES;
    if (appImage != nil) {
        if (!(appImage.size.width == 130.f && appImage.size.height == 180.f) &&
            !(appImage.size.width == 628.f && appImage.size.height == 888.f)) {
            _appImage.image = appImage;
            _noAppImage = NO;
        }
    }
    if (_noAppImage) {
        _appImage.image = noImage;
        _appImage.contentMode = UIViewContentModeCenter;
    }
    else {
        _appImage.contentMode = UIViewContentModeScaleAspectFill;
    }

    _appLabel.text = _app.name;
    _liveBadge.hidden = ![self isRunning];
    [self positionSubviews];
}

- (void) buttonSelected:(id)sender {
    _appImage.layer.opacity = 0.55f;
}
- (void) buttonDeselected:(id)sender {
    _appImage.layer.opacity = 1.0f;
}

- (void) positionSubviews {
    CGFloat art = self.bounds.size.width;
    _appImage.frame = CGRectMake(0, 0, art, art);
    _appLabel.frame = CGRectMake(0, art + 8, art, self.bounds.size.height - art - 8);
    _liveBadge.frame = CGRectMake(8, 8, 44, 20);
    CGFloat border = [self isRunning] ? 2.0 : 1.0;
    _appImage.layer.borderWidth = border;
    UIColor *color = [self isRunning] ? [TwilightTheme accent] : [TwilightTheme stroke];
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        color = [color resolvedColorWithTraitCollection:self.traitCollection];
    }
    _appImage.layer.borderColor = color.CGColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self positionSubviews];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self positionSubviews];
}

- (void) updateLoop {
    if (self.superview == nil) {
        return;
    }

    BOOL running = [self isRunning];
    if (_liveBadge.hidden == running) {
        [self updateAppImage];
    }

    [self setAlpha:_app.hidden ? 0.4 : 1.0];
    [self performSelector:@selector(updateLoop) withObject:self afterDelay:REFRESH_CYCLE];
}

@end
