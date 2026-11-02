#import "MicrophoneCapture.h"
#import "Logger.h"

#include <Limelight.h>
#include <string.h>

#if !TARGET_OS_TV

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "opus/opus.h"

static const int kSampleRate = 48000;
static const int kFrameSamples = 960;
static const int kOpusBitrate = 64000;
static const int kHeaderBytes = 4;
static const int kMaxOpusBytes = 247;
static const unsigned short kPacketType = 0x3003;

@implementation MicrophoneCapture {
}

static AVAudioEngine *micEngine;
static AVAudioConverter *micConverter;
static AVAudioFormat *micConverterInputFormat;
static OpusEncoder *micEncoder;
static NSMutableData *micPcm;
static NSLock *micLock;
static NSLock *micStartLock;
static uint16_t micSequence;
static BOOL micRunning;
static BOOL micStop;
static BOOL micSawInput;
static BOOL micLoggedSendFailure;
static BOOL micLoggedFirstPacket;
static CFTimeInterval micWaitingSince;
static dispatch_source_t micSilenceTimer;

+ (void)ensureLock {
    if (micLock == nil) {
        micLock = [[NSLock alloc] init];
        micStartLock = [[NSLock alloc] init];
    }
}

+ (void)startIfEnabled:(BOOL)enabled {
    if (!enabled) {
        return;
    }
    [self ensureLock];
    [micLock lock];
    if (micRunning) {
        [micLock unlock];
        return;
    }
    micStop = NO;
    [micLock unlock];

    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session requestRecordPermission:^(BOOL granted) {
        if (!granted) {
            Log(LOG_W, @"Microphone permission was not granted; the stream continues without passthrough");
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startEngine];
        });
    }];
}

+ (void)stop {
    [self ensureLock];
    // Start holds micStartLock for the whole engine open, then micLock.
    // Take them in that order so stop cannot free the encoder mid-start.
    [micStartLock lock];
    [micLock lock];
    micStop = YES;
    micRunning = NO;
    AVAudioEngine *engine = micEngine;
    micEngine = nil;
    OpusEncoder *encoder = micEncoder;
    micEncoder = nil;
    micConverter = nil;
    micConverterInputFormat = nil;
    micPcm = nil;
    dispatch_source_t silenceTimer = micSilenceTimer;
    micSilenceTimer = nil;
    [micLock unlock];
    if (silenceTimer != nil) {
        dispatch_source_cancel(silenceTimer);
    }

    void (^teardown)(void) = ^{
        if (engine != nil) {
            @try {
                [engine.inputNode removeTapOnBus:0];
            } @catch (NSException *exception) {
                Log(LOG_W, @"Microphone tap removal: %@", exception.reason);
            }
            [engine stop];
        }
    };
    if ([NSThread isMainThread]) {
        teardown();
    }
    else {
        dispatch_async(dispatch_get_main_queue(), teardown);
    }
    if (encoder != NULL) {
        opus_encoder_destroy(encoder);
    }
    [micStartLock unlock];
}

+ (BOOL)configureEncoder:(OpusEncoder *)encoder {
    int controls[8];
    controls[0] = opus_encoder_ctl(encoder, OPUS_SET_BITRATE(kOpusBitrate));
    controls[1] = opus_encoder_ctl(encoder, OPUS_SET_VBR(1));
    controls[2] = opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY(10));
    controls[3] = opus_encoder_ctl(encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    controls[4] = opus_encoder_ctl(encoder, OPUS_SET_LSB_DEPTH(16));
    controls[5] = opus_encoder_ctl(encoder, OPUS_SET_DTX(0));
    controls[6] = opus_encoder_ctl(encoder, OPUS_SET_INBAND_FEC(1));
    controls[7] = opus_encoder_ctl(encoder, OPUS_SET_PACKET_LOSS_PERC(5));
    for (int i = 0; i < 8; i++) {
        if (controls[i] != OPUS_OK) {
            Log(LOG_W, @"Microphone opus_encoder_ctl failed: %s", opus_strerror(controls[i]));
        }
    }
    int frame = opus_encoder_ctl(encoder, OPUS_SET_EXPERT_FRAME_DURATION(OPUS_FRAMESIZE_20_MS));
    if (frame != OPUS_OK) {
        Log(LOG_W, @"Microphone opus frame duration failed: %s", opus_strerror(frame));
    }
    return YES;
}

+ (void)startEngine {
    [self ensureLock];
    [micStartLock lock];
    [micLock lock];
    if (micStop || micRunning) {
        [micLock unlock];
        [micStartLock unlock];
        return;
    }
    [micLock unlock];

    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayAndRecord
                         mode:AVAudioSessionModeDefault
                      options:AVAudioSessionCategoryOptionMixWithOthers |
                              AVAudioSessionCategoryOptionAllowBluetooth |
                              AVAudioSessionCategoryOptionDefaultToSpeaker
                        error:&error]) {
        Log(LOG_W, @"Microphone audio session failed: %@; the stream continues", error);
        [micStartLock unlock];
        return;
    }
    if (![session setActive:YES error:&error]) {
        Log(LOG_W, @"Microphone audio session activation failed: %@; the stream continues", error);
        [micStartLock unlock];
        return;
    }

    int opusError = OPUS_OK;
    OpusEncoder *encoder = opus_encoder_create(kSampleRate, 1, OPUS_APPLICATION_VOIP, &opusError);
    if (encoder == NULL || opusError != OPUS_OK) {
        Log(LOG_W, @"Microphone opus encoder failed: %s; the stream continues", opus_strerror(opusError));
        [micStartLock unlock];
        return;
    }
    [self configureEncoder:encoder];

    AVAudioEngine *engine = [[AVAudioEngine alloc] init];
    AVAudioInputNode *input = engine.inputNode;
    AVAudioFormat *hardware = [input outputFormatForBus:0];
    if (hardware == nil || hardware.sampleRate < 1.0 || hardware.channelCount < 1) {
        Log(LOG_W, @"Microphone hardware format is not ready; the stream continues");
        opus_encoder_destroy(encoder);
        [micStartLock unlock];
        return;
    }

    AVAudioFormat *tapFormat = hardware;
    if (hardware.commonFormat != AVAudioPCMFormatFloat32 || hardware.interleaved) {
        AVAudioFormat *floatFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                      sampleRate:hardware.sampleRate
                                                                        channels:hardware.channelCount
                                                                     interleaved:NO];
        if (floatFormat == nil) {
            Log(LOG_W, @"Microphone float format could not be created; the stream continues");
            opus_encoder_destroy(encoder);
            [micStartLock unlock];
            return;
        }
        tapFormat = floatFormat;
    }

    // micStartLock is held for this whole method, so stop waits until the
    // engine is either running or abandoned. micLock stays free across the
    // tap and the engine start, because those can call back on another thread.
    [micLock lock];
    if (micStop || micRunning) {
        [micLock unlock];
        opus_encoder_destroy(encoder);
        [micStartLock unlock];
        return;
    }
    micEncoder = encoder;
    micEngine = engine;
    micPcm = [NSMutableData data];
    micSequence = 0;
    micSawInput = NO;
    micLoggedSendFailure = NO;
    micLoggedFirstPacket = NO;
    micWaitingSince = CACurrentMediaTime();
    micRunning = YES;
    [micLock unlock];

    @try {
        [input installTapOnBus:0 bufferSize:4096 format:tapFormat block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            (void)when;
            [self handleBuffer:buffer];
        }];
    } @catch (NSException *exception) {
        [micStartLock unlock];
        Log(LOG_W, @"Microphone tap failed: %@; the stream continues", exception.reason);
        [self stop];
        return;
    }

    if (![engine startAndReturnError:&error]) {
        [micStartLock unlock];
        Log(LOG_W, @"Microphone engine failed: %@; the stream continues", error);
        [self stop];
        return;
    }

    // The host opens its input device on the first packet. Send silence
    // until the tap delivers, even when no buffer has arrived yet.
    dispatch_source_t silenceTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(silenceTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                              (uint64_t)(0.1 * NSEC_PER_SEC),
                              (uint64_t)(0.02 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(silenceTimer, ^{
        [MicrophoneCapture encodeAvailableFrames];
    });
    micSilenceTimer = silenceTimer;
    dispatch_resume(silenceTimer);
    [micStartLock unlock];
    Log(LOG_I, @"Microphone passthrough started");
}

+ (void)appendPcm:(const int16_t *)samples count:(NSUInteger)count realInput:(BOOL)realInput {
    if (count == 0 || samples == NULL) {
        return;
    }
    [micLock lock];
    if (!micStop && micPcm != nil) {
        if (realInput) {
            micSawInput = YES;
        }
        [micPcm appendBytes:samples length:count * sizeof(int16_t)];
        NSUInteger maxSamples = (NSUInteger)kFrameSamples * 2;
        NSUInteger have = micPcm.length / sizeof(int16_t);
        if (have > maxSamples) {
            NSUInteger extraFrames = have / (NSUInteger)kFrameSamples;
            if (extraFrames > 2) {
                NSUInteger drop = (extraFrames - 2) * (NSUInteger)kFrameSamples * sizeof(int16_t);
                [micPcm replaceBytesInRange:NSMakeRange(0, drop) withBytes:NULL length:0];
            }
        }
    }
    [micLock unlock];
}

+ (void)handleBuffer:(AVAudioPCMBuffer *)buffer {
    [micLock lock];
    BOOL stopped = micStop || micEncoder == NULL;
    [micLock unlock];
    if (stopped || buffer == nil || buffer.frameLength == 0) {
        return;
    }
    if (buffer.format.commonFormat != AVAudioPCMFormatFloat32 || buffer.floatChannelData == NULL) {
        Log(LOG_W, @"Microphone input is not float32; capture stopped");
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [MicrophoneCapture stop];
        });
        return;
    }

    AVAudioFormat *outputFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                                   sampleRate:kSampleRate
                                                                     channels:1
                                                                  interleaved:NO];
    [micLock lock];
    if (micConverter == nil || ![micConverterInputFormat isEqual:buffer.format]) {
        micConverter = [[AVAudioConverter alloc] initFromFormat:buffer.format toFormat:outputFormat];
        micConverterInputFormat = buffer.format;
    }
    AVAudioConverter *converter = micConverter;
    [micLock unlock];
    if (converter == nil || outputFormat == nil) {
        return;
    }

    double ratio = kSampleRate / buffer.format.sampleRate;
    AVAudioFrameCount capacity = (AVAudioFrameCount)(buffer.frameLength * ratio) + 32;
    AVAudioPCMBuffer *converted = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outputFormat frameCapacity:capacity];
    if (converted == nil) {
        return;
    }

    __block BOOL provided = NO;
    NSError *error = nil;
    AVAudioConverterOutputStatus status = [converter convertToBuffer:converted error:&error withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
        (void)inNumberOfPackets;
        if (provided) {
            *outStatus = AVAudioConverterInputStatus_NoDataNow;
            return nil;
        }
        provided = YES;
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return buffer;
    }];
    if (status == AVAudioConverterOutputStatus_Error || converted.frameLength == 0 || converted.int16ChannelData == NULL) {
        if (error != nil) {
            Log(LOG_W, @"Microphone convert failed: %@", error);
        }
        return;
    }

    [self appendPcm:converted.int16ChannelData[0] count:converted.frameLength realInput:YES];
    [self encodeAvailableFrames];
}

+ (void)encodeAvailableFrames {
    [micLock lock];
    if (micStop || micEncoder == NULL || micPcm == nil) {
        [micLock unlock];
        return;
    }
    if (!micSawInput && micPcm.length < (NSUInteger)kFrameSamples * sizeof(int16_t) &&
        CACurrentMediaTime() - micWaitingSince >= 0.2) {
        int16_t silence[kFrameSamples];
        memset(silence, 0, sizeof(silence));
        [micPcm appendBytes:silence length:sizeof(silence)];
        micWaitingSince = CACurrentMediaTime();
        Log(LOG_I, @"No microphone samples yet; sending silence so the host can open its input device");
    }

    while (!micStop && micEncoder != NULL && micPcm != nil &&
           micPcm.length >= (NSUInteger)kFrameSamples * sizeof(int16_t)) {
        int16_t frame[kFrameSamples];
        [micPcm getBytes:frame length:sizeof(frame)];
        [micPcm replaceBytesInRange:NSMakeRange(0, sizeof(frame)) withBytes:NULL length:0];
        OpusEncoder *encoder = micEncoder;
        uint16_t sequence = micSequence++;
        unsigned char encoded[kMaxOpusBytes];
        int encodedBytes = opus_encode(encoder, frame, kFrameSamples, encoded, kMaxOpusBytes);
        if (encodedBytes <= 0 || encodedBytes > kMaxOpusBytes) {
            Log(LOG_W, @"Microphone opus_encode failed: %s", opus_strerror(encodedBytes));
            continue;
        }

        unsigned char packet[kHeaderBytes + kMaxOpusBytes];
        packet[0] = (unsigned char)((sequence >> 8) & 0xFF);
        packet[1] = (unsigned char)(sequence & 0xFF);
        packet[2] = 1;
        packet[3] = 0;
        memcpy(packet + kHeaderBytes, encoded, (size_t)encodedBytes);
        int sent = LiSendRawControlStreamPacket(kPacketType, packet, (unsigned short)(kHeaderBytes + encodedBytes));
        if (sent != 0 && !micLoggedSendFailure) {
            micLoggedSendFailure = YES;
            Log(LOG_W, @"Microphone control send failed (%d); further failures are not logged", sent);
        }
        else if (sent == 0 && !micLoggedFirstPacket) {
            micLoggedFirstPacket = YES;
            Log(LOG_I, @"Sent first microphone packet (type 0x%04x, %d opus bytes)", kPacketType, encodedBytes);
        }
    }
    [micLock unlock];
}

@end

#else

@implementation MicrophoneCapture

+ (void)startIfEnabled:(BOOL)enabled {
    (void)enabled;
}

+ (void)stop {
}

@end

#endif
