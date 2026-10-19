//
//  StreamFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "StreamFrameViewController.h"
#import "MainFrameViewController.h"
#import "VideoDecoderRenderer.h"
#import "StreamManager.h"
#import "ControllerSupport.h"
#import "DataManager.h"
#import "AdaptiveBitrate.h"
#import "MicrophoneCapture.h"
#import "HttpManager.h"
#import "TwilightTheme.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <Limelight.h>

#if TARGET_OS_TV
#import <AVFoundation/AVDisplayCriteria.h>
#import <AVKit/AVDisplayManager.h>
#import <AVKit/UIWindow.h>
#endif

@interface AVDisplayCriteria()
@property(readonly) int videoDynamicRange;
@property(readonly, nonatomic) float refreshRate;
- (id)initWithRefreshRate:(float)arg1 videoDynamicRange:(int)arg2;
@end

@implementation StreamFrameViewController {
    ControllerSupport *_controllerSupport;
    StreamManager *_streamMan;
    TemporarySettings *_settings;
    NSTimer *_inactivityTimer;
    NSTimer *_statsUpdateTimer;
    UITapGestureRecognizer *_menuTapGestureRecognizer;
    UITapGestureRecognizer *_menuDoubleTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseTapGestureRecognizer;
    UITextView *_overlayView;
    TwilightLaunchCard *_launchCard;
    UIView *_launchCover;
    TwilightHudBar *_hudBar;
    UIView *_endMenu;
    UIButton *_endMenuFirstButton;
    StreamView *_streamView;
    UIScrollView *_scrollView;
    BOOL _userIsInteracting;
    BOOL _streamFinished;
    BOOL _hostQuitSent;
    BOOL _endMenuPresented;
    NSLock *_featureLock;
    CGSize _keyboardSize;
    
#if !TARGET_OS_TV
    UIScreenEdgePanGestureRecognizer *_exitSwipeRecognizer;
#endif
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
#if !TARGET_OS_TV
    [[self revealViewController] setPrimaryViewController:self];
#endif
}

#if TARGET_OS_TV
- (void)controllerPauseButtonPressed:(id)sender {
    Log(LOG_I, @"Menu pressed -- stream end choices");
    if (_endMenuPresented) {
        [self dismissEndMenu];
        return;
    }
    [self presentEndStreamChoices];
}
- (void)controllerPauseButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Menu double-pressed -- backing out of stream");
    [self endStreamFromUserQuitHost:NO];
}
- (void)controllerPlayPauseButtonPressed:(id)sender {
    Log(LOG_I, @"Play/Pause button pressed -- backing out of stream");
    [self endStreamFromUserQuitHost:NO];
}
#endif


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _settings = [[[DataManager alloc] init] getSettings];
    _featureLock = [[NSLock alloc] init];
    
    self.view.backgroundColor = [TwilightTheme background];
    NSString *stage = [NSString stringWithFormat:@"Starting %@", self.streamConfig.appName ?: @"stream"];
#if TARGET_OS_TV
    NSString *hint = @"Tip: press Menu for end options. Play/Pause disconnects.";
#else
    NSString *hint = @"Tip: swipe from the left edge to disconnect. Hold the left edge for end options.";
#endif
    _launchCard = [TwilightLaunchCard cardWithStage:stage hint:hint];
    _launchCover = [[UIView alloc] initWithFrame:self.view.bounds];
    _launchCover.backgroundColor = [TwilightTheme background];
    _launchCover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_launchCover addSubview:_launchCard];
    
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    _inactivityTimer = nil;
    
    _streamView = [[StreamView alloc] initWithFrame:self.view.frame];
    [_streamView setupStreamView:_controllerSupport interactionDelegate:self config:self.streamConfig];
    
#if TARGET_OS_TV
    if (!_menuTapGestureRecognizer || !_menuDoubleTapGestureRecognizer || !_playPauseTapGestureRecognizer) {
        _menuTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonPressed:)];
        _menuTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];

        _playPauseTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPlayPauseButtonPressed:)];
        _playPauseTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
        
        _menuDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonDoublePressed:)];
        _menuDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [_menuTapGestureRecognizer requireGestureRecognizerToFail:_menuDoubleTapGestureRecognizer];
        _menuDoubleTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];
    }
    
    [self.view addGestureRecognizer:_menuTapGestureRecognizer];
    [self.view addGestureRecognizer:_menuDoubleTapGestureRecognizer];
    [self.view addGestureRecognizer:_playPauseTapGestureRecognizer];

#else
    _exitSwipeRecognizer = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeSwiped:)];
    _exitSwipeRecognizer.edges = UIRectEdgeLeft;
    _exitSwipeRecognizer.delaysTouchesBegan = NO;
    _exitSwipeRecognizer.delaysTouchesEnded = NO;
    
    [self.view addGestureRecognizer:_exitSwipeRecognizer];

    // One recognizer can only be attached to one view. The stream view sits
    // above this controller's view, so the hold lives there. It begins only
    // at the left edge, which is where the swipe-to-disconnect gesture lives.
    UILongPressGestureRecognizer *edgeHold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(edgeHeld:)];
    edgeHold.minimumPressDuration = 0.6;
    edgeHold.delegate = (id<UIGestureRecognizerDelegate>)self;
    [_streamView addGestureRecognizer:edgeHold];
#endif
    
    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                            renderView:_streamView
                                   connectionCallbacks:self];
    NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
    [opQueue addOperation:_streamMan];
    
#if TARGET_OS_TV
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidBecomeActive:)
                                                 name: UIApplicationDidBecomeActiveNotification
                                               object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidEnterBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
#else
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UISceneWillDeactivateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidBecomeActive:)
                                                 name: UISceneDidActivateNotification
                                               object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidEnterBackground:)
                                                 name: UISceneDidEnterBackgroundNotification
                                               object: nil];
#endif

#if 0
    // FIXME: This doesn't work reliably on iPad for some reason. Showing and hiding the keyboard
    // several times in a row will not correctly restore the state of the UIScrollView.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillShow:)
                                                 name: UIKeyboardWillShowNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillHide:)
                                                 name: UIKeyboardWillHideNotification
                                               object: nil];
#endif
    
    // Only enable scroll and zoom in absolute touch mode
    if (_settings.absoluteTouchMode) {
        _scrollView = [[UIScrollView alloc] initWithFrame:self.view.frame];
#if !TARGET_OS_TV
        [_scrollView.panGestureRecognizer setMinimumNumberOfTouches:2];
#endif
        [_scrollView setShowsHorizontalScrollIndicator:NO];
        [_scrollView setShowsVerticalScrollIndicator:NO];
        [_scrollView setDelegate:self];
        [_scrollView setMaximumZoomScale:10.0f];
        
        // Add StreamView inside a UIScrollView for absolute mode
        [_scrollView addSubview:_streamView];
        [self.view addSubview:_scrollView];
    }
    else {
        // Add StreamView directly in relative mode
        [self.view addSubview:_streamView];
    }
    
    [self.view addSubview:_launchCover];
    [self layoutLaunchCard];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _streamView;
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    // Only cleanup when we're being destroyed
    if (parent == nil) {
        [_featureLock lock];
        _streamFinished = YES;
        [_featureLock unlock];
        [MicrophoneCapture stop];
        [_streamMan stopAdaptiveBitrate];
        [_controllerSupport cleanup];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [_streamMan stopStream];
        if (_inactivityTimer != nil) {
            [_inactivityTimer invalidate];
            _inactivityTimer = nil;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

#if 0
- (void)keyboardWillShow:(NSNotification *)notification {
    _keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;

    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height -= self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}

-(void)keyboardWillHide:(NSNotification *)notification {
    // NOTE: UIKeyboardFrameEndUserInfoKey returns a different keyboard size
    // than UIKeyboardFrameBeginUserInfoKey, so it's unsuitable for use here
    // to undo the changes made by keyboardWillShow.
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height += self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}
#endif

- (void)updateStatsOverlay {
    NSString *fps = nil;
    NSString *bitrate = nil;
    NSString *rtt = nil;
    [self->_streamMan getHudMetricsFps:&fps bitrate:&bitrate rtt:&rtt];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_hudBar == nil) {
            self->_hudBar = [[TwilightHudBar alloc] initWithFrame:CGRectMake(0, 0, 420, 44)];
            __weak StreamFrameViewController *weakSelf = self;
            self->_hudBar.endAction = ^{
                [weakSelf presentEndStreamChoices];
            };
            [self.view addSubview:self->_hudBar];
        }
        [self->_hudBar setFps:fps bitrate:bitrate rtt:rtt];
        [self layoutHudBar];
        [self.view bringSubviewToFront:self->_hudBar];
    });
}

- (void)layoutLaunchCard {
    if (_launchCard == nil) {
        return;
    }
    CGSize size = [_launchCard sizeThatFits:CGSizeMake(self.view.bounds.size.width - 64, 220)];
    _launchCard.bounds = (CGRect){CGPointZero, size};
    _launchCard.center = CGPointMake(CGRectGetMidX(_launchCover.bounds), CGRectGetMidY(_launchCover.bounds));
}

- (void)layoutHudBar {
    if (_hudBar == nil) {
        return;
    }
    CGFloat width = MIN(460, self.view.bounds.size.width - 24);
    CGFloat top = self.view.safeAreaInsets.top + 12;
    _hudBar.frame = CGRectMake((self.view.bounds.size.width - width) / 2.0, top, width, 44);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutLaunchCard];
    [self layoutHudBar];
    if (_endMenu != nil) {
        [self.view bringSubviewToFront:_endMenu];
    }
}

- (void)updateOverlayText:(NSString*)text {
    if (_overlayView == nil) {
        _overlayView = [[UITextView alloc] init];
#if !TARGET_OS_TV
        [_overlayView setEditable:NO];
#endif
        [_overlayView setUserInteractionEnabled:NO];
        [_overlayView setSelectable:NO];
        [_overlayView setScrollEnabled:NO];
        
        // HACK: If not using stats overlay, center the text
        if (_statsUpdateTimer == nil) {
            [_overlayView setTextAlignment:NSTextAlignmentCenter];
        }
        
        [_overlayView setTextColor:[TwilightTheme ink]];
        [_overlayView setBackgroundColor:[TwilightTheme glass]];
        _overlayView.layer.cornerRadius = 16;
        _overlayView.textContainerInset = UIEdgeInsetsMake(10, 12, 10, 12);
#if TARGET_OS_TV
        [_overlayView setFont:[TwilightTheme fontForStyle:UIFontTextStyleTitle3 weight:UIFontWeightSemibold]];
#else
        [_overlayView setFont:[TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightSemibold]];
#endif
        [_overlayView setAlpha:1.0];
        [self.view addSubview:_overlayView];
    }
    
    if (text != nil) {
        // We set our bounds to the maximum width in order to work around a bug where
        // sizeToFit interacts badly with the UITextView's line breaks, causing the
        // width to get smaller and smaller each time as more line breaks are inserted.
        [_overlayView setBounds:CGRectMake(self.view.frame.origin.x,
                                           _overlayView.frame.origin.y,
                                           self.view.frame.size.width,
                                           _overlayView.frame.size.height)];
        [_overlayView setText:text];
        [_overlayView sizeToFit];
        [_overlayView setCenter:CGPointMake(self.view.frame.size.width / 2, _overlayView.frame.size.height / 2)];
        [_overlayView setHidden:NO];
    }
    else {
        [_overlayView setHidden:YES];
    }
}

- (void) returnToMainFrame {
    // Reset display mode back to default
    [self updatePreferredDisplayMode:NO];
    
    [_statsUpdateTimer invalidate];
    _statsUpdateTimer = nil;
    
    [self.navigationController popToRootViewControllerAnimated:YES];
}

// This will fire if the user opens control center or gets a low battery message
- (void)applicationWillResignActive:(NSNotification *)notification {
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
    }
    
#if !TARGET_OS_TV
    // Terminate the stream if the app is inactive for 60 seconds
    Log(LOG_I, @"Starting inactivity termination timer");
    _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:60
                                                      target:self
                                                    selector:@selector(inactiveTimerExpired:)
                                                    userInfo:nil
                                                     repeats:NO];
#endif
}

- (void)inactiveTimerExpired:(NSTimer*)timer {
    Log(LOG_I, @"Terminating stream after inactivity");

    [self returnToMainFrame];
    
    _inactivityTimer = nil;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    // Stop the background timer, since we're foregrounded again
    if (_inactivityTimer != nil) {
        Log(LOG_I, @"Stopping inactivity timer after becoming active again");
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
}

// This fires when the home button is pressed
- (void)applicationDidEnterBackground:(UIApplication *)application {
    Log(LOG_I, @"Terminating stream immediately for backgrounding");

    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    
    [self returnToMainFrame];
}

- (void)edgeSwiped:(UIScreenEdgePanGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan || _endMenuPresented) {
        return;
    }
    Log(LOG_I, @"User swiped to end stream");
    [self endStreamFromUserQuitHost:NO];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        CGPoint point = [gestureRecognizer locationInView:self.view];
        return point.x <= 48.0;
    }
    return YES;
}

- (void)edgeHeld:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) {
        return;
    }
    [self presentEndStreamChoices];
}

- (void)dismissEndMenu {
    _endMenuPresented = NO;
    [_endMenu removeFromSuperview];
    _endMenu = nil;
    _endMenuFirstButton = nil;
#if TARGET_OS_TV
    [self setNeedsFocusUpdate];
#endif
}

- (UIButton *)endMenuButton:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[TwilightTheme ink] forState:UIControlStateNormal];
    button.titleLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleSubheadline weight:UIFontWeightSemibold];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.backgroundColor = color;
    button.layer.cornerRadius = 10;
    [button addTarget:self action:action forControlEvents:UIControlEventPrimaryActionTriggered];
    return button;
}

- (void)presentEndStreamChoices {
    if (_endMenuPresented || _streamFinished) {
        return;
    }
    _endMenuPresented = YES;
    UIView *menu = [[UIView alloc] initWithFrame:self.view.bounds];
    menu.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView *scrim = [[UIView alloc] initWithFrame:menu.bounds];
    scrim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrim.backgroundColor = [TwilightTheme scrim];
    [scrim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissEndMenu)]];
    [menu addSubview:scrim];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 220)];
    card.backgroundColor = [TwilightTheme elevated];
    card.layer.cornerRadius = 18;
    [TwilightTheme applyBorderToLayer:card.layer width:1 traitCollection:self.traitCollection];
    card.center = CGPointMake(CGRectGetMidX(menu.bounds), CGRectGetMidY(menu.bounds));
    card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, 280, 22)];
    title.text = @"End stream";
    title.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightSemibold];
    title.textColor = [TwilightTheme secondary];
    [card addSubview:title];

    UIButton *end = [self endMenuButton:@"End Stream" color:[UIColor clearColor] action:@selector(endMenuEndStream)];
    end.frame = CGRectMake(12, 48, 296, 40);
    UIButton *quit = [self endMenuButton:@"End Stream and Quit App" color:[UIColor clearColor] action:@selector(endMenuQuitApp)];
    [quit setTitleColor:[TwilightTheme danger] forState:UIControlStateNormal];
    quit.frame = CGRectMake(12, 92, 296, 40);
    UIButton *cancel = [self endMenuButton:@"Cancel" color:[UIColor clearColor] action:@selector(dismissEndMenu)];
    cancel.frame = CGRectMake(12, 136, 296, 40);
    _endMenuFirstButton = end;
    [card addSubview:end];
    [card addSubview:quit];
    [card addSubview:cancel];
    [menu addSubview:card];
    _endMenu = menu;
    [self.view addSubview:menu];
#if TARGET_OS_TV
    [self setNeedsFocusUpdate];
    [self updateFocusIfNeeded];
#endif
}

- (void)endMenuEndStream {
    [self dismissEndMenu];
    [self endStreamFromUserQuitHost:NO];
}

- (void)endMenuQuitApp {
    [self dismissEndMenu];
    [self endStreamFromUserQuitHost:YES];
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    if (_endMenuFirstButton != nil) {
        return @[ _endMenuFirstButton ];
    }
    return [super preferredFocusEnvironments];
}

- (void)endStreamFromUserQuitHost:(BOOL)forceQuit {
    // Host-initiated termination and backgrounding call returnToMainFrame
    // directly, so they never send cancel. A slow host must not block the pop.
    if (!_streamFinished && (forceQuit || _settings.quitAppAfter) && !_hostQuitSent) {
        _hostQuitSent = YES;
        [self sendQuitAppToHost];
    }
    [self returnToMainFrame];
}

- (void)sendQuitAppToHost {
    NSString *host = self.streamConfig.host;
    unsigned short httpsPort = self.streamConfig.httpsPort;
    NSData *cert = self.streamConfig.serverCert;
    if (host.length == 0) {
        Log(LOG_W, @"Not quitting the host app: the stream has no host address");
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        HttpManager *manager = [[HttpManager alloc] initWithAddress:host httpsPort:httpsPort serverCert:cert];
        NSURLRequest *urlRequest = [manager newQuitAppRequest];
        if (urlRequest == nil) {
            Log(LOG_W, @"Quit app request was not built");
            return;
        }
        HttpResponse *response = [[HttpResponse alloc] init];
        HttpRequest *request = [HttpRequest requestForResponse:response withUrlRequest:urlRequest];
        [manager executeRequestSynchronously:request];
        Log(LOG_I, @"Quit app on host finished with status %ld", (long)response.statusCode);
    });
}

- (void) connectionStarted {
    Log(LOG_I, @"Connection started");
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_launchCover.hidden = YES;
        
        [self->_streamView showOnScreenControls];
        
        [self->_controllerSupport connectionEstablished];
        
        if (self->_settings.statsOverlay) {
            self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                       target:self
                                                                     selector:@selector(updateStatsOverlay)
                                                                     userInfo:nil
                                                                      repeats:YES];
        }
        [self->_featureLock lock];
        if (!self->_streamFinished) {
            [self->_streamMan startAdaptiveBitrateIfEnabled:self->_settings.enableAdaptiveBitrate];
            [MicrophoneCapture startIfEnabled:self->_settings.enableMicrophone];
        }
        [self->_featureLock unlock];
    });
}

- (void)connectionTerminated:(int)errorCode {
    Log(LOG_I, @"Connection terminated: %d", errorCode);
    [_featureLock lock];
    _streamFinished = YES;
    [_featureLock unlock];
    
    unsigned int portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode);
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portFlags);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [self->_controllerSupport clearAdaptiveTriggers];
        
        NSString* title;
        NSString* message;
        
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            title = @"Connection Error";
            message = @"Your device's network connection is blocking Twilight. Streaming may not work while connected to this network.";
        }
        else {
            switch (errorCode) {
                case ML_ERROR_GRACEFUL_TERMINATION:
                    [self returnToMainFrame];
                    return;
                    
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = @"Connection Error";
                    message = @"No video received from host.";
                    if (portFlags != 0) {
                        char failingPorts[256];
                        LiStringifyPortFlags(portFlags, "\n", failingPorts, sizeof(failingPorts));
                        message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
                    }
                    break;
                    
                case ML_ERROR_NO_VIDEO_FRAME:
                    title = @"Connection Error";
                    message = @"Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection.";
                    break;
                    
                case ML_ERROR_UNEXPECTED_EARLY_TERMINATION:
                case ML_ERROR_PROTECTED_CONTENT:
                    title = @"Connection Error";
                    message = @"Something went wrong on your host PC when starting the stream.\n\nMake sure you don't have any DRM-protected content open on your host PC. You can also try restarting your host PC.\n\nIf the issue persists, try reinstalling your GPU drivers and GeForce Experience.";
                    break;
                    
                case ML_ERROR_FRAME_CONVERSION:
                    title = @"Connection Error";
                    message = @"The host PC reported a fatal video encoding error.\n\nTry disabling HDR mode, changing the streaming resolution, or changing your host PC's display resolution.";
                    break;
                    
                default:
                {
                    NSString* errorString;
                    if (abs(errorCode) > 1000) {
                        // We'll assume large errors are hex values
                        errorString = [NSString stringWithFormat:@"%08X", (uint32_t)errorCode];
                    }
                    else {
                        // Smaller values will just be printed as decimal (probably errno.h values)
                        errorString = [NSString stringWithFormat:@"%d", errorCode];
                    }
                    
                    title = @"Connection Terminated";
                    message = [NSString stringWithFormat: @"The connection was terminated\n\nError code: %@", errorString];
                    break;
                }
            }
        }
        
        UIAlertController* conTermAlert = [UIAlertController alertControllerWithTitle:title
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:conTermAlert];
        [conTermAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:conTermAlert animated:YES completion:nil];
    });

    [_streamMan stopStream];
}

- (void) stageStarting:(const char*)stageName {
    Log(LOG_I, @"Starting %s", stageName);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* lowerCase = [NSString stringWithFormat:@"%s in progress…", stageName];
        NSString* titleCase = [[[lowerCase substringToIndex:1] uppercaseString] stringByAppendingString:[lowerCase substringFromIndex:1]];
        [self->_launchCard setStageText:titleCase];
    });
}

- (void) stageComplete:(const char*)stageName {
}

- (void) stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    Log(LOG_I, @"Stage %s failed: %d", stageName, errorCode);
    [_featureLock lock];
    _streamFinished = YES;
    [_featureLock unlock];
    
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portTestFlags);

    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [self->_controllerSupport clearAdaptiveTriggers];
        
        NSString* message = [NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode];
        if (portTestFlags != 0) {
            char failingPorts[256];
            LiStringifyPortFlags(portTestFlags, "\n", failingPorts, sizeof(failingPorts));
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
        }
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            message = [message stringByAppendingString:@"\n\nYour device's network connection is blocking Twilight. Streaming may not work while connected to this network."];
        }
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Failed"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
    
    [_streamMan stopStream];
}

- (void) launchFailed:(NSString*)message {
    Log(LOG_I, @"Launch failed: %@", message);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Error"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    Log(LOG_I, @"Rumble on gamepad %d: %04x %04x", controllerNumber, lowFreqMotor, highFreqMotor);
    
    [_controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

- (void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    Log(LOG_I, @"Trigger rumble on gamepad %d: %04x %04x", controllerNumber, leftTrigger, rightTrigger);
    
    [_controllerSupport rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
}

- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    Log(LOG_I, @"Set motion state on gamepad %d: %02x %u Hz", controllerNumber, motionType, reportRateHz);
    
    [_controllerSupport setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

- (void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    Log(LOG_I, @"Set controller LED on gamepad %d: l%02x%02x%02x", controllerNumber, r, g, b);
    
    [_controllerSupport setControllerLed:controllerNumber r:r g:g b:b];
}

- (void) setAdaptiveTriggers:(uint16_t)controllerNumber eventFlags:(uint8_t)eventFlags typeLeft:(uint8_t)typeLeft typeRight:(uint8_t)typeRight left:(uint8_t *)left right:(uint8_t *)right {
    [_controllerSupport setAdaptiveTriggers:controllerNumber eventFlags:eventFlags typeLeft:typeLeft typeRight:typeRight left:left right:right];
}

- (void)connectionStatusUpdate:(int)status {
    Log(LOG_W, @"Connection status update: %d", status);
    if (status == CONN_STATUS_POOR) {
        TwilightSetPoorConnection(YES);
    }
    else if (status == CONN_STATUS_OKAY) {
        TwilightSetPoorConnection(NO);
    }

    // The stats overlay takes precedence over these warnings
    if (_statsUpdateTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (status) {
            case CONN_STATUS_OKAY:
                [self updateOverlayText:nil];
                break;
                
            case CONN_STATUS_POOR:
                if (self->_streamConfig.bitRate > 5000) {
                    [self updateOverlayText:@"Slow connection to PC\nReduce your bitrate"];
                }
                else {
                    [self updateOverlayText:@"Poor connection to PC"];
                }
                break;
        }
    });
}

- (void) updatePreferredDisplayMode:(BOOL)streamActive {
#if TARGET_OS_TV
    if (@available(tvOS 11.2, *)) {
        UIWindow* window = [[[UIApplication sharedApplication] delegate] window];
        AVDisplayManager* displayManager = [window avDisplayManager];
        
        // This logic comes from Kodi and MrMC
        if (streamActive) {
            int dynamicRange;
            
            if (LiGetCurrentHostDisplayHdrMode()) {
                dynamicRange = 2; // HDR10
            }
            else {
                dynamicRange = 0; // SDR
            }
            
            AVDisplayCriteria* displayCriteria = [[AVDisplayCriteria alloc] initWithRefreshRate:[_settings.framerate floatValue]
                                                                              videoDynamicRange:dynamicRange];
            displayManager.preferredDisplayCriteria = displayCriteria;
        }
        else {
            // Switch back to the default display mode
            displayManager.preferredDisplayCriteria = nil;
        }
    }
#endif
}

- (void) setHdrMode:(bool)enabled {
    Log(LOG_I, @"HDR is now: %s", enabled ? "active" : "inactive");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updatePreferredDisplayMode:YES];
    });
}

- (void) videoContentShown {
    [_launchCover setHidden:YES];
    [self.view setBackgroundColor:[UIColor blackColor]];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)gamepadPresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)mousePresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 14.0, *)) {
        [self setNeedsUpdateOfPrefersPointerLocked];
    }
#endif
}

- (void) streamExitRequested {
    Log(LOG_I, @"Gamepad combo requested stream exit");
    
    [self endStreamFromUserQuitHost:NO];
}

- (void)userInteractionBegan {
    // Disable hiding home bar when user is interacting.
    // iOS will force it to be shown anyway, but it will
    // also discard our edges deferring system gestures unless
    // we willingly give up home bar hiding preference.
    _userIsInteracting = YES;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)userInteractionEnded {
    // Enable home bar hiding again if conditions allow
    _userIsInteracting = NO;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

#if !TARGET_OS_TV
// Require a confirmation when streaming to activate a system gesture
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    if ([_controllerSupport getConnectedGamepadCount] > 0 &&
        [_streamView getCurrentOscState] == OnScreenControlsLevelOff &&
        _userIsInteracting == NO) {
        // Autohide the home bar when a gamepad is connected
        // and the on-screen controls are disabled. We can't
        // do this all the time because any touch on the display
        // will cause the home indicator to reappear, and our
        // preferredScreenEdgesDeferringSystemGestures will also
        // be suppressed (leading to possible errant exits of the
        // stream).
        return YES;
    }
    
    return NO;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (BOOL)prefersPointerLocked {
    // Pointer lock breaks the UIKit mouse APIs, which is a problem because
    // GCMouse is horribly broken on iOS 14.0 for certain mice. Only lock
    // the cursor if there is a GCMouse present.
    return [GCMouse mice].count > 0;
}
#endif

@end
