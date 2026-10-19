//
//  UIComputerView.m
//  Twilight
//

#import "UIComputerView.h"
#import "TwilightTheme.h"

@implementation UIComputerView {
    TemporaryHost* _host;
    UILabel* _hostLabel;
    UILabel* _statusLabel;
    UIView* _statusDot;
    UIActivityIndicatorView* _hostSpinner;
    UIImageView* _addIcon;
    id<HostCallback> _callback;
    BOOL _isAdd;
    BOOL _markedSelected;
}
static const float REFRESH_CYCLE = 2.0f;

- (id) init {
    self = [super init];
    self.backgroundColor = [UIColor clearColor];
#if TARGET_OS_TV
    self.bounds = CGRectMake(0, 0, 420, 150);
#else
    self.bounds = CGRectMake(0, 0, 240, 56);
#endif
    self.layer.cornerRadius = 12;
#if !TARGET_OS_TV
    self.clipsToBounds = YES;
#endif

    _statusDot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 8)];
    _statusDot.layer.cornerRadius = 4;

    _hostLabel = [[UILabel alloc] init];
    _hostLabel.textColor = [TwilightTheme ink];
    _hostLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleSubheadline weight:UIFontWeightSemibold];
    _hostLabel.adjustsFontForContentSizeCategory = YES;
    _hostLabel.adjustsFontSizeToFitWidth = YES;
    _hostLabel.minimumScaleFactor = 0.7;

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.textColor = [TwilightTheme secondary];
    _statusLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleCaption1 weight:UIFontWeightRegular];
    _statusLabel.adjustsFontForContentSizeCategory = YES;

    _addIcon = [[UIImageView alloc] initWithImage:[TwilightTheme symbolNamed:@"plus" pointSize:14]];
    _addIcon.tintColor = [TwilightTheme ink];
    _addIcon.contentMode = UIViewContentModeScaleAspectFit;

    if (@available(iOS 13.0, tvOS 13.0, *)) {
        _hostSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    }
    else {
        _hostSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    }
    _hostSpinner.hidesWhenStopped = YES;
    _hostSpinner.userInteractionEnabled = NO;

    [self addSubview:_statusDot];
    [self addSubview:_hostLabel];
    [self addSubview:_statusLabel];
    [self addSubview:_addIcon];
    [self addSubview:_hostSpinner];

    [self addTarget:self action:@selector(hostButtonSelected:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(hostButtonDeselected:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

#if !TARGET_OS_TV
    if (@available(iOS 13.4.1, *)) {
        self.pointerInteractionEnabled = YES;
    }
#endif
    return self;
}

- (void) hostButtonSelected:(id)sender {
    self.alpha = 0.7f;
}

- (void) hostButtonDeselected:(id)sender {
    self.alpha = 1.0f;
}

- (id) initForAddWithCallback:(id<HostCallback>)callback {
    self = [self init];
    _callback = callback;
    _isAdd = YES;
    _hostLabel.text = @"Add host";
    _statusLabel.text = nil;
    _statusDot.hidden = YES;
    _addIcon.hidden = NO;
#if !TARGET_OS_TV
    self.bounds = CGRectMake(0, 0, 240, 40);
#endif
    [self addTarget:self action:@selector(addClicked) forControlEvents:UIControlEventPrimaryActionTriggered];
    [self applyColors];
    return self;
}

- (id) initWithComputer:(TemporaryHost*)host andCallback:(id<HostCallback>)callback {
    self = [self init];
    _host = host;
    _callback = callback;
    _addIcon.hidden = YES;

#if !TARGET_OS_TV
    if (@available(iOS 13.0, *)) {
        UIContextMenuInteraction* rightClickInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:rightClickInteraction];
    }
    else
#endif
    {
        UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hostLongClicked:)];
        [self addGestureRecognizer:longPressRecognizer];
    }

    [self addTarget:self action:@selector(hostClicked) forControlEvents:UIControlEventPrimaryActionTriggered];
    [self updateContentsForHost:host];
    return self;
}

- (void)setMarkedSelected:(BOOL)selected {
    _markedSelected = selected;
    [self applyColors];
}

- (BOOL)isAddHostButton {
    return _isAdd;
}

- (void)didMoveToSuperview {
    if (self.superview != nil && _host != nil) {
        [self updateLoop];
    }
}

- (NSString *)statusText {
    if (_host.state == StateUnknown) {
        return @"Looking…";
    }
    BOOL streaming = _host.currentGame.length > 0 && ![_host.currentGame isEqualToString:@"0"];
    if (_host.state == StateOnline && _host.pairState == PairStatePaired && streaming) {
        return @"Streaming";
    }
    if (_host.state == StateOnline && _host.pairState == PairStatePaired) {
        return @"Ready";
    }
    if (_host.state == StateOnline) {
        return @"Not paired";
    }
    if (_host.mac.length > 0) {
        return @"Asleep";
    }
    return @"Offline";
}

- (void)applyColors {
    BOOL online = _host.state == StateOnline;
    if (_host.state == StateUnknown) {
        _statusDot.backgroundColor = [TwilightTheme warn];
    }
    else if (online) {
        _statusDot.backgroundColor = [TwilightTheme online];
    }
    else {
        _statusDot.backgroundColor = [TwilightTheme offline];
    }
    if (_isAdd) {
        self.backgroundColor = [TwilightTheme fill];
        [TwilightTheme applyBorderToLayer:self.layer width:1 traitCollection:self.traitCollection];
    }
    else if (_markedSelected) {
        self.backgroundColor = [TwilightTheme selection];
        self.layer.borderWidth = 0;
    }
    else {
        self.backgroundColor = [UIColor clearColor];
        self.layer.borderWidth = 0;
    }
    _hostLabel.textColor = [TwilightTheme ink];
    _statusLabel.textColor = [TwilightTheme secondary];
    self.accessibilityLabel = _isAdd ? @"Add host" : [NSString stringWithFormat:@"%@, %@", _hostLabel.text, _statusLabel.text ?: @""];
}

- (void) updateContentsForHost:(TemporaryHost*)host {
    _hostLabel.text = host.name;
    _statusLabel.text = [self statusText];
    BOOL unknown = host.state == StateUnknown;
    _statusDot.hidden = unknown;
    if (unknown) {
        [_hostSpinner startAnimating];
    }
    else {
        [_hostSpinner stopAnimating];
    }
    [self applyColors];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    if (_isAdd) {
        _addIcon.frame = CGRectMake((width - 92) / 2.0, (height - 16) / 2.0, 16, 16);
        _hostLabel.frame = CGRectMake(CGRectGetMaxX(_addIcon.frame) + 8, 0, 80, height);
        _hostLabel.textAlignment = NSTextAlignmentLeft;
        return;
    }
    _hostLabel.textAlignment = NSTextAlignmentLeft;
    CGFloat textX = 30;
    _statusDot.frame = CGRectMake(12, (height - 8) / 2.0, 8, 8);
    _hostSpinner.frame = CGRectMake(8, (height - 20) / 2.0, 20, 20);
#if TARGET_OS_TV
    _hostLabel.frame = CGRectMake(textX, 36, width - textX - 16, 44);
    _statusLabel.frame = CGRectMake(textX, 84, width - textX - 16, 32);
    _hostLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleTitle2 weight:UIFontWeightSemibold];
    _statusLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleBody weight:UIFontWeightRegular];
#else
    _hostLabel.frame = CGRectMake(textX, 8, width - textX - 12, 22);
    _statusLabel.frame = CGRectMake(textX, 30, width - textX - 12, 18);
#endif
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyColors];
}

#if TARGET_OS_TV
- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    BOOL focused = context.nextFocusedView == self;
    self.backgroundColor = focused ? [TwilightTheme selection] : [TwilightTheme fill];
    self.layer.borderWidth = focused ? 3 : 1;
    UIColor *border = focused ? [TwilightTheme accent] : [TwilightTheme stroke];
    if (@available(tvOS 13.0, *)) {
        border = [border resolvedColorWithTraitCollection:self.traitCollection];
    }
    self.layer.borderColor = border.CGColor;
}
#endif

- (void) updateLoop {
    if (self.superview == nil) {
        return;
    }
    [self updateContentsForHost:_host];
    [self performSelector:@selector(updateLoop) withObject:self afterDelay:REFRESH_CYCLE];
}

- (void) hostLongClicked:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [_callback hostLongClicked:_host view:self];
    }
}

#if !TARGET_OS_TV
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    [self cancelTrackingWithEvent:nil];
    [_callback hostLongClicked:_host view:self];
    return nil;
}
#endif

- (void) hostClicked {
    [_callback hostClicked:_host view:self];
}

- (void) addClicked {
    [_callback addHostClicked];
}

@end
