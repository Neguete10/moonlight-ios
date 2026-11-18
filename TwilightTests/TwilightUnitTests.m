//
//  TwilightUnitTests.m
//  TwilightUnitTests
//
//  Geometry and key mapping. These run inside the app process and do not
//  open a stream or touch the network.
//

#import <UIKit/UIKit.h>
#import <sys/types.h>
#import <XCTest/XCTest.h>
#import "StreamVideoLayout.h"
#import "MetalFXLayout.h"
#import "KeyboardSupport.h"
#import "TwilightOnScreenKeyboard.h"

@interface TwilightUnitTests : XCTestCase
@end

@implementation TwilightUnitTests

- (void)testLandscapeVideoIsCenteredAndFillsTheShortSide {
    CGRect bounds = CGRectMake(0, 0, 874, 402);
    CGRect video = [StreamVideoLayout videoRectForBounds:bounds streamAspectRatio:(16.0 / 9.0)];

    XCTAssertEqualWithAccuracy(video.size.height, 402, 0.5);
    XCTAssertEqualWithAccuracy(video.size.width, 402.0 * 16.0 / 9.0, 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetMidX(video), CGRectGetMidX(bounds), 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetMidY(video), CGRectGetMidY(bounds), 0.5);
    XCTAssertTrue(CGRectContainsRect(bounds, video));
    XCTAssertGreaterThan(video.size.width, video.size.height);
}

- (void)testPortraitContainerCenterSitsOutsideALandscapeScreen {
    // The storyboard view is 414x896. Sizing the picture once from that rect
    // centers it near y=448, which is below a landscape phone.
    CGRect portrait = CGRectMake(0, 0, 402, 874);
    CGRect video = [StreamVideoLayout videoRectForBounds:portrait streamAspectRatio:(16.0 / 9.0)];
    CGRect landscapeScreen = CGRectMake(0, 0, 874, 402);
    XCTAssertFalse(CGRectContainsRect(landscapeScreen, video));
    XCTAssertGreaterThan(CGRectGetMidY(video), CGRectGetMaxY(landscapeScreen));

    CGSize corrected = [StreamVideoLayout interfaceSizeForSize:portrait.size landscapeOnly:YES];
    CGRect fixed = [StreamVideoLayout videoRectForBounds:CGRectMake(0, 0, corrected.width, corrected.height)
                                      streamAspectRatio:(16.0 / 9.0)];
    CGRect correctedBounds = CGRectMake(0, 0, corrected.width, corrected.height);
    XCTAssertTrue(CGRectContainsRect(correctedBounds, fixed));
    XCTAssertEqualWithAccuracy(CGRectGetMidX(fixed), CGRectGetMidX(correctedBounds), 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetMidY(fixed), CGRectGetMidY(correctedBounds), 0.5);
    XCTAssertGreaterThan(fixed.size.width, fixed.size.height);
}

- (void)testRotationToTheOtherLandscapeSideKeepsTheSameCenteredRect {
    CGRect left = CGRectMake(0, 0, 932, 430);
    CGRect right = CGRectMake(0, 0, 932, 430);
    CGRect a = [StreamVideoLayout videoRectForBounds:left streamAspectRatio:(16.0 / 9.0)];
    CGRect b = [StreamVideoLayout videoRectForBounds:right streamAspectRatio:(16.0 / 9.0)];
    XCTAssertEqualWithAccuracy(a.origin.x, b.origin.x, 0.01);
    XCTAssertEqualWithAccuracy(a.origin.y, b.origin.y, 0.01);
    XCTAssertEqualWithAccuracy(a.size.width, b.size.width, 0.01);
    XCTAssertEqualWithAccuracy(a.size.height, b.size.height, 0.01);
}

- (void)testIPadPortraitSizeIsNotSwapped {
    CGSize portrait = CGSizeMake(834, 1194);
    CGSize kept = [StreamVideoLayout interfaceSizeForSize:portrait landscapeOnly:NO];
    XCTAssertEqualWithAccuracy(kept.width, 834, 0.01);
    XCTAssertEqualWithAccuracy(kept.height, 1194, 0.01);

    CGRect video = [StreamVideoLayout videoRectForBounds:CGRectMake(0, 0, kept.width, kept.height)
                                      streamAspectRatio:(16.0 / 9.0)];
    XCTAssertGreaterThan(video.size.width, video.size.height);
    XCTAssertTrue(CGRectContainsRect(CGRectMake(0, 0, kept.width, kept.height), video));
    XCTAssertEqualWithAccuracy(CGRectGetMidX(video), kept.width / 2.0, 0.5);
}

- (void)testAlreadyLandscapeSizeStaysPut {
    CGSize landscape = CGSizeMake(874, 402);
    CGSize same = [StreamVideoLayout interfaceSizeForSize:landscape landscapeOnly:YES];
    XCTAssertEqualWithAccuracy(same.width, 874, 0.01);
    XCTAssertEqualWithAccuracy(same.height, 402, 0.01);
}

- (void)testFullScreenPixelsAreLandscapeWhenTheWindowFrameIsStillPortrait {
    // iPhone 17 Pro logical size, @3x. window.frame reports the portrait pair.
    CGSize portrait = CGSizeMake(402, 874);
    UIEdgeInsets portraitInsets = UIEdgeInsetsMake(62, 0, 34, 0);
    CGSize full = [StreamVideoLayout streamPixelsForSize:portrait
                                                   insets:portraitInsets
                                                    scale:3
                                            landscapeOnly:YES
                                                fullBleed:YES];
    XCTAssertEqualWithAccuracy(full.width, 874 * 3, 0.5);
    XCTAssertEqualWithAccuracy(full.height, 402 * 3, 0.5);
    XCTAssertGreaterThan(full.width, full.height);

    CGSize safe = [StreamVideoLayout streamPixelsForSize:portrait
                                                   insets:portraitInsets
                                                    scale:3
                                            landscapeOnly:YES
                                                fullBleed:NO];
    XCTAssertEqualWithAccuracy(safe.width, (874 - 62 - 34) * 3, 0.5);
    XCTAssertEqualWithAccuracy(safe.height, 402 * 3, 0.5);
    XCTAssertGreaterThan(safe.width, safe.height);
}

- (void)testStoredPortraitResolutionIsRequestedAsLandscapeOnPhone {
    CGSize swapped = [StreamVideoLayout streamSizeForWidth:1206 height:2622 landscapeOnly:YES];
    XCTAssertEqualWithAccuracy(swapped.width, 2622, 0.01);
    XCTAssertEqualWithAccuracy(swapped.height, 1206, 0.01);

    CGSize preset = [StreamVideoLayout streamSizeForWidth:1280 height:720 landscapeOnly:YES];
    XCTAssertEqualWithAccuracy(preset.width, 1280, 0.01);
    XCTAssertEqualWithAccuracy(preset.height, 720, 0.01);

    CGSize pad = [StreamVideoLayout streamSizeForWidth:1206 height:2622 landscapeOnly:NO];
    XCTAssertEqualWithAccuracy(pad.width, 1206, 0.01);
    XCTAssertEqualWithAccuracy(pad.height, 2622, 0.01);
}

- (void)testEmptyBoundsProduceNoVideoRect {
    CGRect video = [StreamVideoLayout videoRectForBounds:CGRectZero streamAspectRatio:(16.0 / 9.0)];
    XCTAssertTrue(CGRectIsEmpty(video));
    video = [StreamVideoLayout videoRectForBounds:CGRectMake(0, 0, 800, 400) streamAspectRatio:0];
    XCTAssertTrue(CGRectIsEmpty(video));
}

- (void)testUpstreamToolbarKeysAndCodes {
    NSArray<TwilightOnScreenKey *> *keys = [TwilightOnScreenKeyboard toolbarKeys];
    NSArray<NSString *> *names = @[@"Done", @"Win", @"Esc", @"Tab", @"Shift", @"Ctrl", @"Alt", @"Del"];
    NSArray<NSNumber *> *codes = @[@0x00, @0x5B, @0x1B, @0x09, @0xA0, @0xA2, @0xA4, @0x2E];
    NSArray<NSNumber *> *toggles = @[@NO, @YES, @NO, @NO, @YES, @YES, @YES, @NO];
    XCTAssertEqual(keys.count, names.count);
    for (NSUInteger i = 0; i < keys.count; i++) {
        XCTAssertEqualObjects(keys[i].name, names[i]);
        XCTAssertEqual(keys[i].keyCode, codes[i].shortValue);
        XCTAssertEqual(keys[i].toggle, toggles[i].boolValue);
        XCTAssertTrue([keys[i].identifier hasPrefix:@"twilight.key."]);
    }
}

- (void)testHardwareArrowsFunctionKeysAndModifiersMapToWindowsCodes {
    if (@available(iOS 13.4, *)) {
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeyboardLeftArrow extendedModifier:NULL], 0x25);
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeyboardUpArrow extendedModifier:NULL], 0x26);
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeyboardRightArrow extendedModifier:NULL], 0x27);
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeyboardDownArrow extendedModifier:NULL], 0x28);
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeyboardF1 extendedModifier:NULL], 0x70);
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeyboardF12 extendedModifier:NULL], 0x7B);
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeyboardEscape extendedModifier:NULL], 0x1B);
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeyboardTab extendedModifier:NULL], 0x09);
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeyboardLeftGUI extendedModifier:NULL], 0x5B);
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeyboardLeftControl extendedModifier:NULL], 0xA2);
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeyboardLeftAlt extendedModifier:NULL], 0xA4);
        char extended = 0;
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:UIKeyboardHIDUsageKeypadEnter extendedModifier:&extended], 0x0D);
        XCTAssertNotEqual(extended, 0);
        XCTAssertEqual([KeyboardSupport virtualKeyCodeForHIDUsage:0xFFFFFFF extendedModifier:NULL], 0);
    }
    else {
        XCTFail(@"HID key mapping requires iOS 13.4");
    }
}

- (void)testCharacterTranslationMatchesUpstreamLetters {
    struct KeyEvent lower = [KeyboardSupport translateKeyEvent:'a' withModifierFlags:0];
    XCTAssertEqual(lower.keycode, 0x41);
    XCTAssertEqual(lower.modifier, 0);

    struct KeyEvent upper = [KeyboardSupport translateKeyEvent:'A' withModifierFlags:0];
    XCTAssertEqual(upper.keycode, 0x41);
    XCTAssertNotEqual(upper.modifier, 0);

    struct KeyEvent tab = [KeyboardSupport translateKeyEvent:'\t' withModifierFlags:0];
    XCTAssertEqual(tab.keycode, 0x09);

    struct KeyEvent space = [KeyboardSupport translateKeyEvent:' ' withModifierFlags:0];
    XCTAssertEqual(space.keycode, 0x20);
}

- (void)testMetalFXScaleChoicesRoundTrip {
    XCTAssertEqual([MetalFXLayout scalePercentForChoiceIndex:0], 50);
    XCTAssertEqual([MetalFXLayout scalePercentForChoiceIndex:1], 67);
    XCTAssertEqual([MetalFXLayout scalePercentForChoiceIndex:2], 75);
    XCTAssertEqual([MetalFXLayout scalePercentForChoiceIndex:3], 0);
    XCTAssertEqual([MetalFXLayout scalePercentForChoiceIndex:9], 0);
    XCTAssertEqual([MetalFXLayout choiceIndexForScalePercent:50], 0);
    XCTAssertEqual([MetalFXLayout choiceIndexForScalePercent:67], 1);
    XCTAssertEqual([MetalFXLayout choiceIndexForScalePercent:75], 2);
    XCTAssertEqual([MetalFXLayout choiceIndexForScalePercent:0], 3);
    XCTAssertEqual([MetalFXLayout normalizedScalePercent:66], 0);
    XCTAssertEqual([MetalFXLayout choiceIndexForScalePercent:100], 3);
}

- (void)testMetalFXHostSizeUsesScreenFractionOnALandscapePhone {
    // iPhone 17 Pro pixels. window.frame still reports the portrait pair.
    CGSize portraitPixels = CGSizeMake(1206, 2622);
    CGSize half = [MetalFXLayout hostSizeForNativePixels:portraitPixels
                                            chosenWidth:1280
                                           chosenHeight:720
                                           scalePercent:50
                                                enabled:YES
                                          landscapeOnly:YES];
    XCTAssertEqual(half.width, 1310);
    XCTAssertEqual(half.height, 602);
    XCTAssertGreaterThan(half.width, half.height);

    CGSize twoThirds = [MetalFXLayout hostSizeForNativePixels:portraitPixels
                                                 chosenWidth:3840
                                                chosenHeight:2160
                                                scalePercent:67
                                                     enabled:YES
                                               landscapeOnly:YES];
    XCTAssertEqual(twoThirds.width, 1748);
    XCTAssertEqual(twoThirds.height, 804);

    CGSize threeQuarters = [MetalFXLayout hostSizeForNativePixels:portraitPixels
                                                     chosenWidth:1920
                                                    chosenHeight:1080
                                                    scalePercent:75
                                                         enabled:YES
                                                   landscapeOnly:YES];
    XCTAssertEqual(threeQuarters.width, 1966);
    XCTAssertEqual(threeQuarters.height, 904);

    CGSize alreadyLandscape = [MetalFXLayout hostSizeForNativePixels:CGSizeMake(2622, 1206)
                                                         chosenWidth:1280
                                                        chosenHeight:720
                                                        scalePercent:50
                                                             enabled:YES
                                                       landscapeOnly:YES];
    XCTAssertEqual(alreadyLandscape.width, 1310);
    XCTAssertEqual(alreadyLandscape.height, 602);
}

- (void)testMetalFXHostSizeKeepsTheChosenResolutionWhenUpscalingIsOff {
    CGSize native = CGSizeMake(1206, 2622);
    CGSize off = [MetalFXLayout hostSizeForNativePixels:native
                                           chosenWidth:1920
                                          chosenHeight:1080
                                          scalePercent:50
                                               enabled:NO
                                         landscapeOnly:YES];
    XCTAssertEqual(off.width, 1920);
    XCTAssertEqual(off.height, 1080);

    CGSize chosen = [MetalFXLayout hostSizeForNativePixels:native
                                              chosenWidth:1280
                                             chosenHeight:720
                                             scalePercent:0
                                                  enabled:YES
                                            landscapeOnly:YES];
    XCTAssertEqual(chosen.width, 1280);
    XCTAssertEqual(chosen.height, 720);

    CGSize storedPortrait = [MetalFXLayout hostSizeForNativePixels:native
                                                      chosenWidth:720
                                                     chosenHeight:1280
                                                     scalePercent:0
                                                          enabled:YES
                                                    landscapeOnly:YES];
    XCTAssertEqual(storedPortrait.width, 1280);
    XCTAssertEqual(storedPortrait.height, 720);

    CGSize pad = [MetalFXLayout hostSizeForNativePixels:CGSizeMake(2048, 2732)
                                           chosenWidth:1280
                                          chosenHeight:720
                                          scalePercent:50
                                               enabled:YES
                                         landscapeOnly:NO];
    XCTAssertEqual(pad.width, 1024);
    XCTAssertEqual(pad.height, 1366);
}

- (void)testMetalFXOutputRectFitsAndFlipsForMetal {
    CGSize drawable = CGSizeMake(2622, 1206);
    CGRect output = [MetalFXLayout outputRectForDrawablePixels:drawable streamAspectRatio:(16.0 / 9.0)];
    XCTAssertEqualWithAccuracy(output.size.height, 1206, 1);
    XCTAssertEqualWithAccuracy(output.size.width, 2144, 1);
    XCTAssertEqualWithAccuracy(output.origin.y, 0, 1);
    XCTAssertTrue(CGRectContainsRect(CGRectMake(0, 0, drawable.width, drawable.height), output));
    XCTAssertGreaterThan(output.size.width, output.size.height);

    CGRect viewport = [MetalFXLayout metalViewportForOutputRect:output drawableHeight:drawable.height];
    XCTAssertEqualWithAccuracy(viewport.origin.y, drawable.height - CGRectGetMaxY(output), 0.01);
    XCTAssertEqualWithAccuracy(viewport.size.width, output.size.width, 0.01);
    XCTAssertEqualWithAccuracy(viewport.size.height, output.size.height, 0.01);

    CGRect square = [MetalFXLayout outputRectForDrawablePixels:CGSizeMake(1000, 1000) streamAspectRatio:(16.0 / 9.0)];
    CGRect squareViewport = [MetalFXLayout metalViewportForOutputRect:square drawableHeight:1000];
    XCTAssertGreaterThan(square.origin.y, 0);
    XCTAssertTrue(CGRectContainsRect(CGRectMake(0, 0, 1000, 1000), square));
    XCTAssertEqualWithAccuracy(squareViewport.origin.y, 1000 - CGRectGetMaxY(square), 0.01);

    CGRect left = [MetalFXLayout outputRectForDrawablePixels:drawable streamAspectRatio:(16.0 / 9.0)];
    CGRect right = [MetalFXLayout outputRectForDrawablePixels:CGSizeMake(2622, 1206) streamAspectRatio:(16.0 / 9.0)];
    XCTAssertEqualWithAccuracy(left.origin.x, right.origin.x, 0.01);
    XCTAssertEqualWithAccuracy(left.size.width, right.size.width, 0.01);
}

- (void)testMetalFXCanUpscaleOnlyWhenTheScreenIsLarger {
    XCTAssertTrue([MetalFXLayout canUpscaleInput:CGSizeMake(1280, 720) toOutput:CGSizeMake(2144, 1206)]);
    XCTAssertTrue([MetalFXLayout canUpscaleInput:CGSizeMake(1310, 602) toOutput:CGSizeMake(2622, 1206)]);
    XCTAssertFalse([MetalFXLayout canUpscaleInput:CGSizeMake(3840, 2160) toOutput:CGSizeMake(2144, 1206)]);
    XCTAssertFalse([MetalFXLayout canUpscaleInput:CGSizeMake(2144, 1206) toOutput:CGSizeMake(2144, 1206)]);
    XCTAssertFalse([MetalFXLayout canUpscaleInput:CGSizeMake(0, 0) toOutput:CGSizeMake(100, 100)]);
}

- (void)testMetalFXStatsLineNamesTheResolutions {
    XCTAssertEqualObjects([MetalFXLayout statsLineForMode:MetalFXStatsModeOff input:CGSizeZero output:CGSizeZero], @"MetalFX off");
    XCTAssertEqualObjects([MetalFXLayout statsLineForMode:MetalFXStatsModeFallback input:CGSizeZero output:CGSizeZero], @"MetalFX fallback");
    XCTAssertEqualObjects([MetalFXLayout statsLineForMode:MetalFXStatsModeStarting input:CGSizeZero output:CGSizeZero], @"MetalFX starting");
    NSString *active = [MetalFXLayout statsLineForMode:MetalFXStatsModeActive input:CGSizeMake(1280, 720) output:CGSizeMake(2622, 1206)];
    XCTAssertEqualObjects(active, @"MetalFX active 1280x720 -> 2622x1206");
    XCTAssertEqualObjects([MetalFXLayout statsLineForMode:MetalFXStatsModeActive input:CGSizeZero output:CGSizeZero], @"MetalFX active");
}

@end
