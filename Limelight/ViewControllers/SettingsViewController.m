//
//  SettingsViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/27/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "SettingsViewController.h"
#import "TemporarySettings.h"
#import "DataManager.h"
#import "StreamConfiguration.h"
#import "Utils.h"
#import "TwilightTheme.h"

#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

@interface TwilightSegmentWrap : UIView
- (instancetype)initWithControl:(UISegmentedControl *)control;
- (CGFloat)layoutWithinWidth:(CGFloat)width;
@end

@implementation TwilightSegmentWrap {
    __weak UISegmentedControl *_control;
    NSMutableArray<UIButton *> *_buttons;
}

- (instancetype)initWithControl:(UISegmentedControl *)control {
    self = [super initWithFrame:CGRectZero];
    if (self == nil) {
        return nil;
    }
    _control = control;
    _buttons = [NSMutableArray array];
    self.backgroundColor = [UIColor clearColor];
    return self;
}

- (void)rebuildIfNeeded {
    if ((NSInteger)_buttons.count == _control.numberOfSegments) {
        return;
    }
    for (UIButton *button in _buttons) {
        [button removeFromSuperview];
    }
    [_buttons removeAllObjects];
    for (NSInteger i = 0; i < _control.numberOfSegments; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = i;
        button.titleLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightSemibold];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.65;
        button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        button.layer.cornerRadius = 10;
        button.clipsToBounds = YES;
        [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];
        [_buttons addObject:button];
    }
}

- (CGFloat)naturalWidthForTitle:(NSString *)title font:(UIFont *)font {
    CGSize size = [title sizeWithAttributes:@{ NSFontAttributeName: font }];
    return MIN(240, MAX(76, ceil(size.width) + 28));
}

- (CGFloat)layoutWithinWidth:(CGFloat)width {
    [self rebuildIfNeeded];
    if (width < 1 || _buttons.count == 0 || _control == nil) {
        return 0;
    }
    UIFont *font = _buttons.firstObject.titleLabel.font;
    NSMutableArray<NSNumber *> *naturals = [NSMutableArray array];
    CGFloat sum = 0;
    CGFloat gap = 8;
    for (NSInteger i = 0; i < (NSInteger)_buttons.count; i++) {
        NSString *title = [_control titleForSegmentAtIndex:i] ?: @"";
        [_buttons[i] setTitle:title forState:UIControlStateNormal];
        CGFloat natural = [self naturalWidthForTitle:title font:font];
        [naturals addObject:@(natural)];
        sum += natural;
    }
    if (_buttons.count > 1) {
        sum += gap * (_buttons.count - 1);
    }

    NSMutableArray<NSMutableArray<NSNumber *> *> *rows = [NSMutableArray array];
    if (sum <= width + 0.5) {
        NSMutableArray<NSNumber *> *row = [NSMutableArray array];
        for (NSInteger i = 0; i < (NSInteger)_buttons.count; i++) {
            [row addObject:@(i)];
        }
        [rows addObject:row];
    }
    else {
        NSMutableArray<NSNumber *> *row = [NSMutableArray array];
        CGFloat used = 0;
        for (NSInteger i = 0; i < (NSInteger)_buttons.count; i++) {
            CGFloat natural = naturals[i].doubleValue;
            CGFloat next = used == 0 ? natural : used + gap + natural;
            if (used > 0 && next > width) {
                [rows addObject:row];
                row = [NSMutableArray array];
                used = 0;
            }
            [row addObject:@(i)];
            used = used == 0 ? natural : used + gap + natural;
        }
        if (row.count > 0) {
            [rows addObject:row];
        }
    }

    CGFloat rowH = 36;
    CGFloat y = 0;
    BOOL enabled = _control.enabled;
    for (NSMutableArray<NSNumber *> *row in rows) {
        CGFloat naturalSum = 0;
        for (NSNumber *index in row) {
            naturalSum += naturals[index.integerValue].doubleValue;
        }
        CGFloat gaps = gap * (row.count > 0 ? row.count - 1 : 0);
        CGFloat extra = width - naturalSum - gaps;
        if (extra < 0) {
            extra = 0;
        }
        CGFloat share = row.count > 0 ? extra / row.count : 0;
        CGFloat x = 0;
        for (NSNumber *indexNumber in row) {
            NSInteger index = indexNumber.integerValue;
            UIButton *button = _buttons[index];
            CGFloat buttonWidth = MIN(width, naturals[index].doubleValue + share);
            button.frame = CGRectMake(x, y, buttonWidth, rowH);
            x += buttonWidth + gap;
            BOOL selected = _control.selectedSegmentIndex == index;
            BOOL segmentEnabled = enabled && [_control isEnabledForSegmentAtIndex:index];
            button.enabled = segmentEnabled;
            button.backgroundColor = selected ? [TwilightTheme accent] : [TwilightTheme fillStrong];
            UIColor *ink = selected ? [TwilightTheme accentInk] : [TwilightTheme ink];
            [button setTitleColor:ink forState:UIControlStateNormal];
            [button setTitleColor:ink forState:UIControlStateDisabled];
            button.alpha = segmentEnabled ? 1 : 0.45;
            if (selected) {
                button.layer.borderWidth = 0;
            }
            else {
                [TwilightTheme applyBorderToLayer:button.layer width:1 traitCollection:self.traitCollection];
            }
        }
        y += rowH + gap;
    }
    return MAX(rowH, y - gap);
}

- (void)tapped:(UIButton *)button {
    if (_control == nil || !_control.enabled || ![_control isEnabledForSegmentAtIndex:button.tag]) {
        return;
    }
    _control.selectedSegmentIndex = button.tag;
    [_control sendActionsForControlEvents:UIControlEventValueChanged];
    [self layoutWithinWidth:self.bounds.size.width];
}

@end

@implementation SettingsViewController {
    NSInteger _bitrate;
    NSInteger _lastSelectedResolutionIndex;
    UISegmentedControl *_adaptiveBitrateSelector;
    UISegmentedControl *_microphoneSelector;
    UISegmentedControl *_quitAppAfterSelector;
    UILabel *_versionLabel;
    NSArray<UIView *> *_settingsRows;
    BOOL _settingsReady;
}

- (UISegmentedControl *)addYesNoControlTitled:(NSString *)title below:(UIView *)anchor {
    return [self addYesNoControlTitled:title subtitle:nil below:anchor];
}

- (UISegmentedControl *)addYesNoControlTitled:(NSString *)title subtitle:(NSString *)subtitle below:(UIView *)anchor {
    CGFloat y = CGRectGetMaxY(anchor.frame) + 20;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(22, y, 420, 24)];
    label.text = title;
    label.font = [TwilightTheme fontForStyle:UIFontTextStyleHeadline weight:UIFontWeightSemibold];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = [TwilightTheme ink];
    [self.scrollView addSubview:label];

    CGFloat controlY = y + 30;
    if (subtitle.length > 0) {
        UILabel *detail = [[UILabel alloc] initWithFrame:CGRectMake(22, y + 24, 420, 36)];
        detail.text = subtitle;
        detail.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightRegular];
        detail.adjustsFontForContentSizeCategory = YES;
        detail.textColor = [TwilightTheme secondary];
        detail.tag = 2;
        detail.numberOfLines = 2;
        [self.scrollView addSubview:detail];
        controlY = y + 64;
    }

    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:@[@"No", @"Yes"]];
    control.frame = CGRectMake(anchor.frame.origin.x, controlY, anchor.frame.size.width, 32);
    control.selectedSegmentIndex = 0;
    control.tintColor = [TwilightTheme accent];
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        control.selectedSegmentTintColor = [TwilightTheme accent];
    }
    [self.scrollView addSubview:control];
    return control;
}

@dynamic overrideUserInterfaceStyle;

static NSString* bitrateFormat = @"Bitrate: %.1f Mbps";
static const int bitrateTable[] = {
    500,
    1000,
    1500,
    2000,
    2500,
    3000,
    4000,
    5000,
    6000,
    7000,
    8000,
    9000,
    10000,
    12000,
    15000,
    18000,
    20000,
    30000,
    40000,
    50000,
    60000,
    70000,
    80000,
    100000,
    120000,
    150000,
    200000,
    250000,
    300000,
    400000,
    500000,
    600000,
    700000,
    800000,
    900000,
    TWILIGHT_BITRATE_MAX_KBPS,
};

const int RESOLUTION_TABLE_SIZE = 7;
const int RESOLUTION_TABLE_CUSTOM_INDEX = RESOLUTION_TABLE_SIZE - 1;
CGSize resolutionTable[RESOLUTION_TABLE_SIZE];

-(int)getSliderValueForBitrate:(NSInteger)bitrate {
    int i;
    
    for (i = 0; i < (sizeof(bitrateTable) / sizeof(*bitrateTable)); i++) {
        if (bitrate <= bitrateTable[i]) {
            return i;
        }
    }
    
    // Return the last entry in the table
    return i - 1;
}

- (BOOL)isSettingsRow:(UIView *)view {
    return [view isKindOfClass:[UILabel class]] ||
        [view isKindOfClass:[UISegmentedControl class]] ||
        [view isKindOfClass:[UISlider class]] ||
        view == self.resolutionDisplayView;
}

- (void)installWrappedSettings {
    if (!_settingsReady || _settingsRows != nil || self.scrollView == nil) {
        return;
    }
    // Adding the wraps can layout immediately. A sentinel stops that pass
    // from installing a second copy before this one finishes.
    _settingsRows = @[];
    if (@available(iOS 11.0, *)) {
        self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    self.scrollView.clipsToBounds = YES;

    _versionLabel = [[UILabel alloc] init];
    _versionLabel.tag = 7702;
    _versionLabel.textAlignment = NSTextAlignmentCenter;
    _versionLabel.numberOfLines = 0;
    _versionLabel.textColor = [TwilightTheme secondary];
    _versionLabel.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightRegular];
    _versionLabel.adjustsFontForContentSizeCategory = YES;
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    if (version.length == 0) {
        version = @"—";
    }
    if (build.length == 0) {
        build = @"—";
    }
    _versionLabel.text = [NSString stringWithFormat:@"Version %@ (build %@)", version, build];
    [self.scrollView addSubview:_versionLabel];

    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    for (UIView *view in self.scrollView.subviews) {
        if (view == _versionLabel) {
            continue;
        }
        if ([self isSettingsRow:view]) {
            [rows addObject:view];
        }
    }
    [rows sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        if (a.frame.origin.y < b.frame.origin.y - 0.5) {
            return NSOrderedAscending;
        }
        if (a.frame.origin.y > b.frame.origin.y + 0.5) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    NSUInteger quitIndex = _quitAppAfterSelector != nil ? [rows indexOfObject:_quitAppAfterSelector] : NSNotFound;
    if (quitIndex != NSNotFound) {
        [rows insertObject:_versionLabel atIndex:quitIndex + 1];
    }
    else {
        [rows addObject:_versionLabel];
    }
    for (NSUInteger i = 0; i < rows.count; i++) {
        UIView *view = rows[i];
        if (![view isKindOfClass:[UISegmentedControl class]]) {
            continue;
        }
        TwilightSegmentWrap *wrap = [[TwilightSegmentWrap alloc] initWithControl:(UISegmentedControl *)view];
        view.hidden = YES;
        view.frame = CGRectZero;
        [self.scrollView addSubview:wrap];
        rows[i] = wrap;
    }
    _settingsRows = rows;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self installWrappedSettings];
    if (_settingsRows == nil || self.scrollView == nil) {
        return;
    }
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat margin = 16;
    CGFloat x = safe.left + margin;
    CGFloat width = self.scrollView.bounds.size.width - safe.left - safe.right - margin * 2;
    if (width < 120) {
        return;
    }

    CGFloat y = safe.top + 12;
    BOOL first = YES;
    for (UIView *view in _settingsRows) {
        CGFloat gap = 18;
        if (first) {
            gap = 0;
            first = NO;
        }
        else if (view == _versionLabel) {
            gap = 28;
        }
        else if ([view isKindOfClass:[UILabel class]] && view.tag == 2) {
            gap = 4;
        }
        else if ([view isKindOfClass:[UILabel class]]) {
            gap = 22;
        }
        y += gap;

        CGFloat height = 32;
        if ([view isKindOfClass:[TwilightSegmentWrap class]]) {
            height = [(TwilightSegmentWrap *)view layoutWithinWidth:width];
        }
        else if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;
            label.numberOfLines = (label.tag == 2 || label == _versionLabel) ? 0 : 1;
            CGSize size = [label sizeThatFits:CGSizeMake(width, 240)];
            height = MAX(label == _versionLabel ? 18 : 22, ceil(size.height));
            if (label == _versionLabel) {
                label.textAlignment = NSTextAlignmentCenter;
                label.textColor = [TwilightTheme secondary];
                label.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightRegular];
            }
        }
        else if (view == self.resolutionDisplayView) {
            height = 44;
        }
        else if ([view isKindOfClass:[UISlider class]]) {
            height = 36;
        }
        view.frame = CGRectMake(x, y, width, MAX(1, height));
        y += view.frame.size.height;
    }
    [self updateResolutionDisplayViewText];
    self.scrollView.contentSize = CGSizeMake(self.scrollView.bounds.size.width, y + safe.bottom + 28);
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self.view setNeedsLayout];
}

BOOL isCustomResolution(CGSize res) {
    if (res.width == 0 && res.height == 0) {
        return NO;
    }
    
    for (int i = 0; i < RESOLUTION_TABLE_CUSTOM_INDEX; i++) {
        if (res.width == resolutionTable[i].width && res.height == resolutionTable[i].height) {
            return NO;
        }
    }
    
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [TwilightTheme background];
    self.scrollView.backgroundColor = [TwilightTheme background];
    self.view.tintColor = [TwilightTheme accent];
    
    DataManager* dataMan = [[DataManager alloc] init];
    TemporarySettings* currentSettings = [dataMan getSettings];
    
    // Notches stop at 1 Gbps. A stored value above that stays as stored
    // until the slider moves. Nothing in this table is Unlimited.
    NSInteger storedBitrate = [currentSettings.bitrate intValue];
    if (storedBitrate > TWILIGHT_BITRATE_MAX_KBPS) {
        _bitrate = storedBitrate;
    }
    else {
        _bitrate = bitrateTable[[self getSliderValueForBitrate:storedBitrate]];
    }

    // Get the size of the screen with and without safe area insets
    UIWindow *window = [AppDelegate currentWindow];
    if (window == nil) {
        window = self.view.window;
    }
    CGRect windowFrame = window != nil ? window.frame : UIScreen.mainScreen.bounds;
    UIEdgeInsets safeInsets = window != nil ? window.safeAreaInsets : UIEdgeInsetsZero;
    CGFloat screenScale = window != nil ? window.screen.scale : UIScreen.mainScreen.scale;
    CGFloat safeAreaWidth = (windowFrame.size.width - safeInsets.left - safeInsets.right) * screenScale;
    CGFloat fullScreenWidth = windowFrame.size.width * screenScale;
    CGFloat fullScreenHeight = windowFrame.size.height * screenScale;
    
    self.resolutionDisplayView.layer.cornerRadius = 10;
    self.resolutionDisplayView.clipsToBounds = YES;
    self.resolutionDisplayView.backgroundColor = [TwilightTheme field];
    [TwilightTheme applyBorderToLayer:self.resolutionDisplayView.layer width:1 traitCollection:self.traitCollection];
    UITapGestureRecognizer *resolutionDisplayViewTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(resolutionDisplayViewTapped:)];
    [self.resolutionDisplayView addGestureRecognizer:resolutionDisplayViewTap];
    
    resolutionTable[0] = CGSizeMake(640, 360);
    resolutionTable[1] = CGSizeMake(1280, 720);
    resolutionTable[2] = CGSizeMake(1920, 1080);
    resolutionTable[3] = CGSizeMake(3840, 2160);
    resolutionTable[4] = CGSizeMake(safeAreaWidth, fullScreenHeight);
    resolutionTable[5] = CGSizeMake(fullScreenWidth, fullScreenHeight);
    resolutionTable[6] = CGSizeMake([currentSettings.width integerValue], [currentSettings.height integerValue]); // custom initial value
    
    // Don't populate the custom entry unless we have a custom resolution
    if (!isCustomResolution(resolutionTable[6])) {
        resolutionTable[6] = CGSizeMake(0, 0);
    }
    
    NSInteger framerate;
    switch ([currentSettings.framerate integerValue]) {
        case 30:
            framerate = 0;
            break;
        default:
        case 60:
            framerate = 1;
            break;
        case 120:
            framerate = 2;
            break;
    }

    NSInteger resolution = 1;
    for (int i = 0; i < RESOLUTION_TABLE_SIZE; i++) {
        if ((int) resolutionTable[i].height == [currentSettings.height intValue]
            && (int) resolutionTable[i].width == [currentSettings.width intValue]) {
            resolution = i;
            break;
        }
    }

    // Only show the 120 FPS option if we have a > 60-ish Hz display
    bool enable120Fps = false;
    if (@available(iOS 10.3, tvOS 10.3, *)) {
        if ([UIScreen mainScreen].maximumFramesPerSecond > 62) {
            enable120Fps = true;
        }
    }
    if (!enable120Fps) {
        [self.framerateSelector removeSegmentAtIndex:2 animated:NO];
    }

    // Hide codecs this device cannot decode. Titles, not indexes: removing
    // AV1 must not make the old AV1 slot select HEVC or Auto.
    if (![Utils av1HardwareDecodeSupported]) {
        [self removeCodecSegmentTitled:@"AV1"];
    }
    if (!VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
        [self removeCodecSegmentTitled:@"HEVC"];

        // Only enable the 4K option for "recent" devices. We'll judge that by whether
        // they support HEVC decoding (A9 or later).
        [self.resolutionSelector setEnabled:NO forSegmentAtIndex:3];
    }
    [self selectCodecPreference:currentSettings.preferredCodec];

    BOOL hdrDecode = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) || [Utils av1HardwareDecodeSupported];
    if (!hdrDecode || ![Utils displaySupportsHDR10]) {
        [self.hdrSelector removeAllSegments];
        [self.hdrSelector insertSegmentWithTitle:@"Unsupported on this device" atIndex:0 animated:NO];
        [self.hdrSelector setEnabled:NO];
    }
    else {
        [self.hdrSelector setSelectedSegmentIndex:currentSettings.enableHdr ? 1 : 0];
    }
    
    [self.touchModeSelector setSelectedSegmentIndex:currentSettings.absoluteTouchMode ? 1 : 0];
    [self.touchModeSelector addTarget:self action:@selector(touchModeChanged) forControlEvents:UIControlEventValueChanged];
    [self.statsOverlaySelector setSelectedSegmentIndex:currentSettings.statsOverlay ? 1 : 0];
    if (self.statsOverlaySelector != nil) {
        _adaptiveBitrateSelector = [self addYesNoControlTitled:@"Adaptive Bitrate" below:self.statsOverlaySelector];
        [_adaptiveBitrateSelector setSelectedSegmentIndex:currentSettings.enableAdaptiveBitrate ? 1 : 0];
#if !TARGET_OS_TV
        _microphoneSelector = [self addYesNoControlTitled:@"Microphone Passthrough" below:_adaptiveBitrateSelector];
        [_microphoneSelector setSelectedSegmentIndex:currentSettings.enableMicrophone ? 1 : 0];
#endif
        UIView *quitAnchor = _microphoneSelector != nil ? _microphoneSelector : _adaptiveBitrateSelector;
        _quitAppAfterSelector = [self addYesNoControlTitled:@"Quit App on Host"
                                                   subtitle:@"When you end the stream. Unsaved progress on the host will be lost."
                                                      below:quitAnchor];
        [_quitAppAfterSelector setSelectedSegmentIndex:currentSettings.quitAppAfter ? 1 : 0];
    }
    [self.btMouseSelector setSelectedSegmentIndex:currentSettings.btMouseSupport ? 1 : 0];
    [self.optimizeSettingsSelector setSelectedSegmentIndex:currentSettings.optimizeGames ? 1 : 0];
    [self.framePacingSelector setSelectedSegmentIndex:currentSettings.useFramePacing ? 1 : 0];
    [self.multiControllerSelector setSelectedSegmentIndex:currentSettings.multiController ? 1 : 0];
    [self.swapABXYButtonsSelector setSelectedSegmentIndex:currentSettings.swapABXYButtons ? 1 : 0];
    [self.audioOnPCSelector setSelectedSegmentIndex:currentSettings.playAudioOnPC ? 1 : 0];
    NSInteger onscreenControls = [currentSettings.onscreenControls integerValue];
    _lastSelectedResolutionIndex = resolution;
    [self.resolutionSelector setSelectedSegmentIndex:resolution];
    [self.resolutionSelector addTarget:self action:@selector(newResolutionChosen) forControlEvents:UIControlEventValueChanged];
    [self.framerateSelector setSelectedSegmentIndex:framerate];
    [self.framerateSelector addTarget:self action:@selector(updateBitrate) forControlEvents:UIControlEventValueChanged];
    [self.onscreenControlSelector setSelectedSegmentIndex:onscreenControls];
    [self.onscreenControlSelector setEnabled:!currentSettings.absoluteTouchMode];
    [self.bitrateSlider setMinimumValue:0];
    [self.bitrateSlider setMaximumValue:(sizeof(bitrateTable) / sizeof(*bitrateTable)) - 1];
    [self.bitrateSlider setValue:[self getSliderValueForBitrate:_bitrate] animated:YES];
    [self.bitrateSlider addTarget:self action:@selector(bitrateSliderMoved) forControlEvents:UIControlEventValueChanged];
    [self updateBitrateText];
    [self updateResolutionDisplayViewText];
    [self applyTwilightChrome];
    _settingsReady = YES;
    [self installWrappedSettings];
}

- (void)removeCodecSegmentTitled:(NSString *)title {
    for (NSInteger i = 0; i < self.codecSelector.numberOfSegments; i++) {
        if ([[self.codecSelector titleForSegmentAtIndex:i] isEqualToString:title]) {
            [self.codecSelector removeSegmentAtIndex:i animated:NO];
            return;
        }
    }
}

- (void)selectCodecPreference:(int)preference {
    NSString *title = @"Auto";
    switch (preference) {
        case CODEC_PREF_H264:
            title = @"H.264";
            break;
        case CODEC_PREF_HEVC:
            title = @"HEVC";
            break;
        case CODEC_PREF_AV1:
            title = @"AV1";
            break;
        default:
            title = @"Auto";
            break;
    }
    for (NSInteger i = 0; i < self.codecSelector.numberOfSegments; i++) {
        if ([[self.codecSelector titleForSegmentAtIndex:i] isEqualToString:title]) {
            self.codecSelector.selectedSegmentIndex = i;
            return;
        }
    }
    for (NSInteger i = 0; i < self.codecSelector.numberOfSegments; i++) {
        if ([[self.codecSelector titleForSegmentAtIndex:i] isEqualToString:@"Auto"]) {
            self.codecSelector.selectedSegmentIndex = i;
            return;
        }
    }
}

- (void) touchModeChanged {
    // Disable on-screen controls in absolute touch mode
    [self.onscreenControlSelector setEnabled:[self.touchModeSelector selectedSegmentIndex] == 0];
    [self.view setNeedsLayout];
}

- (void) updateBitrate {
    NSInteger fps = [self getChosenFrameRate];
    NSInteger width = [self getChosenStreamWidth];
    NSInteger height = [self getChosenStreamHeight];
    NSInteger defaultBitrate;
    
    // This logic is shamelessly stolen from Moonlight Qt:
    // https://github.com/moonlight-stream/moonlight-qt/blob/master/app/settings/streamingpreferences.cpp
    
    // Don't scale bitrate linearly beyond 60 FPS. It's definitely not a linear
    // bitrate increase for frame rate once we get to values that high.
    float frameRateFactor = (fps <= 60 ? fps : (sqrtf(fps / 60.f) * 60.f)) / 30.f;

    // TODO: Collect some empirical data to see if these defaults make sense.
    // We're just using the values that the Shield used, as we have for years.
    struct {
        NSInteger pixels;
        int factor;
    } resTable[] = {
        { 640 * 360, 1 },
        { 854 * 480, 2 },
        { 1280 * 720, 5 },
        { 1920 * 1080, 10 },
        { 2560 * 1440, 20 },
        { 3840 * 2160, 40 },
        { -1, -1 }
    };

    // Calculate the resolution factor by linear interpolation of the resolution table
    float resolutionFactor;
    NSInteger pixels = width * height;
    for (int i = 0;; i++) {
        if (pixels == resTable[i].pixels) {
            // We can bail immediately for exact matches
            resolutionFactor = resTable[i].factor;
            break;
        }
        else if (pixels < resTable[i].pixels) {
            if (i == 0) {
                // Never go below the lowest resolution entry
                resolutionFactor = resTable[i].factor;
            }
            else {
                // Interpolate between the entry greater than the chosen resolution (i) and the entry less than the chosen resolution (i-1)
                resolutionFactor = ((float)(pixels - resTable[i-1].pixels) / (resTable[i].pixels - resTable[i-1].pixels)) * (resTable[i].factor - resTable[i-1].factor) + resTable[i-1].factor;
            }
            break;
        }
        else if (resTable[i].pixels == -1) {
            // Never go above the highest resolution entry
            resolutionFactor = resTable[i-1].factor;
            break;
        }
    }

    defaultBitrate = round(resolutionFactor * frameRateFactor) * 1000;
    if (defaultBitrate > TWILIGHT_BITRATE_MAX_KBPS) {
        defaultBitrate = TWILIGHT_BITRATE_MAX_KBPS;
    }
    _bitrate = bitrateTable[[self getSliderValueForBitrate:defaultBitrate]];
    [self.bitrateSlider setValue:[self getSliderValueForBitrate:_bitrate] animated:YES];
    
    [self updateBitrateText];
}

- (void) newResolutionChosen {
    BOOL lastSegmentSelected = [self.resolutionSelector selectedSegmentIndex] + 1 == [self.resolutionSelector numberOfSegments];
    if (lastSegmentSelected) {
        [self promptCustomResolutionDialog];
    }
    else {
        [self updateBitrate];
        [self updateResolutionDisplayViewText];
        _lastSelectedResolutionIndex = [self.resolutionSelector selectedSegmentIndex];
    }
}

- (void) promptCustomResolutionDialog {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Enter Custom Resolution" message:nil preferredStyle:UIAlertControllerStyleAlert];

    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Video Width";
        textField.clearButtonMode = UITextFieldViewModeAlways;
        textField.borderStyle = UITextBorderStyleRoundedRect;
        textField.keyboardType = UIKeyboardTypeNumberPad;
        
        if (resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width == 0) {
            textField.text = @"";
        }
        else {
            textField.text = [NSString stringWithFormat:@"%d", (int) resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width];
        }
    }];

    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Video Height";
        textField.clearButtonMode = UITextFieldViewModeAlways;
        textField.borderStyle = UITextBorderStyleRoundedRect;
        textField.keyboardType = UIKeyboardTypeNumberPad;
        
        if (resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height == 0) {
            textField.text = @"";
        }
        else {
            textField.text = [NSString stringWithFormat:@"%d", (int) resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height];
        }
    }];

    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray * textfields = alertController.textFields;
        UITextField *widthField = textfields[0];
        UITextField *heightField = textfields[1];
        
        long width = [widthField.text integerValue];
        long height = [heightField.text integerValue];
        if (width <= 0 || height <= 0) {
            // Restore the previous selection
            [self.resolutionSelector setSelectedSegmentIndex:self->_lastSelectedResolutionIndex];
            return;
        }
        
        // H.264 maximum
        int maxResolutionDimension = 4096;
        if (@available(iOS 11.0, tvOS 11.0, *)) {
            if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
                // HEVC maximum
                maxResolutionDimension = 8192;
            }
        }
        
        // Cap to maximum valid dimensions
        width = MIN(width, maxResolutionDimension);
        height = MIN(height, maxResolutionDimension);
        
        // Cap to minimum valid dimensions
        width = MAX(width, 256);
        height = MAX(height, 256);

        resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX] = CGSizeMake(width, height);
        [self updateBitrate];
        [self updateResolutionDisplayViewText];
        self->_lastSelectedResolutionIndex = [self.resolutionSelector selectedSegmentIndex];
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Custom Resolution Selected" message: @"Custom resolutions are not officially supported by GeForce Experience, so it will not set your host display resolution. You will need to set it manually while in game.\n\nResolutions that are not supported by your client or host PC may cause streaming errors." preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alertController animated:YES completion:nil];
    }]];

    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        // Restore the previous selection
        [self.resolutionSelector setSelectedSegmentIndex:self->_lastSelectedResolutionIndex];
    }]];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)resolutionDisplayViewTapped:(UITapGestureRecognizer *)sender {
    NSURL *url = [NSURL URLWithString:@"https://moonlight-stream.org/custom-resolution"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void) updateResolutionDisplayViewText {
    NSInteger width = [self getChosenStreamWidth];
    NSInteger height = [self getChosenStreamHeight];
    CGFloat viewFrameWidth = self.resolutionDisplayView.frame.size.width;
    CGFloat viewFrameHeight = self.resolutionDisplayView.frame.size.height;
    CGFloat padding = 10;
    
    for (UIView *subview in self.resolutionDisplayView.subviews) {
        [subview removeFromSuperview];
    }
    UILabel *label1 = [[UILabel alloc] init];
    label1.text = @"Set PC/Game resolution: ";
    label1.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightRegular];
    label1.textColor = [TwilightTheme secondary];
    [label1 sizeToFit];
    label1.frame = CGRectMake(padding, (viewFrameHeight - label1.frame.size.height) / 2, label1.frame.size.width, label1.frame.size.height);

    UILabel *label2 = [[UILabel alloc] init];
    label2.text = [NSString stringWithFormat:@"%ld x %ld", (long)width, (long)height];
    label2.textColor = [TwilightTheme ink];
    label2.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightSemibold];
    label2.textAlignment = NSTextAlignmentRight;
    label2.adjustsFontSizeToFitWidth = YES;
    label2.minimumScaleFactor = 0.7;
    [label2 sizeToFit];
    CGFloat inner = MAX(0, viewFrameWidth - padding * 2);
    CGFloat valueW = MIN(label2.frame.size.width, MAX(72, inner * 0.46));
    CGFloat labelH = MAX(label1.frame.size.height, label2.frame.size.height);
    CGFloat labelY = (viewFrameHeight - labelH) / 2.0;
    label2.frame = CGRectMake(viewFrameWidth - padding - valueW, labelY, valueW, labelH);
    label1.lineBreakMode = NSLineBreakByTruncatingTail;
    label1.frame = CGRectMake(padding, labelY, MAX(0, inner - valueW - 8), labelH);

    [self.resolutionDisplayView addSubview:label1];
    [self.resolutionDisplayView addSubview:label2];
}

- (void) bitrateSliderMoved {
    assert(self.bitrateSlider.value < (sizeof(bitrateTable) / sizeof(*bitrateTable)));
    _bitrate = bitrateTable[(int)self.bitrateSlider.value];
    [self updateBitrateText];
}

- (void) updateBitrateText {
    // Display bitrate in Mbps
    [self.bitrateLabel setText:[NSString stringWithFormat:bitrateFormat, _bitrate / 1000.]];
    self.bitrateLabel.textColor = [TwilightTheme ink];
}

- (void)applyTwilightChrome {
    self.view.backgroundColor = [TwilightTheme background];
    self.scrollView.backgroundColor = [TwilightTheme background];
    self.view.tintColor = [TwilightTheme accent];
    self.resolutionDisplayView.backgroundColor = [TwilightTheme field];
    [TwilightTheme applyBorderToLayer:self.resolutionDisplayView.layer width:1 traitCollection:self.traitCollection];
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    }
    [self styleTwilightControls:self.scrollView];
    self.bitrateSlider.minimumTrackTintColor = [TwilightTheme accent];
}

- (void)styleTwilightControls:(UIView *)root {
    for (UIView *view in root.subviews) {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;
            BOOL bold = (label.font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0;
            if (label.tag == 2) {
                label.textColor = [TwilightTheme secondary];
                label.font = [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightRegular];
            }
            else {
                label.textColor = [TwilightTheme ink];
                label.font = [TwilightTheme fontForStyle:bold ? UIFontTextStyleHeadline : UIFontTextStyleBody weight:bold ? UIFontWeightSemibold : UIFontWeightRegular];
            }
            label.adjustsFontForContentSizeCategory = YES;
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.7;
        }
        else if ([view isKindOfClass:[UISegmentedControl class]]) {
            UISegmentedControl *control = (UISegmentedControl *)view;
            control.tintColor = [TwilightTheme accent];
            if (@available(iOS 13.0, tvOS 13.0, *)) {
                control.selectedSegmentTintColor = [TwilightTheme accent];
                [control setTitleTextAttributes:@{
                    NSForegroundColorAttributeName: [TwilightTheme ink],
                    NSFontAttributeName: [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightSemibold],
                } forState:UIControlStateNormal];
                [control setTitleTextAttributes:@{
                    NSForegroundColorAttributeName: [TwilightTheme accentInk],
                    NSFontAttributeName: [TwilightTheme fontForStyle:UIFontTextStyleFootnote weight:UIFontWeightSemibold],
                } forState:UIControlStateSelected];
            }
        }
        else if ([view isKindOfClass:[UISlider class]]) {
            ((UISlider *)view).minimumTrackTintColor = [TwilightTheme accent];
        }
        else if (![view isKindOfClass:[UIButton class]] && view != self.resolutionDisplayView) {
            [self styleTwilightControls:view];
        }
    }
}

- (NSInteger) getChosenFrameRate {
    switch ([self.framerateSelector selectedSegmentIndex]) {
        case 0:
            return 30;
        case 1:
            return 60;
        case 2:
            return 120;
        default:
            abort();
    }
}

- (uint32_t) getChosenCodecPreference {
    NSString *title = [self.codecSelector titleForSegmentAtIndex:self.codecSelector.selectedSegmentIndex];
    if ([title isEqualToString:@"H.264"]) {
        return CODEC_PREF_H264;
    }
    if ([title isEqualToString:@"HEVC"]) {
        return CODEC_PREF_HEVC;
    }
    if ([title isEqualToString:@"AV1"]) {
        return CODEC_PREF_AV1;
    }
    return CODEC_PREF_AUTO;
}

- (NSInteger) getChosenStreamHeight {
    // because the 4k resolution can be removed
    BOOL lastSegmentSelected = [self.resolutionSelector selectedSegmentIndex] + 1 == [self.resolutionSelector numberOfSegments];
    if (lastSegmentSelected) {
        return resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height;
    }

    return resolutionTable[[self.resolutionSelector selectedSegmentIndex]].height;
}

- (NSInteger) getChosenStreamWidth {
    // because the 4k resolution can be removed
    BOOL lastSegmentSelected = [self.resolutionSelector selectedSegmentIndex] + 1 == [self.resolutionSelector numberOfSegments];
    if (lastSegmentSelected) {
        return resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width;
    }

    return resolutionTable[[self.resolutionSelector selectedSegmentIndex]].width;
}

- (void) saveSettings {
    DataManager* dataMan = [[DataManager alloc] init];
    NSInteger framerate = [self getChosenFrameRate];
    NSInteger height = [self getChosenStreamHeight];
    NSInteger width = [self getChosenStreamWidth];
    NSInteger onscreenControls = [self.onscreenControlSelector selectedSegmentIndex];
    BOOL optimizeGames = [self.optimizeSettingsSelector selectedSegmentIndex] == 1;
    BOOL multiController = [self.multiControllerSelector selectedSegmentIndex] == 1;
    BOOL swapABXYButtons = [self.swapABXYButtonsSelector selectedSegmentIndex] == 1;
    BOOL audioOnPC = [self.audioOnPCSelector selectedSegmentIndex] == 1;
    uint32_t preferredCodec = [self getChosenCodecPreference];
    BOOL btMouseSupport = [self.btMouseSelector selectedSegmentIndex] == 1;
    BOOL useFramePacing = [self.framePacingSelector selectedSegmentIndex] == 1;
    BOOL absoluteTouchMode = [self.touchModeSelector selectedSegmentIndex] == 1;
    BOOL statsOverlay = [self.statsOverlaySelector selectedSegmentIndex] == 1;
    BOOL enableHdr = [self.hdrSelector selectedSegmentIndex] == 1;
    BOOL enableAdaptiveBitrate = [_adaptiveBitrateSelector selectedSegmentIndex] == 1;
    BOOL enableMicrophone = [_microphoneSelector selectedSegmentIndex] == 1;
    BOOL quitAppAfter = [_quitAppAfterSelector selectedSegmentIndex] == 1;
    [dataMan saveSettingsWithBitrate:_bitrate
                           framerate:framerate
                              height:height
                               width:width
                         audioConfig:2 // Stereo
                    onscreenControls:onscreenControls
                       optimizeGames:optimizeGames
                     multiController:multiController
                     swapABXYButtons:swapABXYButtons
                           audioOnPC:audioOnPC
                      preferredCodec:preferredCodec
                      useFramePacing:useFramePacing
                           enableHdr:enableHdr
                      btMouseSupport:btMouseSupport
                   absoluteTouchMode:absoluteTouchMode
                        statsOverlay:statsOverlay
               enableAdaptiveBitrate:enableAdaptiveBitrate
                   enableMicrophone:enableMicrophone
                      quitAppAfter:quitAppAfter];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
}


@end
