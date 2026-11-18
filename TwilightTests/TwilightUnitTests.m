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
#import "KeyboardSupport.h"
#import "TwilightOnScreenKeyboard.h"
#import "SpatialAudio.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <stdint.h>

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

@end
