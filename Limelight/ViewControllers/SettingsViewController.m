//
//  SettingsViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/27/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "SettingsViewController.h"
#import "AboutViewController.h"
#import "TemporarySettings.h"
#import "DataManager.h"
#import "StreamConfiguration.h"
#import "Utils.h"

#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

@implementation SettingsViewController {
    NSInteger _bitrate;
    NSInteger _lastSelectedResolutionIndex;
    UISegmentedControl *_adaptiveBitrateSelector;
    UISegmentedControl *_microphoneSelector;
    UISegmentedControl *_quitAppAfterSelector;
}

- (UISegmentedControl *)addYesNoControlTitled:(NSString *)title below:(UIView *)anchor {
    return [self addYesNoControlTitled:title subtitle:nil below:anchor];
}

- (UISegmentedControl *)addYesNoControlTitled:(NSString *)title subtitle:(NSString *)subtitle below:(UIView *)anchor {
    CGFloat y = CGRectGetMaxY(anchor.frame) + 20;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(22, y, 420, 21)];
    label.text = title;
    label.font = [UIFont boldSystemFontOfSize:17];
    label.textColor = [UIColor colorWithRed:0.939 green:0.963 blue:1 alpha:1];
    [self.scrollView addSubview:label];

    CGFloat controlY = y + 27;
    if (subtitle.length > 0) {
        UILabel *detail = [[UILabel alloc] initWithFrame:CGRectMake(22, y + 22, 420, 34)];
        detail.text = subtitle;
        detail.font = [UIFont systemFontOfSize:13];
        detail.textColor = [UIColor colorWithRed:0.75 green:0.78 blue:0.85 alpha:1];
        detail.numberOfLines = 2;
        [self.scrollView addSubview:detail];
        controlY = y + 58;
    }

    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:@[@"No", @"Yes"]];
    control.frame = CGRectMake(anchor.frame.origin.x, controlY, anchor.frame.size.width, 28);
    control.selectedSegmentIndex = 0;
    UIColor *tint = [UIColor colorWithRed:0.672 green:0.617 blue:0.999 alpha:1];
    control.tintColor = tint;
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        control.selectedSegmentTintColor = tint;
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

// This view is rooted at a ScrollView. To make it scrollable,
// we'll update content size here.
-(void)viewDidLayoutSubviews {
    CGFloat highestViewY = 0;
    
    // Enumerate the scroll view's subviews looking for the
    // highest view Y value to set our scroll view's content
    // size.
    for (UIView* view in self.scrollView.subviews) {
        // UIScrollViews have 2 default child views
        // which represent the horizontal and vertical scrolling
        // indicators. Ignore any views we don't recognize.
        if (![view isKindOfClass:[UILabel class]] &&
            ![view isKindOfClass:[UISegmentedControl class]] &&
            ![view isKindOfClass:[UISlider class]] &&
            ![view isKindOfClass:[UIButton class]]) {
            continue;
        }
        
        CGFloat currentViewY = view.frame.origin.y + view.frame.size.height;
        if (currentViewY > highestViewY) {
            highestViewY = currentViewY;
        }
    }
    
    // Add a bit of padding so the view doesn't end right at the button of the display
    self.scrollView.contentSize = CGSizeMake(self.scrollView.contentSize.width,
                                             highestViewY + 20);
}

// Adjust the subviews for the safe area on the iPhone X.
- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    
    if (@available(iOS 11.0, *)) {
        for (UIView* view in self.view.subviews) {
            // HACK: The official safe area is much too large for our purposes
            // so we'll just use the presence of any safe area to indicate we should
            // pad by 20.
            if (self.view.safeAreaInsets.left >= 20 || self.view.safeAreaInsets.right >= 20) {
                view.frame = CGRectMake(view.frame.origin.x + 20, view.frame.origin.y, view.frame.size.width, view.frame.size.height);
            }
        }
    }
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

    // Always run settings in dark mode because we want the light fonts
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    
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
    [self addLicenseEntry];
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

- (void)addLicenseEntry {
    UIView *anchor = _quitAppAfterSelector;
    if (anchor == nil) {
        anchor = _microphoneSelector;
    }
    if (anchor == nil) {
        anchor = _adaptiveBitrateSelector;
    }
    if (anchor == nil) {
        anchor = self.statsOverlaySelector;
    }
    if (anchor == nil) {
        anchor = self.bitrateSlider;
    }

    CGFloat y = CGRectGetMaxY(anchor.frame) + 28;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(22, y, 420, 21)];
    label.text = @"License";
    label.font = [UIFont boldSystemFontOfSize:17];
    label.textColor = [UIColor colorWithRed:0.939 green:0.963 blue:1 alpha:1];
    [self.scrollView addSubview:label];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(anchor.frame.origin.x, y + 27, MAX(anchor.frame.size.width, 280), 36);
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [button setTitle:@"GNU GPL version 3" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithRed:0.939 green:0.963 blue:1 alpha:1] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17];
    [button addTarget:self action:@selector(showLicense) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:button];
}

- (void)showLicense {
    [AboutViewController presentFrom:self];
}

- (void) touchModeChanged {
    // Disable on-screen controls in absolute touch mode
    [self.onscreenControlSelector setEnabled:[self.touchModeSelector selectedSegmentIndex] == 0];
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
    CGFloat fontSize = [UIFont smallSystemFontSize];
    
    for (UIView *subview in self.resolutionDisplayView.subviews) {
        [subview removeFromSuperview];
    }
    UILabel *label1 = [[UILabel alloc] init];
    label1.text = @"Set PC/Game resolution: ";
    label1.font = [UIFont systemFontOfSize:fontSize];
    [label1 sizeToFit];
    label1.frame = CGRectMake(padding, (viewFrameHeight - label1.frame.size.height) / 2, label1.frame.size.width, label1.frame.size.height);

    UILabel *label2 = [[UILabel alloc] init];
    label2.text = [NSString stringWithFormat:@"%ld x %ld", (long)width, (long)height];
    [label2 sizeToFit];
    label2.frame = CGRectMake(viewFrameWidth - label2.frame.size.width - padding, (viewFrameHeight - label2.frame.size.height) / 2, label2.frame.size.width, label2.frame.size.height);

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
