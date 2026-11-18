//
//  TwilightUnitTests.m
//  TwilightUnitTests
//
//  Geometry and key mapping. These run inside the app process and do not
//  open a stream or touch the network.
//

#import <UIKit/UIKit.h>
#import <math.h>
#import <sys/types.h>
#import <XCTest/XCTest.h>
#import "StreamVideoLayout.h"
#import "MetalFXLayout.h"
#import "KeyboardSupport.h"
#import "TwilightOnScreenKeyboard.h"
#import "SpatialAudio.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <stdint.h>
#import <string.h>

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

- (void)testMetalFXKeepsTheChosenResolutionAndUpscalesOnlyWhenTheScreenIsLarger {
    CGSize chosen = [MetalFXLayout hostSizeForChosenWidth:1280 height:720 landscapeOnly:YES];
    XCTAssertEqual(chosen.width, 1280);
    XCTAssertEqual(chosen.height, 720);
    CGSize storedPortrait = [MetalFXLayout hostSizeForChosenWidth:720 height:1280 landscapeOnly:YES];
    XCTAssertEqual(storedPortrait.width, 1280);
    XCTAssertEqual(storedPortrait.height, 720);

    CGSize phone = CGSizeMake(1206, 2622);
    XCTAssertTrue([MetalFXLayout shouldUpscaleStreamWidth:1280 height:720 screenPixels:phone landscapeOnly:YES]);
    XCTAssertTrue([MetalFXLayout shouldUpscaleStreamWidth:1920 height:1080 screenPixels:phone landscapeOnly:YES]);
    XCTAssertFalse([MetalFXLayout shouldUpscaleStreamWidth:3840 height:2160 screenPixels:phone landscapeOnly:YES]);
    XCTAssertFalse([MetalFXLayout shouldUpscaleStreamWidth:2622 height:1206 screenPixels:phone landscapeOnly:YES]);
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

- (void)testMetalFXSafeAreaFractionAndLayerMatchTheDisplayRect {
    // iPhone 17 Pro points, still reported portrait, with the island and home insets.
    CGSize portrait = CGSizeMake(402, 874);
    UIEdgeInsets insets = UIEdgeInsetsMake(62, 0, 34, 0);
    CGSize safe = [StreamVideoLayout streamPixelsForSize:portrait
                                                   insets:insets
                                                    scale:3
                                            landscapeOnly:YES
                                                fullBleed:NO];
    CGSize full = [StreamVideoLayout streamPixelsForSize:portrait
                                                   insets:insets
                                                    scale:3
                                            landscapeOnly:YES
                                                fullBleed:YES];
    XCTAssertEqualWithAccuracy(safe.width, 2334, 0.5);
    XCTAssertEqualWithAccuracy(safe.height, 1206, 0.5);
    XCTAssertEqualWithAccuracy(full.width, 2622, 0.5);
    XCTAssertGreaterThan(full.width, safe.width);

    CGSize safeBase = [MetalFXLayout nativeBaseForChosenWidth:(NSInteger)llround(safe.width)
                                                        height:(NSInteger)llround(safe.height)
                                                    safePixels:safe
                                                    fullPixels:full
                                                 landscapeOnly:YES];
    XCTAssertEqualWithAccuracy(safeBase.width, safe.width, 0.5);
    XCTAssertEqualWithAccuracy(safeBase.height, safe.height, 0.5);

    CGSize safeHost = [MetalFXLayout hostSizeForChosenWidth:(NSInteger)llround(safe.width)
                                                      height:(NSInteger)llround(safe.height)
                                               landscapeOnly:YES];
    XCTAssertEqualWithAccuracy(safeHost.width, safe.width, 0.5);
    XCTAssertEqualWithAccuracy(safeHost.height, safe.height, 0.5);
    XCTAssertFalse([MetalFXLayout shouldUpscaleStreamWidth:(NSInteger)llround(safe.width)
                                                     height:(NSInteger)llround(safe.height)
                                               screenPixels:full
                                              landscapeOnly:YES]);
    XCTAssertFalse([MetalFXLayout shouldUpscaleStreamWidth:(NSInteger)llround(full.width)
                                                     height:(NSInteger)llround(full.height)
                                               screenPixels:full
                                              landscapeOnly:YES]);

    CGSize fixedBase = [MetalFXLayout nativeBaseForChosenWidth:1920
                                                         height:1080
                                                     safePixels:safe
                                                     fullPixels:full
                                                  landscapeOnly:YES];
    XCTAssertEqual(fixedBase.width, 1920);
    XCTAssertEqual(fixedBase.height, 1080);
    XCTAssertTrue([MetalFXLayout shouldUpscaleStreamWidth:1920
                                                   height:1080
                                             screenPixels:full
                                            landscapeOnly:YES]);

    CGRect bounds = CGRectMake(0, 0, 874, 402);
    CGFloat safeAspect = safe.width / safe.height;
    CGRect safeLayer = [MetalFXLayout layerRectForBounds:bounds streamAspectRatio:safeAspect];
    CGRect safeVideo = [StreamVideoLayout videoRectForBounds:bounds streamAspectRatio:safeAspect];
    XCTAssertEqualWithAccuracy(safeLayer.origin.x, safeVideo.origin.x, 0.5);
    XCTAssertEqualWithAccuracy(safeLayer.origin.y, safeVideo.origin.y, 0.5);
    XCTAssertEqualWithAccuracy(safeLayer.size.width, safeVideo.size.width, 0.5);
    XCTAssertEqualWithAccuracy(safeLayer.size.height, safeVideo.size.height, 0.5);
    XCTAssertLessThan(safeLayer.size.width, bounds.size.width - 1);
    XCTAssertEqualWithAccuracy(safeLayer.size.height, bounds.size.height, 0.5);

    CGRect fullLayer = [MetalFXLayout layerRectForBounds:bounds streamAspectRatio:(full.width / full.height)];
    CGRect fullVideo = [StreamVideoLayout videoRectForBounds:bounds streamAspectRatio:(full.width / full.height)];
    XCTAssertEqualWithAccuracy(fullLayer.size.width, fullVideo.size.width, 0.5);
    XCTAssertEqualWithAccuracy(fullLayer.size.width, bounds.size.width, 1);
    XCTAssertEqualWithAccuracy(fullLayer.size.height, bounds.size.height, 1);

    CGRect fixedLayer = [MetalFXLayout layerRectForBounds:bounds streamAspectRatio:(16.0 / 9.0)];
    CGRect fixedVideo = [StreamVideoLayout videoRectForBounds:bounds streamAspectRatio:(16.0 / 9.0)];
    XCTAssertEqualWithAccuracy(fixedLayer.origin.x, fixedVideo.origin.x, 0.5);
    XCTAssertEqualWithAccuracy(fixedLayer.size.width, fixedVideo.size.width, 0.5);
    XCTAssertEqualWithAccuracy(fixedLayer.size.height, fixedVideo.size.height, 0.5);
    XCTAssertLessThan(fixedLayer.size.width, bounds.size.width - 1);
    XCTAssertLessThan(fixedLayer.size.width, safeLayer.size.width);
}

- (void)testMetalFXStatsLineNamesTheResolutions {
    XCTAssertEqualObjects([MetalFXLayout statsLineForMode:MetalFXStatsModeOff input:CGSizeZero output:CGSizeZero], @"MetalFX off");
    XCTAssertEqualObjects([MetalFXLayout statsLineForMode:MetalFXStatsModeFallback input:CGSizeZero output:CGSizeZero], @"MetalFX fallback");
    XCTAssertEqualObjects([MetalFXLayout statsLineForMode:MetalFXStatsModeStarting input:CGSizeZero output:CGSizeZero], @"MetalFX starting");
    NSString *active = [MetalFXLayout statsLineForMode:MetalFXStatsModeActive input:CGSizeMake(1280, 720) output:CGSizeMake(2622, 1206)];
    XCTAssertEqualObjects(active, @"MetalFX active 1280x720 -> 2622x1206");
    XCTAssertEqualObjects([MetalFXLayout statsLineForMode:MetalFXStatsModeActive input:CGSizeZero output:CGSizeZero], @"MetalFX active");
    XCTAssertEqualObjects([MetalFXLayout statsLineForMode:MetalFXStatsModeIdle input:CGSizeMake(2622, 1206) output:CGSizeZero], @"MetalFX idle 2622x1206");
    XCTAssertEqualObjects([MetalFXLayout statsLineForMode:MetalFXStatsModeIdle input:CGSizeZero output:CGSizeZero], @"MetalFX idle");
    NSString *timed = [MetalFXLayout statsLine:@"MetalFX active 1280x720 -> 2334x1206" appendingLatencyMs:4.16];
    XCTAssertEqualObjects(timed, @"MetalFX active 1280x720 -> 2334x1206 +4.2 ms");
    XCTAssertEqualObjects([MetalFXLayout statsLine:@"MetalFX off" appendingLatencyMs:-1], @"MetalFX off");
    NSString *staged = [MetalFXLayout statsLine:@"MetalFX active 1280x720 -> 2334x1206" appendingLatencyMs:73.2 stage:@"drawable"];
    XCTAssertEqualObjects(staged, @"MetalFX active 1280x720 -> 2334x1206 +73.2 ms drawable");
    NSString *dropped = [MetalFXLayout statsLine:@"MetalFX active 1280x720 -> 2334x1206" appendingLatencyMs:8.2 stage:@"present" droppedFrames:12];
    XCTAssertEqualObjects(dropped, @"MetalFX active 1280x720 -> 2334x1206 +8.2 ms present drop 12");
    XCTAssertEqualObjects([MetalFXLayout dominantStageNameForQueueMs:0.4
                                                            textureMs:0.2
                                                                yuvMs:0.3
                                                             scalerMs:1.1
                                                           drawableMs:70
                                                                gpuMs:2.0
                                                             presentMs:8.0], @"drawable");
    XCTAssertEqualObjects([MetalFXLayout dominantStageNameForQueueMs:0.1
                                                            textureMs:0.1
                                                                yuvMs:0.1
                                                             scalerMs:0.4
                                                           drawableMs:0.2
                                                                gpuMs:1.5
                                                             presentMs:6.0], @"present");
}

- (void)testMetalFXScheduleDropsStaleFramesAndRejectsOverlappedPresents {
    MetalFXFrameSchedule *schedule = [[MetalFXFrameSchedule alloc] init];
    for (uint64_t frame = 1; frame <= 50; frame++) {
        [schedule submitFrame:frame];
    }
    XCTAssertEqual(schedule.submittedFrames, 50);
    XCTAssertEqual(schedule.droppedFrames, 49);
    XCTAssertEqual([schedule beginPresent], 50);
    XCTAssertEqual([schedule beginPresent], 0);
    XCTAssertTrue(schedule.presentInFlight);
    XCTAssertFalse([schedule tryBeginPresent]);
    [schedule endPresent];
    XCTAssertFalse(schedule.presentInFlight);

    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0);
    dispatch_apply(8, queue, ^(size_t lane) {
        for (int i = 0; i < 400; i++) {
            [schedule submitFrame:(uint64_t)(lane * 1000 + (uint64_t)i + 1)];
            uint64_t claimed = [schedule beginPresent];
            if (claimed != 0) {
                [schedule endPresent];
            }
        }
    });
    while ([schedule beginPresent] != 0) {
        [schedule endPresent];
    }
    XCTAssertFalse(schedule.presentInFlight);
    XCTAssertEqual(schedule.presentedFrames + schedule.droppedFrames, schedule.submittedFrames);
}

- (void)testSpatialLayoutTagsMatchTheSurroundBed {
    XCTAssertEqual(TwilightSpatialLayoutForChannelCount(6), TwilightSpatialLayout51);
    XCTAssertEqual(TwilightSpatialLayoutForChannelCount(8), TwilightSpatialLayout71);
    XCTAssertEqual(TwilightSpatialLayoutForChannelCount(2), TwilightSpatialLayoutNone);
    XCTAssertEqual(TwilightSpatialLayoutForChannelCount(1), TwilightSpatialLayoutNone);
    XCTAssertEqual(TwilightSpatialLayoutForChannelCount(4), TwilightSpatialLayoutNone);
    XCTAssertEqual(TwilightSpatialLayoutForChannelCount(12), TwilightSpatialLayoutNone);

    XCTAssertEqualObjects(TwilightSpatialLayoutName(TwilightSpatialLayout51), @"5.1");
    XCTAssertEqualObjects(TwilightSpatialLayoutName(TwilightSpatialLayout71), @"7.1");
    XCTAssertEqualObjects(TwilightSpatialLayoutName(TwilightSpatialLayoutNone), @"stereo");

    XCTAssertEqual(TwilightSpatialChannelLayoutTag(6), (uint32_t)kAudioChannelLayoutTag_WAVE_5_1_B);
    XCTAssertEqual(TwilightSpatialChannelLayoutTag(8), (uint32_t)kAudioChannelLayoutTag_WAVE_7_1);
    XCTAssertEqual(TwilightSpatialChannelLayoutTag(2), 0u);
    XCTAssertEqual(TwilightSpatialChannelLayoutTag(0), 0u);
}

- (void)testSpatialRouteKinds {
    XCTAssertEqual(TwilightSpatialRouteKindForPort(AVAudioSessionPortHeadphones), TwilightSpatialRouteHeadphones);
    XCTAssertEqual(TwilightSpatialRouteKindForPort(AVAudioSessionPortBluetoothA2DP), TwilightSpatialRouteHeadphones);
    XCTAssertEqual(TwilightSpatialRouteKindForPort(AVAudioSessionPortBluetoothHFP), TwilightSpatialRouteHeadphones);
    XCTAssertEqual(TwilightSpatialRouteKindForPort(AVAudioSessionPortBluetoothLE), TwilightSpatialRouteHeadphones);
    XCTAssertEqual(TwilightSpatialRouteKindForPort(AVAudioSessionPortAirPlay), TwilightSpatialRouteHeadphones);
    XCTAssertEqual(TwilightSpatialRouteKindForPort(AVAudioSessionPortBuiltInSpeaker), TwilightSpatialRouteSpeakers);
    XCTAssertEqual(TwilightSpatialRouteKindForPort(AVAudioSessionPortBuiltInReceiver), TwilightSpatialRouteSpeakers);
    XCTAssertEqual(TwilightSpatialRouteKindForPort(AVAudioSessionPortHDMI), TwilightSpatialRouteExternal);
    XCTAssertEqual(TwilightSpatialRouteKindForPort(AVAudioSessionPortUSBAudio), TwilightSpatialRouteExternal);
    XCTAssertEqual(TwilightSpatialRouteKindForPort(AVAudioSessionPortCarAudio), TwilightSpatialRouteExternal);
    XCTAssertEqual(TwilightSpatialRouteKindForPort(nil), TwilightSpatialRouteExternal);
    XCTAssertEqual(TwilightSpatialRouteKindForPort(@""), TwilightSpatialRouteExternal);
}

- (void)testSpatialStatusLine {
    NSString *off = TwilightSpatialStatusLine(NO, NO, NO, TwilightSpatialLayoutNone, TwilightSpatialRouteSpeakers, NO, NO);
    XCTAssertEqualObjects(off, @"Spatial audio off");

    NSString *active = TwilightSpatialStatusLine(YES, YES, NO, TwilightSpatialLayout71, TwilightSpatialRouteHeadphones, NO, NO);
    XCTAssertEqualObjects(active, @"Spatial audio active 7.1 headphones");

    NSString *tracked = TwilightSpatialStatusLine(YES, YES, YES, TwilightSpatialLayout51, TwilightSpatialRouteHeadphones, NO, NO);
    XCTAssertEqualObjects(tracked, @"Spatial audio active 5.1 headphones, head tracking");

    NSString *speakers = TwilightSpatialStatusLine(YES, YES, YES, TwilightSpatialLayout71, TwilightSpatialRouteSpeakers, NO, NO);
    XCTAssertEqualObjects(speakers, @"Spatial audio active 7.1 speakers");

    NSString *fallback = TwilightSpatialStatusLine(YES, NO, NO, TwilightSpatialLayout51, TwilightSpatialRouteSpeakers, YES, NO);
    XCTAssertEqualObjects(fallback, @"Spatial audio fallback 5.1");

    NSString *passthrough = TwilightSpatialStatusLine(YES, NO, NO, TwilightSpatialLayout71, TwilightSpatialRouteExternal, NO, YES);
    XCTAssertEqualObjects(passthrough, @"Spatial audio passthrough 7.1");
}

- (void)testSpatialDownmixPlacesEachBedChannel {
    int16_t out[2] = {0, 0};

    int16_t left[6] = {1000, 0, 0, 0, 0, 0};
    TwilightSpatialDownmixToStereo(left, 1, 6, out);
    XCTAssertEqual(out[0], 1000);
    XCTAssertEqual(out[1], 0);

    int16_t right[6] = {0, 1000, 0, 0, 0, 0};
    TwilightSpatialDownmixToStereo(right, 1, 6, out);
    XCTAssertEqual(out[0], 0);
    XCTAssertEqual(out[1], 1000);

    int16_t center[6] = {0, 0, 1000, 0, 0, 0};
    TwilightSpatialDownmixToStereo(center, 1, 6, out);
    XCTAssertEqual(out[0], 707);
    XCTAssertEqual(out[1], 707);

    int16_t lfe[6] = {0, 0, 0, 1000, 0, 0};
    TwilightSpatialDownmixToStereo(lfe, 1, 6, out);
    XCTAssertEqual(out[0], 500);
    XCTAssertEqual(out[1], 500);

    int16_t backLeft[6] = {0, 0, 0, 0, 1000, 0};
    TwilightSpatialDownmixToStereo(backLeft, 1, 6, out);
    XCTAssertEqual(out[0], 707);
    XCTAssertEqual(out[1], 0);

    int16_t backRight[6] = {0, 0, 0, 0, 0, 1000};
    TwilightSpatialDownmixToStereo(backRight, 1, 6, out);
    XCTAssertEqual(out[0], 0);
    XCTAssertEqual(out[1], 707);

    int16_t sideLeft[8] = {0, 0, 0, 0, 0, 0, 1000, 0};
    TwilightSpatialDownmixToStereo(sideLeft, 1, 8, out);
    XCTAssertEqual(out[0], 707);
    XCTAssertEqual(out[1], 0);

    int16_t sideRight[8] = {0, 0, 0, 0, 0, 0, 0, 1000};
    TwilightSpatialDownmixToStereo(sideRight, 1, 8, out);
    XCTAssertEqual(out[0], 0);
    XCTAssertEqual(out[1], 707);

    int16_t hot[6] = {30000, 0, 30000, 0, 30000, 0};
    TwilightSpatialDownmixToStereo(hot, 1, 6, out);
    XCTAssertEqual(out[0], INT16_MAX);
    XCTAssertEqual(out[1], (int16_t)((30000 * 707) / 1000));
}

- (void)testSpatialSettingsDefaultOffAndRoundTrip {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL audio = TwilightSpatialAudioEnabled();
    BOOL head = TwilightSpatialHeadTrackingEnabled();

    [defaults removeObjectForKey:TwilightSpatialAudioEnabledKey()];
    [defaults removeObjectForKey:TwilightSpatialHeadTrackingEnabledKey()];
    XCTAssertFalse(TwilightSpatialAudioEnabled());
    XCTAssertFalse(TwilightSpatialHeadTrackingEnabled());
    XCTAssertEqual(TwilightSpatialSurroundChannelCount(NO), 0);
    XCTAssertEqual(TwilightSpatialSurroundChannelCount(YES), 8);
    XCTAssertEqualObjects(TwilightSpatialCurrentStatusLine(), @"Spatial audio off");

    TwilightSpatialSetAudioEnabled(YES);
    TwilightSpatialSetHeadTrackingEnabled(YES);
    XCTAssertTrue(TwilightSpatialAudioEnabled());
    XCTAssertTrue(TwilightSpatialHeadTrackingEnabled());
    XCTAssertEqual(TwilightSpatialSurroundChannelCount(TwilightSpatialAudioEnabled()), 8);

    TwilightSpatialSetAudioEnabled(NO);
    XCTAssertFalse(TwilightSpatialAudioEnabled());
    XCTAssertTrue(TwilightSpatialHeadTrackingEnabled());
    XCTAssertEqualObjects(TwilightSpatialCurrentStatusLine(), @"Spatial audio off");

    TwilightSpatialSetAudioEnabled(audio);
    TwilightSpatialSetHeadTrackingEnabled(head);
}

- (void)testSpatialRenderAcceptsInterleavedAndPlanarBuffers {
    enum { frames = 4 };
    float left[frames] = {0.25f, 0.5f, -0.25f, -1.0f};
    float right[frames] = {1.0f, 0.0f, 0.5f, 0.125f};
    float interleaved[frames * 2];
    memset(interleaved, 0x5a, sizeof(interleaved));
    uint8_t canary[32];
    memset(canary, 0xab, sizeof(canary));

    // RemoteIO's packed stereo list has one buffer. A second slot may sit
    // next to it in memory; writing it is the device crash.
    struct {
        UInt32 mNumberBuffers;
        AudioBuffer mBuffers[2];
    } packed;
    memset(&packed, 0, sizeof(packed));
    packed.mNumberBuffers = 1;
    packed.mBuffers[0].mNumberChannels = 2;
    packed.mBuffers[0].mDataByteSize = sizeof(interleaved);
    packed.mBuffers[0].mData = interleaved;
    packed.mBuffers[1].mNumberChannels = 1;
    packed.mBuffers[1].mDataByteSize = sizeof(canary);
    packed.mBuffers[1].mData = canary;

    XCTAssertTrue(TwilightSpatialRenderStereo((AudioBufferList *)&packed, frames, left, right, YES));
    for (UInt32 frame = 0; frame < frames; frame++) {
        XCTAssertEqualWithAccuracy(interleaved[frame * 2], left[frame], 0.0001f);
        XCTAssertEqualWithAccuracy(interleaved[frame * 2 + 1], right[frame], 0.0001f);
    }
    uint8_t expectedCanary[32];
    memset(expectedCanary, 0xab, sizeof(expectedCanary));
    XCTAssertEqual(memcmp(canary, expectedCanary, sizeof(canary)), 0);

    packed.mNumberBuffers = 2;
    memset(interleaved, 0x5a, sizeof(interleaved));
    XCTAssertTrue(TwilightSpatialRenderStereo((AudioBufferList *)&packed, frames, left, right, YES));
    XCTAssertEqualWithAccuracy(interleaved[0], left[0], 0.0001f);
    XCTAssertEqualWithAccuracy(interleaved[1], right[0], 0.0001f);
    XCTAssertEqual(memcmp(canary, expectedCanary, sizeof(canary)), 0);

    float saved = interleaved[0];
    packed.mNumberBuffers = 1;
    packed.mBuffers[0].mDataByteSize = sizeof(float);
    XCTAssertFalse(TwilightSpatialRenderStereo((AudioBufferList *)&packed, frames, left, right, YES));
    XCTAssertEqualWithAccuracy(interleaved[0], saved, 0.0001f);

    float planarLeft[frames];
    float planarRight[frames];
    memset(planarLeft, 0x11, sizeof(planarLeft));
    memset(planarRight, 0x22, sizeof(planarRight));
    struct {
        UInt32 mNumberBuffers;
        AudioBuffer mBuffers[2];
    } planar;
    memset(&planar, 0, sizeof(planar));
    planar.mNumberBuffers = 2;
    planar.mBuffers[0].mNumberChannels = 1;
    planar.mBuffers[0].mDataByteSize = sizeof(planarLeft);
    planar.mBuffers[0].mData = planarLeft;
    planar.mBuffers[1].mNumberChannels = 1;
    planar.mBuffers[1].mDataByteSize = sizeof(planarRight);
    planar.mBuffers[1].mData = planarRight;
    XCTAssertTrue(TwilightSpatialRenderStereo((AudioBufferList *)&planar, frames, left, right, NO));
    for (UInt32 frame = 0; frame < frames; frame++) {
        XCTAssertEqualWithAccuracy(planarLeft[frame], left[frame], 0.0001f);
        XCTAssertEqualWithAccuracy(planarRight[frame], right[frame], 0.0001f);
    }

    planar.mBuffers[1].mDataByteSize = sizeof(float);
    float untouched = planarRight[1];
    XCTAssertFalse(TwilightSpatialRenderStereo((AudioBufferList *)&planar, frames, left, right, NO));
    XCTAssertEqualWithAccuracy(planarRight[1], untouched, 0.0001f);
    planar.mBuffers[1].mData = NULL;
    planar.mBuffers[1].mDataByteSize = sizeof(planarRight);
    XCTAssertFalse(TwilightSpatialRenderStereo((AudioBufferList *)&planar, frames, left, right, NO));

    float bed[] = {1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f, 7.0f, 8.0f, 9.0f, 10.0f, 11.0f, 12.0f};
    float channels[6][2];
    memset(channels, 0, sizeof(channels));
    struct {
        UInt32 mNumberBuffers;
        AudioBuffer mBuffers[6];
    } mixer;
    memset(&mixer, 0, sizeof(mixer));
    mixer.mNumberBuffers = 6;
    for (UInt32 channel = 0; channel < 6; channel++) {
        mixer.mBuffers[channel].mNumberChannels = 1;
        mixer.mBuffers[channel].mDataByteSize = sizeof(channels[channel]);
        mixer.mBuffers[channel].mData = channels[channel];
    }
    XCTAssertTrue(TwilightSpatialRenderDeinterleaved((AudioBufferList *)&mixer, 2, 6, bed));
    XCTAssertEqualWithAccuracy(channels[0][0], 1.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(channels[1][0], 2.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(channels[5][0], 6.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(channels[0][1], 7.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(channels[5][1], 12.0f, 0.0001f);
    mixer.mNumberBuffers = 1;
    XCTAssertFalse(TwilightSpatialRenderDeinterleaved((AudioBufferList *)&mixer, 2, 6, bed));
    mixer.mNumberBuffers = 6;
    mixer.mBuffers[3].mDataByteSize = sizeof(float);
    float kept = channels[3][1];
    XCTAssertFalse(TwilightSpatialRenderDeinterleaved((AudioBufferList *)&mixer, 2, 6, bed));
    XCTAssertEqualWithAccuracy(channels[3][1], kept, 0.0001f);
}

@end
