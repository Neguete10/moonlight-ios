//
//  TwilightUITests.m
//  TwilightUITests
//
//  Simulator coverage for launch orientation, the stream picture frame,
//  the three-finger keyboard, and the main shell. No real host is required.
//

#import <XCTest/XCTest.h>

@interface TwilightUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation TwilightUITests

- (void)setUp {
    [super setUp];
    self.continueAfterFailure = NO;
}

- (void)tearDown {
    // XCUIApplication terminate records a test failure when the simulator
    // cannot reap the process, even after every assertion passed. Leaving
    // the app for the runner to reap keeps that from failing the case.
    self.app = nil;
    [super tearDown];
}

- (BOOL)expectLandscape {
    return [NSProcessInfo.processInfo.environment[@"TWILIGHT_EXPECT_LANDSCAPE"] isEqualToString:@"1"];
}

- (void)spinFor:(NSTimeInterval)seconds {
    XCTestExpectation *done = [self expectationWithDescription:@"spin"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [done fulfill];
    });
    [self waitForExpectations:@[done] timeout:seconds + 2];
}

- (XCUIApplication *)launchMode:(NSString *)mode {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    app.launchEnvironment = @{@"TWILIGHT_UITEST": mode};
    [app launch];
    self.app = app;
    XCUIElement *allow = app.buttons[@"Allow"];
    if ([allow waitForExistenceWithTimeout:1]) {
        [allow tap];
    }
    return app;
}

- (void)saveShot:(NSString *)name {
    XCUIScreenshot *shot = [XCUIScreen.mainScreen screenshot];
    NSString *dir = NSProcessInfo.processInfo.environment[@"TWILIGHT_SCREENSHOT_DIR"];
    if (dir.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *safe = [[name stringByReplacingOccurrencesOfString:@" " withString:@"-"] stringByAppendingPathExtension:@"png"];
        [shot.PNGRepresentation writeToFile:[dir stringByAppendingPathComponent:safe] atomically:YES];
    }
    XCTAttachment *attachment = [XCTAttachment attachmentWithScreenshot:shot];
    attachment.name = name;
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
}

- (CGRect)windowFrame {
    return self.app.windows.firstMatch.frame;
}

- (void)assertFrame:(CGRect)frame fitsInWindowNamed:(NSString *)name {
    CGRect window = [self windowFrame];
    CGRect allowed = CGRectInset(window, -3, -3);
    XCTAssertTrue(CGRectContainsRect(allowed, frame),
                  @"%@ frame %@ is outside window %@", name, NSStringFromCGRect(frame), NSStringFromCGRect(window));
    XCTAssertGreaterThan(frame.size.width, 8, @"%@", name);
    XCTAssertGreaterThan(frame.size.height, 8, @"%@", name);
}

- (XCUIElement *)waitForIdentifier:(NSString *)identifier timeout:(NSTimeInterval)timeout {
    XCUIElement *element = [[self.app descendantsMatchingType:XCUIElementTypeAny] elementMatchingPredicate:[NSPredicate predicateWithFormat:@"identifier == %@", identifier]];
    XCTAssertTrue([element waitForExistenceWithTimeout:timeout], @"Missing %@", identifier);
    return element;
}

- (void)assertVideoSettled {
    XCUIElement *stream = [self waitForIdentifier:@"twilight.stream" timeout:4];
    XCUIElement *video = [self waitForIdentifier:@"twilight.video" timeout:4];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
    CGRect streamFrame = CGRectZero;
    CGRect videoFrame = CGRectZero;
    BOOL settled = NO;
    while ([deadline timeIntervalSinceNow] > 0) {
        streamFrame = stream.frame;
        videoFrame = video.frame;
        BOOL sized = videoFrame.size.width > videoFrame.size.height && videoFrame.size.height > 20;
        BOOL inside = CGRectContainsRect(CGRectInset(streamFrame, -3, -3), videoFrame);
        BOOL centered = fabs(CGRectGetMidX(videoFrame) - CGRectGetMidX(streamFrame)) < 4
            && fabs(CGRectGetMidY(videoFrame) - CGRectGetMidY(streamFrame)) < 4;
        CGFloat aspect = videoFrame.size.height > 1 ? videoFrame.size.width / videoFrame.size.height : 0;
        BOOL ratio = fabs(aspect - (16.0 / 9.0)) < 0.08;
        BOOL fills = fabs(videoFrame.size.width - streamFrame.size.width) < 6
            || fabs(videoFrame.size.height - streamFrame.size.height) < 6;
        if (sized && inside && centered && ratio && fills) {
            settled = YES;
            break;
        }
        [self spinFor:0.2];
    }
    XCTAssertTrue(settled, @"video %@ in stream %@", NSStringFromCGRect(videoFrame), NSStringFromCGRect(streamFrame));
    CGRect window = [self windowFrame];
    XCTAssertEqualWithAccuracy(streamFrame.size.width, window.size.width, 12, @"stream should fill the screen width");
    XCTAssertEqualWithAccuracy(streamFrame.size.height, window.size.height, 12, @"stream should fill the screen height");
    [self assertFrame:streamFrame fitsInWindowNamed:@"stream"];
    [self assertFrame:videoFrame fitsInWindowNamed:@"video"];
    if ([self expectLandscape]) {
        XCTAssertGreaterThan(window.size.width, window.size.height, @"iPhone interface should be landscape");
        XCTAssertGreaterThan(streamFrame.size.width, streamFrame.size.height);
    }
}

- (void)testAppLaunchesAndMainFlowsFit {
    // Rotate after launch. Setting portrait before launch on a landscape-only
    // phone leaves the simulator unable to start the app.
    XCUIApplication *app = [self launchMode:@"library"];
    if ([self expectLandscape]) {
        [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationPortrait];
        [self spinFor:0.4];
    }
    XCUIElement *shell = [self waitForIdentifier:@"twilight.shell" timeout:4];
    XCUIElement *apps = [self waitForIdentifier:@"twilight.apps" timeout:4];
    [self assertFrame:shell.frame fitsInWindowNamed:@"shell"];
    [self assertFrame:apps.frame fitsInWindowNamed:@"apps"];
    XCUIElement *desktop = app.staticTexts[@"Desktop"];
    XCTAssertTrue([desktop waitForExistenceWithTimeout:3], @"App grid did not show the fixture desktop");
    [self assertFrame:desktop.frame fitsInWindowNamed:@"Desktop"];
    if ([self expectLandscape]) {
        CGRect window = [self windowFrame];
        XCTAssertGreaterThan(window.size.width, window.size.height);
    }
    [self saveShot:@"library"];

    [app.buttons[@"twilight.settingsButton"] tap];
    XCUIElement *settings = [self waitForIdentifier:@"twilight.settings" timeout:4];
    [self assertFrame:settings.frame fitsInWindowNamed:@"settings"];
    [self saveShot:@"settings"];
}

- (void)dismissTypingTip {
    // A fresh simulator covers the keyboard with "Speed up your typing by
    // sliding your finger… Continue". That tip swallows the Esc tap.
    XCUIElement *continueButton = self.app.buttons[@"Continue"];
    if ([continueButton waitForExistenceWithTimeout:2]) {
        if (continueButton.isHittable) {
            [continueButton tap];
        }
        else {
            [[continueButton coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.5)] tap];
        }
    }
}

- (void)tapIdentifier:(NSString *)identifier {
    XCUIElement *element = self.app.buttons[identifier];
    XCTAssertTrue([element waitForExistenceWithTimeout:2], @"Missing %@", identifier);
    [self assertFrame:element.frame fitsInWindowNamed:identifier];
    // Tap the button's own center. Offsetting from the window origin put
    // Done at the landscape safe-area edge (about x=34) and missed the key.
    if (element.isHittable) {
        [element tap];
    }
    else {
        [[element coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.5)] tap];
    }
}

- (void)testHostsFitOnScreen {
    XCUIApplication *app = [self launchMode:@"hosts"];
    XCUIElement *hosts = [self waitForIdentifier:@"twilight.hosts" timeout:4];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (hosts.frame.size.width < 8 && [deadline timeIntervalSinceNow] > 0) {
        [self spinFor:0.2];
    }
    [self assertFrame:hosts.frame fitsInWindowNamed:@"hosts"];
    XCUIElementQuery *rooms = [app.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", @"Living Room"]];
    if (rooms.firstMatch.exists) {
        [self assertFrame:rooms.firstMatch.frame fitsInWindowNamed:@"Living Room"];
    }
    [self saveShot:@"hosts"];
}

- (void)testStreamVideoFromPortraitAndBothLandscapes {
    [self launchMode:@"stream"];
    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationPortrait];
    [self assertVideoSettled];
    [self saveShot:@"stream-from-portrait"];

    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationLandscapeLeft];
    [self assertVideoSettled];
    [self saveShot:@"stream-landscape-left"];

    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationLandscapeRight];
    [self assertVideoSettled];
    [self saveShot:@"stream-landscape-right"];
}

- (XCUIElement *)keyLog {
    XCUIElement *log = self.app.staticTexts[@"twilight.keylog"];
    if (!log.exists) {
        log = self.app.otherElements[@"twilight.keylog"];
    }
    return log;
}

- (BOOL)logContains:(NSString *)needle within:(NSTimeInterval)timeout {
    XCUIElement *log = [self keyLog];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"label CONTAINS %@", needle];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc] initWithPredicate:predicate object:log];
    return [XCTWaiter waitForExpectations:@[expectation] timeout:timeout] == XCTWaiterResultCompleted;
}

- (void)tapIdentifier:(NSString *)identifier expecting:(NSString *)needle {
    [self tapIdentifier:identifier];
    if ([self logContains:needle within:2]) {
        return;
    }
    // One missed tap is enough to fail the case. Try the button's center again.
    [self tapIdentifier:identifier];
    XCTAssertTrue([self logContains:needle within:4], @"key log missing \"%@\": %@", needle, [self keyLog].label);
}

- (void)waitForLogContaining:(NSString *)needle {
    XCTAssertTrue([self logContains:needle within:4], @"key log missing \"%@\": %@", needle, [self keyLog].label);
}

- (void)testThreeFingerKeyboardSpecialKeysSendEvents {
    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationLandscapeLeft];
    XCUIApplication *app = [self launchMode:@"keyboard"];
    [self assertVideoSettled];
    XCUIElement *stream = [self waitForIdentifier:@"twilight.stream" timeout:4];

    if (@available(iOS 16.4, *)) {
        [stream tapWithNumberOfTaps:1 numberOfTouches:3];
    }
    else {
        XCTFail(@"Three-finger tap needs iOS 16.4");
    }

    XCUIElement *keyboard = app.keyboards.firstMatch;
    BOOL appeared = [keyboard waitForExistenceWithTimeout:4];
    if (!appeared) {
        [stream tapWithNumberOfTaps:1 numberOfTouches:3];
        appeared = [keyboard waitForExistenceWithTimeout:4];
    }
    XCTAssertTrue(appeared, @"Software keyboard did not appear. Disable ConnectHardwareKeyboard on the simulator. %@", app.debugDescription);
    [self dismissTypingTip];
    [self assertFrame:keyboard.frame fitsInWindowNamed:@"keyboard"];
    XCTAssertGreaterThan(app.keys.count, 0, @"System keyboard has no keys");

    NSArray<NSString *> *identifiers = @[
        @"twilight.key.done",
        @"twilight.key.win",
        @"twilight.key.esc",
        @"twilight.key.tab",
        @"twilight.key.shift",
        @"twilight.key.ctrl",
        @"twilight.key.alt",
        @"twilight.key.del",
    ];
    for (NSString *identifier in identifiers) {
        XCUIElement *button = app.buttons[identifier];
        XCTAssertTrue([button waitForExistenceWithTimeout:2], @"Missing %@", identifier);
        [self assertFrame:button.frame fitsInWindowNamed:identifier];
    }
    [self saveShot:@"keyboard"];

    // Type the letter before any toggle key is held. Win and Alt stay down
    // until tapped again, and a q typed in that state is not VK 81.
    XCUIElement *letter = app.keys[@"q"];
    if (!letter.exists) {
        letter = app.keys[@"Q"];
    }
    XCTAssertTrue(letter.exists, @"System keyboard is missing the Q key");
    // Type into the focused stream field. The one-point field is not a
    // hittable target, and a later Win/Alt hold would change the character.
    [app typeText:@"q"];
    XCTAssertTrue([self logContains:@"down 81" within:8], @"key log missing \"down 81\": %@", [self keyLog].label);

    [self tapIdentifier:@"twilight.key.esc" expecting:@"down 27"];
    [self waitForLogContaining:@"up 27"];

    [self tapIdentifier:@"twilight.key.tab" expecting:@"down 9 "];
    [self waitForLogContaining:@"up 9 "];

    [self tapIdentifier:@"twilight.key.ctrl" expecting:@"down 162"];
    [self tapIdentifier:@"twilight.key.ctrl" expecting:@"up 162"];

    [self tapIdentifier:@"twilight.key.alt" expecting:@"down 164"];
    [self tapIdentifier:@"twilight.key.alt" expecting:@"up 164"];

    [self tapIdentifier:@"twilight.key.win" expecting:@"down 91"];
    [self tapIdentifier:@"twilight.key.win" expecting:@"up 91"];

    [self tapIdentifier:@"twilight.key.done"];
    NSPredicate *gone = [NSPredicate predicateWithFormat:@"exists == 0"];
    XCTNSPredicateExpectation *dismissed = [[XCTNSPredicateExpectation alloc] initWithPredicate:gone object:keyboard];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[dismissed] timeout:8], XCTWaiterResultCompleted, @"Done did not resign first responder");
    [self saveShot:@"keyboard-dismissed"];
}

- (void)scrollSettingsUntilHittable:(NSString *)identifier {
    XCUIElement *settings = [self waitForIdentifier:@"twilight.settings" timeout:4];
    XCUIElement *button = self.app.buttons[identifier];
    for (NSInteger i = 0; i < 8; i++) {
        if (button.exists && button.isHittable) {
            return;
        }
        [settings swipeUp];
        [self spinFor:0.3];
    }
}

- (void)testMetalFXToggleStartsStreamAndFallsBack {
    [self launchMode:@"metalfx"];
    [self scrollSettingsUntilHittable:@"twilight.metalfx.1"];
    [self tapIdentifier:@"twilight.metalfx.1"];
    XCUIElement *done = self.app.navigationBars[@"Settings"].buttons[@"Done"];
    if (!done.exists) {
        done = self.app.buttons[@"Done"];
    }
    XCTAssertTrue([done waitForExistenceWithTimeout:2], @"Settings Done button is missing");
    [done tap];

    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationLandscapeLeft];
    [self assertVideoSettled];
    XCUIElement *status = [self waitForIdentifier:@"twilight.metalfx.status" timeout:4];
    NSString *line = status.label.length > 0 ? status.label : [status.value description];
    // The simulator does not advertise MTLFXSpatialScaler. The stream stays
    // on the display layer, which is the fallback the setting promises.
    XCTAssertTrue([line containsString:@"fallback"], @"MetalFX status: %@", line);
    [self saveShot:@"metalfx-fallback"];
}

- (void)assertElement:(XCUIElement *)element matches:(XCUIElement *)other named:(NSString *)name {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
    CGRect elementFrame = CGRectZero;
    CGRect otherFrame = CGRectZero;
    BOOL matched = NO;
    while ([deadline timeIntervalSinceNow] > 0) {
        elementFrame = element.frame;
        otherFrame = other.frame;
        BOOL sized = elementFrame.size.width > 20 && elementFrame.size.height > 20;
        BOOL equal = fabs(elementFrame.origin.x - otherFrame.origin.x) < 2
            && fabs(elementFrame.origin.y - otherFrame.origin.y) < 2
            && fabs(elementFrame.size.width - otherFrame.size.width) < 2
            && fabs(elementFrame.size.height - otherFrame.size.height) < 2;
        if (sized && equal) {
            matched = YES;
            break;
        }
        [self spinFor:0.2];
    }
    XCTAssertTrue(matched, @"%@ frame %@ != %@", name, NSStringFromCGRect(elementFrame), NSStringFromCGRect(otherFrame));
    CGRect window = [self windowFrame];
    if (otherFrame.size.width < window.size.width - 8) {
        XCTAssertLessThan(elementFrame.size.width, window.size.width - 8, @"%@ filled the screen", name);
    }
}

- (void)testMetalFXSafeAreaLayerMatchesVideoFrame {
    XCUIApplication *app = [self launchMode:@"metalfx-safe"];
    [self scrollSettingsUntilHittable:@"Safe Area"];
    [self tapIdentifier:@"Safe Area"];
    [self scrollSettingsUntilHittable:@"twilight.metalfx.1"];
    [self tapIdentifier:@"twilight.metalfx.1"];
    XCUIElement *done = app.navigationBars[@"Settings"].buttons[@"Done"];
    if (!done.exists) {
        done = app.buttons[@"Done"];
    }
    XCTAssertTrue([done waitForExistenceWithTimeout:2], @"Settings Done button is missing");
    [done tap];

    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationLandscapeLeft];
    XCUIElement *video = [self waitForIdentifier:@"twilight.video" timeout:4];
    XCUIElement *metal = [self waitForIdentifier:@"twilight.metalfx.layer" timeout:4];
    [self assertElement:metal matches:video named:@"MetalFX layer"];
    XCUIElement *status = [self waitForIdentifier:@"twilight.metalfx.status" timeout:4];
    NSString *line = status.label.length > 0 ? status.label : [status.value description];
    XCTAssertTrue([line containsString:@"fallback"] || [line containsString:@"active"] || [line containsString:@"starting"],
                  @"MetalFX status: %@", line);
    [self saveShot:@"metalfx-safe-area"];
}

@end
