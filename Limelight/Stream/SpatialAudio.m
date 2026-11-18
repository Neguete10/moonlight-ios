//
//  SpatialAudio.m
//  Moonlight
//
//  Renders a 5.1 or 7.1 bed with the spatial mixer, then plays stereo.
//  Headphones get the binaural renderer. Built-in speakers get the
//  speaker renderer. A route that already has its own speakers, or any
//  failed setup, leaves playback on the normal path.
//

#import "SpatialAudio.h"
#import "Logger.h"

#import <os/lock.h>
#import <stdatomic.h>

#if __has_include(<AudioToolbox/AudioToolbox.h>) && __has_include(<AVFoundation/AVFoundation.h>)
#define TWILIGHT_SPATIAL_RENDERER 1
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#else
#define TWILIGHT_SPATIAL_RENDERER 0
#endif

static NSString *const kSpatialAudioKey = @"spatialAudio";
static NSString *const kHeadTrackingKey = @"spatialHeadTracking";

static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;
static _Atomic int gRunning = 0;
static _Atomic int gMode = 0; // 0 normal, 1 active, 2 passthrough, 3 downmix fallback
static _Atomic int gLayoutRaw = 0;
static _Atomic int gRouteRaw = 0;
static _Atomic int gHeadApplied = 0;

enum {
    kModeNormal = 0,
    kModeActive = 1,
    kModePassthrough = 2,
    kModeFallback = 3,
};

#if TWILIGHT_SPATIAL_RENDERER
static const uint32_t kRingFrames = 4096;
static const uint32_t kMaxSlice = 4096;

static AudioUnit gMixer = NULL;
static AudioUnit gOutput = NULL;
static BOOL gMixerReady = NO;
static BOOL gOutputReady = NO;
static id gRouteObserver = nil;
static id gInterruptObserver = nil;
static float *gConvert = NULL;

static float *gRing = NULL;
static uint32_t gRingCapacity = 0;
static int gChannels = 0;
static _Atomic uint32_t gReadFrame = 0;
static _Atomic uint32_t gWriteFrame = 0;

static float *gLeft = NULL;
static float *gRight = NULL;
static int gMaxSubmitFrames = 0;
#endif

NSString *TwilightSpatialAudioEnabledKey(void) {
    return kSpatialAudioKey;
}

NSString *TwilightSpatialHeadTrackingEnabledKey(void) {
    return kHeadTrackingKey;
}

BOOL TwilightSpatialAudioEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSpatialAudioKey];
}

BOOL TwilightSpatialHeadTrackingEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kHeadTrackingKey];
}

void TwilightSpatialSetAudioEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kSpatialAudioKey];
}

void TwilightSpatialSetHeadTrackingEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kHeadTrackingKey];
}

int TwilightSpatialSurroundChannelCount(BOOL enabled) {
    return enabled ? 8 : 0;
}

TwilightSpatialLayout TwilightSpatialLayoutForChannelCount(int channelCount) {
    if (channelCount == 6) {
        return TwilightSpatialLayout51;
    }
    if (channelCount == 8) {
        return TwilightSpatialLayout71;
    }
    return TwilightSpatialLayoutNone;
}

NSString *TwilightSpatialLayoutName(TwilightSpatialLayout layout) {
    switch (layout) {
        case TwilightSpatialLayout51:
            return @"5.1";
        case TwilightSpatialLayout71:
            return @"7.1";
        case TwilightSpatialLayoutNone:
            return @"stereo";
    }
    return @"stereo";
}

uint32_t TwilightSpatialChannelLayoutTag(int channelCount) {
#if TWILIGHT_SPATIAL_RENDERER
    // The host bed is front L/R, center, LFE, then back L/R. 7.1 adds the
    // side pair after the backs. That is the WAVE 5.1 B and WAVE 7.1 order.
    if (channelCount == 6) {
        return (uint32_t)kAudioChannelLayoutTag_WAVE_5_1_B;
    }
    if (channelCount == 8) {
        return (uint32_t)kAudioChannelLayoutTag_WAVE_7_1;
    }
#else
    (void)channelCount;
#endif
    return 0;
}

TwilightSpatialRouteKind TwilightSpatialRouteKindForPort(NSString *portType) {
    if (portType.length == 0) {
        return TwilightSpatialRouteExternal;
    }
    // String values of the session port constants. Literals keep this
    // mapping available on both the iOS and tvOS SDKs.
    if ([portType isEqualToString:@"Headphones"] ||
        [portType isEqualToString:@"BluetoothA2DP"] ||
        [portType isEqualToString:@"BluetoothHFP"] ||
        [portType isEqualToString:@"BluetoothLE"] ||
        [portType isEqualToString:@"AirPlay"]) {
        return TwilightSpatialRouteHeadphones;
    }
    if ([portType isEqualToString:@"Speaker"] ||
        [portType isEqualToString:@"Receiver"]) {
        return TwilightSpatialRouteSpeakers;
    }
    return TwilightSpatialRouteExternal;
}

TwilightSpatialRouteKind TwilightSpatialCurrentRouteKind(void) {
#if TWILIGHT_SPATIAL_RENDERER
    AVAudioSessionRouteDescription *route = [AVAudioSession sharedInstance].currentRoute;
    if (route.outputs.count != 1) {
        return TwilightSpatialRouteExternal;
    }
    return TwilightSpatialRouteKindForPort(route.outputs.firstObject.portType);
#else
    return TwilightSpatialRouteExternal;
#endif
}

NSString *TwilightSpatialRouteName(TwilightSpatialRouteKind kind) {
    switch (kind) {
        case TwilightSpatialRouteHeadphones:
            return @"headphones";
        case TwilightSpatialRouteSpeakers:
            return @"speakers";
        case TwilightSpatialRouteExternal:
            return @"external";
    }
    return @"external";
}

NSString *TwilightSpatialStatusLine(BOOL enabled,
                                     BOOL active,
                                     BOOL headTracking,
                                     TwilightSpatialLayout layout,
                                     TwilightSpatialRouteKind route,
                                     BOOL fallback,
                                     BOOL passthrough) {
    if (!enabled) {
        return @"Spatial audio off";
    }
    NSString *name = TwilightSpatialLayoutName(layout);
    if (passthrough) {
        return [NSString stringWithFormat:@"Spatial audio passthrough %@", name];
    }
    if (!active || fallback) {
        return [NSString stringWithFormat:@"Spatial audio fallback %@", name];
    }
    if (headTracking && route == TwilightSpatialRouteHeadphones) {
        return [NSString stringWithFormat:@"Spatial audio active %@ %@, head tracking",
                name, TwilightSpatialRouteName(route)];
    }
    return [NSString stringWithFormat:@"Spatial audio active %@ %@",
            name, TwilightSpatialRouteName(route)];
}

static int16_t clampS16(int32_t sample) {
    if (sample > INT16_MAX) {
        return INT16_MAX;
    }
    if (sample < INT16_MIN) {
        return INT16_MIN;
    }
    return (int16_t)sample;
}

static int32_t scaled(int16_t sample, int32_t numerator) {
    return ((int32_t)sample * numerator) / 1000;
}

void TwilightSpatialDownmixToStereo(const int16_t *interleaved,
                                    int frames,
                                    int channels,
                                    int16_t *stereoOut) {
    if (interleaved == NULL || stereoOut == NULL || frames <= 0 || channels <= 0) {
        return;
    }
    for (int frame = 0; frame < frames; frame++) {
        const int16_t *in = interleaved + (frame * channels);
        int32_t left = 0;
        int32_t right = 0;
        if (channels >= 1) {
            left += in[0];
        }
        if (channels >= 2) {
            right += in[1];
        }
        if (channels >= 6) {
            // Center and the back pair fold in at about -3 dB. LFE is quieter.
            left += scaled(in[2], 707);
            right += scaled(in[2], 707);
            left += scaled(in[3], 500);
            right += scaled(in[3], 500);
            left += scaled(in[4], 707);
            right += scaled(in[5], 707);
        }
        else if (channels > 2) {
            for (int channel = 2; channel < channels; channel++) {
                left += scaled(in[channel], 500);
                right += scaled(in[channel], 500);
            }
        }
        if (channels >= 8) {
            left += scaled(in[6], 707);
            right += scaled(in[7], 707);
        }
        stereoOut[frame * 2] = clampS16(left);
        stereoOut[frame * 2 + 1] = clampS16(right);
    }
}

static void publishLayout(int channels) {
    atomic_store_explicit(&gLayoutRaw, (int)TwilightSpatialLayoutForChannelCount(channels), memory_order_relaxed);
}

void TwilightSpatialNotePassthrough(int channels) {
    publishLayout(channels);
    atomic_store_explicit(&gMode, kModePassthrough, memory_order_relaxed);
    atomic_store_explicit(&gRunning, 0, memory_order_relaxed);
    atomic_store_explicit(&gHeadApplied, 0, memory_order_relaxed);
}

void TwilightSpatialNoteDownmix(int channels) {
    publishLayout(channels);
    atomic_store_explicit(&gMode, kModeFallback, memory_order_relaxed);
    atomic_store_explicit(&gRunning, 0, memory_order_relaxed);
    atomic_store_explicit(&gHeadApplied, 0, memory_order_relaxed);
}

NSString *TwilightSpatialCurrentStatusLine(void) {
    BOOL enabled = TwilightSpatialAudioEnabled();
    int mode = atomic_load_explicit(&gMode, memory_order_relaxed);
    TwilightSpatialLayout layout = (TwilightSpatialLayout)atomic_load_explicit(&gLayoutRaw, memory_order_relaxed);
    TwilightSpatialRouteKind route = (TwilightSpatialRouteKind)atomic_load_explicit(&gRouteRaw, memory_order_relaxed);
    BOOL active = mode == kModeActive;
    BOOL head = atomic_load_explicit(&gHeadApplied, memory_order_relaxed) != 0;
    return TwilightSpatialStatusLine(enabled,
                                      active,
                                      head,
                                      layout,
                                      route,
                                      mode == kModeFallback,
                                      mode == kModePassthrough);
}

#if TWILIGHT_SPATIAL_RENDERER

static void logStatus(OSStatus status, NSString *what) {
    if (status == noErr) {
        return;
    }
    Log(LOG_W, @"Spatial audio %@: %d", what, (int)status);
}

static BOOL setStreamFormat(AudioUnit unit,
                            AudioUnitScope scope,
                            AudioUnitElement element,
                            double sampleRate,
                            AudioChannelLayoutTag tag) {
    AVAudioChannelLayout *layout = [AVAudioChannelLayout layoutWithLayoutTag:tag];
    if (layout == nil) {
        return NO;
    }
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                              sampleRate:sampleRate
                                                             interleaved:NO
                                                           channelLayout:layout];
    if (format == nil) {
        return NO;
    }
    const AudioStreamBasicDescription *asbd = format.streamDescription;
    OSStatus status = AudioUnitSetProperty(unit,
                                            kAudioUnitProperty_StreamFormat,
                                            scope,
                                            element,
                                            asbd,
                                            sizeof(AudioStreamBasicDescription));
    if (status != noErr) {
        logStatus(status, @"stream format");
        return NO;
    }
    // A tag layout has no extra channel descriptions, so the base struct is the whole layout.
    status = AudioUnitSetProperty(unit,
                                  kAudioUnitProperty_AudioChannelLayout,
                                  scope,
                                  element,
                                  layout.layout,
                                  sizeof(AudioChannelLayout));
    if (status != noErr) {
        logStatus(status, @"channel layout");
        return NO;
    }
    return YES;
}

static AUSpatialMixerOutputType mixerOutputType(TwilightSpatialRouteKind kind) {
    switch (kind) {
        case TwilightSpatialRouteHeadphones:
            return kSpatialMixerOutputType_Headphones;
        case TwilightSpatialRouteSpeakers:
            return kSpatialMixerOutputType_BuiltInSpeakers;
        case TwilightSpatialRouteExternal:
            return kSpatialMixerOutputType_ExternalSpeakers;
    }
    return kSpatialMixerOutputType_Headphones;
}

static BOOL setOutputType(TwilightSpatialRouteKind kind) {
    AUSpatialMixerOutputType outputType = mixerOutputType(kind);
    OSStatus status = AudioUnitSetProperty(gMixer,
                                            kAudioUnitProperty_SpatialMixerOutputType,
                                            kAudioUnitScope_Global,
                                            0,
                                            &outputType,
                                            sizeof(outputType));
    logStatus(status, @"output type");
    return status == noErr;
}

static void ringReset(void) {
    atomic_store_explicit(&gReadFrame, 0, memory_order_relaxed);
    atomic_store_explicit(&gWriteFrame, 0, memory_order_relaxed);
}

static BOOL ringWrite(const float *interleaved, uint32_t frames) {
    if (gRing == NULL || frames == 0) {
        return NO;
    }
    uint32_t read = atomic_load_explicit(&gReadFrame, memory_order_acquire);
    uint32_t write = atomic_load_explicit(&gWriteFrame, memory_order_relaxed);
    if ((write - read) + frames > gRingCapacity) {
        return NO;
    }
    uint32_t start = write % gRingCapacity;
    uint32_t first = gRingCapacity - start;
    if (first > frames) {
        first = frames;
    }
    memcpy(gRing + (start * (uint32_t)gChannels),
           interleaved,
           first * (uint32_t)gChannels * sizeof(float));
    if (frames > first) {
        memcpy(gRing,
               interleaved + (first * (uint32_t)gChannels),
               (frames - first) * (uint32_t)gChannels * sizeof(float));
    }
    atomic_store_explicit(&gWriteFrame, write + frames, memory_order_release);
    return YES;
}

static BOOL ringReadDeinterleaved(AudioBufferList *ioData, uint32_t frames) {
    uint32_t write = atomic_load_explicit(&gWriteFrame, memory_order_acquire);
    uint32_t read = atomic_load_explicit(&gReadFrame, memory_order_relaxed);
    if (write - read < frames || gRing == NULL) {
        return NO;
    }
    uint32_t channels = (uint32_t)gChannels;
    if (ioData->mNumberBuffers < channels) {
        return NO;
    }
    for (uint32_t frame = 0; frame < frames; frame++) {
        const float *src = gRing + (((read + frame) % gRingCapacity) * channels);
        for (uint32_t channel = 0; channel < channels; channel++) {
            float *dst = (float *)ioData->mBuffers[channel].mData;
            dst[frame] = src[channel];
        }
    }
    atomic_store_explicit(&gReadFrame, read + frames, memory_order_release);
    return YES;
}

static OSStatus mixerInput(void *inRefCon,
                           AudioUnitRenderActionFlags *ioActionFlags,
                           const AudioTimeStamp *inTimestamp,
                           UInt32 inBusNumber,
                           UInt32 inNumberFrames,
                           AudioBufferList *ioData) {
    (void)inRefCon;
    (void)inTimestamp;
    (void)inBusNumber;
    for (UInt32 buffer = 0; buffer < ioData->mNumberBuffers; buffer++) {
        memset(ioData->mBuffers[buffer].mData, 0, inNumberFrames * sizeof(float));
    }
    if (!ringReadDeinterleaved(ioData, inNumberFrames)) {
        if (ioActionFlags != NULL) {
            *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        }
    }
    return noErr;
}

static void silenceInterleaved(AudioBufferList *ioData, UInt32 frames) {
    for (UInt32 buffer = 0; buffer < ioData->mNumberBuffers; buffer++) {
        memset(ioData->mBuffers[buffer].mData, 0, ioData->mBuffers[buffer].mDataByteSize);
    }
    (void)frames;
}

static OSStatus outputRender(void *inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimestamp,
                             UInt32 inBusNumber,
                             UInt32 inNumberFrames,
                             AudioBufferList *ioData) {
    (void)inRefCon;
    (void)inBusNumber;
    if (!atomic_load_explicit(&gRunning, memory_order_relaxed) || gMixer == NULL || gLeft == NULL || inNumberFrames > kMaxSlice) {
        silenceInterleaved(ioData, inNumberFrames);
        if (ioActionFlags != NULL) {
            *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        }
        return noErr;
    }

    AudioBufferList spatial;
    spatial.mNumberBuffers = 2;
    spatial.mBuffers[0].mNumberChannels = 1;
    spatial.mBuffers[0].mDataByteSize = inNumberFrames * (UInt32)sizeof(float);
    spatial.mBuffers[0].mData = gLeft;
    spatial.mBuffers[1].mNumberChannels = 1;
    spatial.mBuffers[1].mDataByteSize = inNumberFrames * (UInt32)sizeof(float);
    spatial.mBuffers[1].mData = gRight;

    AudioUnitRenderActionFlags flags = 0;
    OSStatus status = AudioUnitRender(gMixer, &flags, inTimestamp, 0, inNumberFrames, &spatial);
    if (status != noErr) {
        silenceInterleaved(ioData, inNumberFrames);
        return noErr;
    }

    if (ioData->mNumberBuffers >= 2 && ioData->mBuffers[0].mData != NULL && ioData->mBuffers[1].mData != NULL) {
        memcpy(ioData->mBuffers[0].mData, gLeft, inNumberFrames * sizeof(float));
        memcpy(ioData->mBuffers[1].mData, gRight, inNumberFrames * sizeof(float));
        return noErr;
    }
    float *interleaved = (float *)ioData->mBuffers[0].mData;
    if (interleaved == NULL) {
        return noErr;
    }
    for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
        interleaved[frame * 2] = gLeft[frame];
        interleaved[frame * 2 + 1] = gRight[frame];
    }
    return noErr;
}

static void disposeUnitsLocked(void) {
    atomic_store_explicit(&gRunning, 0, memory_order_relaxed);
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (gRouteObserver != nil) {
        [center removeObserver:gRouteObserver];
        gRouteObserver = nil;
    }
    if (gInterruptObserver != nil) {
        [center removeObserver:gInterruptObserver];
        gInterruptObserver = nil;
    }
    if (gOutput != NULL) {
        AudioOutputUnitStop(gOutput);
        if (gOutputReady) {
            AudioUnitUninitialize(gOutput);
            gOutputReady = NO;
        }
        AudioComponentInstanceDispose(gOutput);
        gOutput = NULL;
    }
    if (gMixer != NULL) {
        if (gMixerReady) {
            AudioUnitUninitialize(gMixer);
            gMixerReady = NO;
        }
        AudioComponentInstanceDispose(gMixer);
        gMixer = NULL;
    }
    free(gRing);
    gRing = NULL;
    gRingCapacity = 0;
    free(gLeft);
    gLeft = NULL;
    free(gRight);
    gRight = NULL;
    free(gConvert);
    gConvert = NULL;
    gChannels = 0;
    ringReset();
    atomic_store_explicit(&gMode, kModeNormal, memory_order_relaxed);
    atomic_store_explicit(&gHeadApplied, 0, memory_order_relaxed);
}

static BOOL applyHeadTrackingLocked(BOOL enabled, TwilightSpatialRouteKind route) {
    atomic_store_explicit(&gHeadApplied, 0, memory_order_relaxed);
    if (!enabled || route != TwilightSpatialRouteHeadphones || gMixer == NULL) {
        return NO;
    }
#if TARGET_OS_TV
    if (@available(tvOS 18.0, *))
#else
    if (@available(iOS 18.0, *))
#endif
    {
        UInt32 tracking = 1;
        OSStatus status = AudioUnitSetProperty(gMixer,
                                                kAudioUnitProperty_SpatialMixerEnableHeadTracking,
                                                kAudioUnitScope_Global,
                                                0,
                                                &tracking,
                                                sizeof(tracking));
        if (status != noErr) {
            logStatus(status, @"head tracking");
            return NO;
        }
        UInt32 hrtf = kSpatialMixerPersonalizedHRTFMode_Auto;
        status = AudioUnitSetProperty(gMixer,
                                      kAudioUnitProperty_SpatialMixerPersonalizedHRTFMode,
                                      kAudioUnitScope_Global,
                                      0,
                                      &hrtf,
                                      sizeof(hrtf));
        logStatus(status, @"personalized rendering");
        atomic_store_explicit(&gHeadApplied, 1, memory_order_relaxed);
        return YES;
    }
    return NO;
}

static void handleRouteChange(void) {
    os_unfair_lock_lock(&gLock);
    if (gMixer == NULL || gOutput == NULL) {
        os_unfair_lock_unlock(&gLock);
        return;
    }
    TwilightSpatialRouteKind route = TwilightSpatialCurrentRouteKind();
    atomic_store_explicit(&gRouteRaw, (int)route, memory_order_relaxed);
    atomic_store_explicit(&gRunning, 0, memory_order_relaxed);
    AudioOutputUnitStop(gOutput);
    if (!setOutputType(route)) {
        atomic_store_explicit(&gMode, kModeFallback, memory_order_relaxed);
        os_unfair_lock_unlock(&gLock);
        return;
    }
    BOOL head = TwilightSpatialHeadTrackingEnabled();
    applyHeadTrackingLocked(head, route);
    OSStatus status = AudioOutputUnitStart(gOutput);
    if (status != noErr) {
        logStatus(status, @"restart after route change");
        atomic_store_explicit(&gMode, kModeFallback, memory_order_relaxed);
        os_unfair_lock_unlock(&gLock);
        return;
    }
    atomic_store_explicit(&gRunning, 1, memory_order_relaxed);
    atomic_store_explicit(&gMode, kModeActive, memory_order_relaxed);
    os_unfair_lock_unlock(&gLock);
}

static void prepareSession(int sampleRate, int samplesPerFrame) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [session setCategory:AVAudioSessionCategoryPlayback
             withOptions:AVAudioSessionCategoryOptionMixWithOthers
                   error:&error];
    if (error != nil) {
        Log(LOG_W, @"Spatial audio session category: %@", error);
    }
    error = nil;
    [session setPreferredSampleRate:sampleRate error:&error];
    error = nil;
    if (sampleRate > 0 && samplesPerFrame > 0) {
        NSTimeInterval seconds = (NSTimeInterval)samplesPerFrame / (NSTimeInterval)sampleRate;
        [session setPreferredIOBufferDuration:seconds error:&error];
    }
    error = nil;
    [session setActive:YES error:&error];
    if (error != nil) {
        Log(LOG_W, @"Spatial audio session activate: %@", error);
    }
}

#endif

BOOL TwilightSpatialStart(int sampleRate, int channels, int samplesPerFrame, BOOL headTracking) {
#if !TWILIGHT_SPATIAL_RENDERER
    (void)sampleRate;
    (void)channels;
    (void)samplesPerFrame;
    (void)headTracking;
    return NO;
#else
    if (sampleRate < 1 || samplesPerFrame < 1 || TwilightSpatialChannelLayoutTag(channels) == 0) {
        return NO;
    }
    TwilightSpatialRouteKind route = TwilightSpatialCurrentRouteKind();
    if (route == TwilightSpatialRouteExternal) {
        return NO;
    }

    os_unfair_lock_lock(&gLock);
    disposeUnitsLocked();

    gChannels = channels;
    gMaxSubmitFrames = samplesPerFrame;
    gRingCapacity = kRingFrames;
    gRing = (float *)calloc(gRingCapacity * (uint32_t)channels, sizeof(float));
    gLeft = (float *)calloc(kMaxSlice, sizeof(float));
    gRight = (float *)calloc(kMaxSlice, sizeof(float));
    gConvert = (float *)calloc((size_t)samplesPerFrame * (size_t)channels, sizeof(float));
    if (gRing == NULL || gLeft == NULL || gRight == NULL || gConvert == NULL) {
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }
    ringReset();

    prepareSession(sampleRate, samplesPerFrame);

    AudioComponentDescription mixerDesc = {
        kAudioUnitType_Mixer,
        kAudioUnitSubType_SpatialMixer,
        kAudioUnitManufacturer_Apple,
        0,
        0
    };
    AudioComponent mixerComponent = AudioComponentFindNext(NULL, &mixerDesc);
    if (mixerComponent == NULL || AudioComponentInstanceNew(mixerComponent, &gMixer) != noErr) {
        Log(LOG_W, @"Spatial mixer is not available");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }

    UInt32 inputs = 1;
    OSStatus status = AudioUnitSetProperty(gMixer,
                                            kAudioUnitProperty_ElementCount,
                                            kAudioUnitScope_Input,
                                            0,
                                            &inputs,
                                            sizeof(inputs));
    if (status != noErr ||
        !setStreamFormat(gMixer, kAudioUnitScope_Output, 0, sampleRate, kAudioChannelLayoutTag_Stereo) ||
        !setStreamFormat(gMixer, kAudioUnitScope_Input, 0, sampleRate, (AudioChannelLayoutTag)TwilightSpatialChannelLayoutTag(channels))) {
        logStatus(status, @"mixer format");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }

    UInt32 algorithm = kSpatializationAlgorithm_UseOutputType;
    status = AudioUnitSetProperty(gMixer,
                                  kAudioUnitProperty_SpatializationAlgorithm,
                                  kAudioUnitScope_Input,
                                  0,
                                  &algorithm,
                                  sizeof(algorithm));
    if (status != noErr) {
        logStatus(status, @"renderer algorithm");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }
    UInt32 sourceMode = kSpatialMixerSourceMode_AmbienceBed;
    status = AudioUnitSetProperty(gMixer,
                                  kAudioUnitProperty_SpatialMixerSourceMode,
                                  kAudioUnitScope_Input,
                                  0,
                                  &sourceMode,
                                  sizeof(sourceMode));
    if (status != noErr || !setOutputType(route)) {
        logStatus(status, @"source mode");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }

#if TARGET_OS_TV
    if (@available(tvOS 18.0, *))
#else
    if (@available(iOS 18.0, *))
#endif
    {
        AUPreset preset;
        preset.presetNumber = route == TwilightSpatialRouteSpeakers ? 0 : 1;
        preset.presetName = NULL;
        status = AudioUnitSetProperty(gMixer,
                                      kAudioUnitProperty_PresentPreset,
                                      kAudioUnitScope_Global,
                                      0,
                                      &preset,
                                      sizeof(preset));
        logStatus(status, @"playback preset");
    }
    // The preset can replace earlier properties, so head tracking is applied after it.
    setOutputType(route);
    applyHeadTrackingLocked(headTracking, route);

    UInt32 maxFrames = kMaxSlice;
    status = AudioUnitSetProperty(gMixer,
                                  kAudioUnitProperty_MaximumFramesPerSlice,
                                  kAudioUnitScope_Global,
                                  0,
                                  &maxFrames,
                                  sizeof(maxFrames));
    if (status != noErr) {
        logStatus(status, @"mixer slice");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }
    AURenderCallbackStruct mixerCallback;
    mixerCallback.inputProc = mixerInput;
    mixerCallback.inputProcRefCon = NULL;
    status = AudioUnitSetProperty(gMixer,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  0,
                                  &mixerCallback,
                                  sizeof(mixerCallback));
    if (status != noErr) {
        logStatus(status, @"mixer callback");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }
    status = AudioUnitInitialize(gMixer);
    if (status != noErr) {
        logStatus(status, @"mixer initialize");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }
    gMixerReady = YES;

    AudioComponentDescription outputDesc = {
        kAudioUnitType_Output,
        kAudioUnitSubType_RemoteIO,
        kAudioUnitManufacturer_Apple,
        0,
        0
    };
    AudioComponent outputComponent = AudioComponentFindNext(NULL, &outputDesc);
    if (outputComponent == NULL || AudioComponentInstanceNew(outputComponent, &gOutput) != noErr) {
        Log(LOG_W, @"Audio output is not available");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }
    UInt32 enable = 1;
    AudioUnitSetProperty(gOutput,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Output,
                         0,
                         &enable,
                         sizeof(enable));
    AudioStreamBasicDescription outputFormat;
    memset(&outputFormat, 0, sizeof(outputFormat));
    outputFormat.mSampleRate = sampleRate;
    outputFormat.mFormatID = kAudioFormatLinearPCM;
    outputFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    outputFormat.mFramesPerPacket = 1;
    outputFormat.mChannelsPerFrame = 2;
    outputFormat.mBitsPerChannel = 32;
    outputFormat.mBytesPerFrame = 8;
    outputFormat.mBytesPerPacket = 8;
    status = AudioUnitSetProperty(gOutput,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &outputFormat,
                                  sizeof(outputFormat));
    if (status != noErr) {
        logStatus(status, @"output format");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }
    status = AudioUnitSetProperty(gOutput,
                                  kAudioUnitProperty_MaximumFramesPerSlice,
                                  kAudioUnitScope_Global,
                                  0,
                                  &maxFrames,
                                  sizeof(maxFrames));
    logStatus(status, @"output slice");
    AURenderCallbackStruct outputCallback;
    outputCallback.inputProc = outputRender;
    outputCallback.inputProcRefCon = NULL;
    status = AudioUnitSetProperty(gOutput,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  0,
                                  &outputCallback,
                                  sizeof(outputCallback));
    if (status != noErr) {
        logStatus(status, @"output callback");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }
    status = AudioUnitInitialize(gOutput);
    if (status != noErr) {
        logStatus(status, @"output initialize");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }
    gOutputReady = YES;
    status = AudioOutputUnitStart(gOutput);
    if (status != noErr) {
        logStatus(status, @"output start");
        disposeUnitsLocked();
        os_unfair_lock_unlock(&gLock);
        return NO;
    }

    atomic_store_explicit(&gRouteRaw, (int)route, memory_order_relaxed);
    publishLayout(channels);
    atomic_store_explicit(&gMode, kModeActive, memory_order_relaxed);
    atomic_store_explicit(&gRunning, 1, memory_order_relaxed);

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    gRouteObserver = [center addObserverForName:AVAudioSessionRouteChangeNotification
                                         object:nil
                                          queue:[NSOperationQueue mainQueue]
                                     usingBlock:^(NSNotification *note) {
        (void)note;
        handleRouteChange();
    }];
    gInterruptObserver = [center addObserverForName:AVAudioSessionInterruptionNotification
                                            object:nil
                                             queue:[NSOperationQueue mainQueue]
                                        usingBlock:^(NSNotification *note) {
        NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
        if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded) {
            handleRouteChange();
        }
    }];
    os_unfair_lock_unlock(&gLock);
    Log(LOG_I, @"Spatial audio active (%@, %@)",
        TwilightSpatialLayoutName(TwilightSpatialLayoutForChannelCount(channels)),
        TwilightSpatialRouteName(route));
    return YES;
#endif
}

void TwilightSpatialStop(void) {
    os_unfair_lock_lock(&gLock);
#if TWILIGHT_SPATIAL_RENDERER
    disposeUnitsLocked();
#endif
    atomic_store_explicit(&gRunning, 0, memory_order_relaxed);
    atomic_store_explicit(&gMode, kModeNormal, memory_order_relaxed);
    atomic_store_explicit(&gHeadApplied, 0, memory_order_relaxed);
    os_unfair_lock_unlock(&gLock);
}

BOOL TwilightSpatialIsActive(void) {
    return atomic_load_explicit(&gMode, memory_order_relaxed) == kModeActive;
}

void TwilightSpatialSubmitS16(const int16_t *interleaved, int frames, int channels) {
#if !TWILIGHT_SPATIAL_RENDERER
    (void)interleaved;
    (void)frames;
    (void)channels;
    return;
#else
    if (interleaved == NULL || frames <= 0) {
        return;
    }
    os_unfair_lock_lock(&gLock);
    if (atomic_load_explicit(&gRunning, memory_order_relaxed) && gConvert != NULL &&
        channels == gChannels && frames <= gMaxSubmitFrames) {
        int samples = frames * channels;
        for (int i = 0; i < samples; i++) {
            gConvert[i] = (float)interleaved[i] / 32768.0f;
        }
        ringWrite(gConvert, (uint32_t)frames);
    }
    os_unfair_lock_unlock(&gLock);
#endif
}

NSString *TwilightSpatialExerciseTestStream(void) {
    TwilightSpatialStop();
    BOOL started = TwilightSpatialStart(48000, 6, 240, TwilightSpatialHeadTrackingEnabled());
    if (!started) {
        TwilightSpatialNoteDownmix(6);
        return TwilightSpatialCurrentStatusLine();
    }
    int16_t pcm[240 * 6];
    memset(pcm, 0, sizeof(pcm));
    pcm[2] = 8000;
    for (int packet = 0; packet < 4; packet++) {
        TwilightSpatialSubmitS16(pcm, 240, 6);
    }
#if TWILIGHT_SPATIAL_RENDERER
    handleRouteChange();
    handleRouteChange();
#endif
    NSString *line = TwilightSpatialCurrentStatusLine();
    if (atomic_load_explicit(&gRunning, memory_order_relaxed) == 0) {
        TwilightSpatialNoteDownmix(6);
        line = TwilightSpatialCurrentStatusLine();
    }
    return line;
}
