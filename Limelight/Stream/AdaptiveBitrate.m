#import "AdaptiveBitrate.h"
#import "HttpManager.h"
#import "HttpRequest.h"
#import "HttpResponse.h"
#import "Logger.h"
#import "Connection.h"

#include <Limelight.h>
#include <string.h>

static const int kFloorKbps = 5000;
static const int kHostEndpointCapKbps = 500000;
static const int kMinChangeIntervalMs = 1000;
static const int kCleanRaiseMs = 10000;
static const double kLossCut = 0.02;
static const double kLossClean = 0.005;
static const double kCutFactor = 0.70;
static const double kRaiseFactor = 1.05;
static const int kAudioCushionKbps = 500;

static uint32_t g_poorConnection;
static uint32_t g_poorEdge;
static int g_overlayKbps;
static uint32_t g_abrGeneration;
static NSLock *g_overlayLock;

static NSLock *overlayLock(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_overlayLock = [[NSLock alloc] init];
    });
    return g_overlayLock;
}

void TwilightSetPoorConnection(BOOL poor) {
    __atomic_store_n(&g_poorConnection, poor ? 1 : 0, __ATOMIC_RELAXED);
    // A short poor pulse has to survive until the worker samples it.
    // Recovery clears the level only; the worker clears the edge.
    if (poor) {
        __atomic_store_n(&g_poorEdge, 1, __ATOMIC_RELAXED);
    }
}

void TwilightResetPoorConnection(void) {
    __atomic_store_n(&g_poorConnection, 0, __ATOMIC_RELAXED);
    __atomic_store_n(&g_poorEdge, 0, __ATOMIC_RELAXED);
}

int TwilightAdaptiveOverlayKbps(void) {
    int value = __atomic_load_n(&g_overlayKbps, __ATOMIC_RELAXED);
    return value > 0 ? value : 0;
}

static void setOverlayKbps(int kbps) {
    __atomic_store_n(&g_overlayKbps, kbps > 0 ? kbps : 0, __ATOMIC_RELAXED);
}

static int64_t steadyNowMs(void) {
    return (int64_t)(CACurrentMediaTime() * 1000.0);
}

static int wireCeilingKbps(int requestedWireKbps) {
    if (requestedWireKbps > kHostEndpointCapKbps) {
        return kHostEndpointCapKbps;
    }
    if (requestedWireKbps < 1) {
        return 1;
    }
    return requestedWireKbps;
}

static int floorForCeiling(int ceilingKbps) {
    if (ceilingKbps < kFloorKbps) {
        return ceilingKbps;
    }
    return kFloorKbps;
}

static int assumedAudioKbps(int channelCount, BOOL lan) {
    if (channelCount < 1) {
        channelCount = 2;
    }
    int stereo = lan ? 512 : 96;
    return stereo * ((channelCount + 1) / 2);
}

static int encoderKbpsForWire(int wireKbps, int audioKbps) {
    double raw = (double)wireKbps * 0.80 - (double)audioKbps - (double)kAudioCushionKbps;
    int kbps = (int)raw;
    if (kbps < 1) {
        kbps = 1;
    }
    if (kbps > kHostEndpointCapKbps) {
        kbps = kHostEndpointCapKbps;
    }
    return kbps;
}

static BOOL rttIsSpike(uint32_t rttMs, uint32_t varianceMs, uint32_t baselineMs, BOOL haveBaseline) {
    if (!haveBaseline || baselineMs == 0) {
        return NO;
    }
    if (rttMs > 0 && varianceMs > rttMs) {
        return YES;
    }
    if (rttMs > baselineMs + 30 && rttMs * 2 > baselineMs * 3) {
        return YES;
    }
    return NO;
}

typedef struct {
    int ceiling;
    int floorKbps;
    int wire;
    int audio;
    int64_t lastChangeMs;
    int64_t cleanSinceMs;
    BOOL havePrev;
    uint32_t prevFrames;
    uint32_t prevDropped;
    uint32_t prevFec;
    int64_t prevMs;
    BOOL haveRttBaseline;
    uint32_t rttBaseline;
} AbrController;

typedef struct {
    int64_t nowMs;
    uint32_t totalFrames;
    uint32_t networkDroppedFrames;
    uint32_t fecFailures;
    BOOL rttKnown;
    uint32_t rttMs;
    uint32_t rttVarianceMs;
    BOOL poorConnection;
} AbrObservation;

typedef enum {
    AbrHold,
    AbrCut,
    AbrRaise,
} AbrAction;

typedef struct {
    AbrAction action;
    BOOL send;
    int wireKbps;
    int encoderKbps;
} AbrDecision;

static void abrInit(AbrController *controller, int ceilingWireKbps, int audioKbps) {
    memset(controller, 0, sizeof(*controller));
    controller->ceiling = ceilingWireKbps < 1 ? 1 : ceilingWireKbps;
    controller->floorKbps = floorForCeiling(controller->ceiling);
    controller->wire = controller->ceiling;
    controller->audio = audioKbps < 0 ? 0 : audioKbps;
    controller->lastChangeMs = -1000000;
    controller->cleanSinceMs = -1;
    controller->havePrev = YES;
    controller->prevMs = -1000000;
}

static void abrPrime(AbrController *controller, const AbrObservation *obs) {
    controller->havePrev = YES;
    controller->prevFrames = obs->totalFrames;
    controller->prevDropped = obs->networkDroppedFrames;
    controller->prevFec = obs->fecFailures;
    controller->prevMs = obs->nowMs;
    if (obs->rttKnown && obs->rttMs > 0) {
        controller->haveRttBaseline = YES;
        controller->rttBaseline = obs->rttMs;
    }
}

static AbrDecision abrHold(const AbrController *controller) {
    AbrDecision held;
    held.action = AbrHold;
    held.send = NO;
    held.wireKbps = controller->wire;
    held.encoderKbps = encoderKbpsForWire(controller->wire, controller->audio);
    return held;
}

static AbrDecision abrTick(AbrController *controller, const AbrObservation *obs) {
    AbrDecision held = abrHold(controller);
    if (controller->havePrev && obs->nowMs < controller->prevMs) {
        return held;
    }
    if (controller->havePrev && obs->nowMs - controller->prevMs < kMinChangeIntervalMs) {
        return held;
    }

    uint32_t frameDelta = 0;
    uint32_t droppedDelta = 0;
    uint32_t fecDelta = 0;
    if (controller->havePrev) {
        frameDelta = obs->totalFrames - controller->prevFrames;
        droppedDelta = obs->networkDroppedFrames - controller->prevDropped;
        fecDelta = obs->fecFailures - controller->prevFec;
    }

    BOOL haveInterval = controller->havePrev;
    controller->havePrev = YES;
    controller->prevFrames = obs->totalFrames;
    controller->prevDropped = obs->networkDroppedFrames;
    controller->prevFec = obs->fecFailures;
    controller->prevMs = obs->nowMs;

    if (!haveInterval) {
        if (obs->rttKnown && obs->rttMs > 0) {
            controller->haveRttBaseline = YES;
            controller->rttBaseline = obs->rttMs;
        }
        return held;
    }

    BOOL fecBad = fecDelta > 0;
    BOOL haveLoss = frameDelta > 0;
    double loss = 0.0;
    if (haveLoss) {
        loss = (double)droppedDelta / (double)frameDelta;
        if (loss > 1.0) {
            loss = 1.0;
        }
    }
    BOOL lossCut = haveLoss && loss > kLossCut;
    BOOL rttBad = obs->rttKnown && rttIsSpike(obs->rttMs, obs->rttVarianceMs, controller->rttBaseline, controller->haveRttBaseline);
    if (obs->rttKnown && obs->rttMs > 0 && !rttBad) {
        if (!controller->haveRttBaseline || obs->rttMs < controller->rttBaseline) {
            controller->rttBaseline = obs->rttMs;
            controller->haveRttBaseline = YES;
        }
    }

    BOOL shouldCut = lossCut || fecBad || rttBad || obs->poorConnection;
    BOOL clean = !obs->poorConnection && !fecBad && !rttBad && haveLoss && loss <= kLossClean;
    BOOL canChange = obs->nowMs - controller->lastChangeMs >= kMinChangeIntervalMs;

    if (shouldCut && canChange && controller->wire > controller->floorKbps) {
        int next = (int)((double)controller->wire * kCutFactor);
        if (next >= controller->wire) {
            next = controller->wire - 1;
        }
        if (next < controller->floorKbps) {
            next = controller->floorKbps;
        }
        controller->wire = next;
        controller->lastChangeMs = obs->nowMs;
        controller->cleanSinceMs = -1;
        AbrDecision cut;
        cut.action = AbrCut;
        cut.send = YES;
        cut.wireKbps = controller->wire;
        cut.encoderKbps = encoderKbpsForWire(controller->wire, controller->audio);
        return cut;
    }

    if (!clean) {
        controller->cleanSinceMs = -1;
        return held;
    }
    if (controller->cleanSinceMs < 0) {
        controller->cleanSinceMs = obs->nowMs;
        return held;
    }
    if (obs->nowMs - controller->cleanSinceMs >= kCleanRaiseMs && canChange && controller->wire < controller->ceiling) {
        int next = (int)((double)controller->wire * kRaiseFactor);
        if (next <= controller->wire) {
            next = controller->wire + 1;
        }
        if (next > controller->ceiling) {
            next = controller->ceiling;
        }
        controller->wire = next;
        controller->lastChangeMs = obs->nowMs;
        controller->cleanSinceMs = obs->nowMs;
        AbrDecision raise;
        raise.action = AbrRaise;
        raise.send = YES;
        raise.wireKbps = controller->wire;
        raise.encoderKbps = encoderKbpsForWire(controller->wire, controller->audio);
        return raise;
    }
    return held;
}

static void fillObservation(AbrObservation *obs) {
    memset(obs, 0, sizeof(*obs));
    obs->nowMs = steadyNowMs();
    TwilightGetCumulativeVideoCounts(&obs->totalFrames, &obs->networkDroppedFrames);
    const RTP_VIDEO_STATS *rtp = LiGetRTPVideoStats();
    if (rtp != NULL) {
        obs->fecFailures = rtp->packetCountFecFailed;
    }
    uint32_t rtt = 0;
    uint32_t variance = 0;
    obs->rttKnown = LiGetEstimatedRttInfo(&rtt, &variance);
    obs->rttMs = rtt;
    obs->rttVarianceMs = variance;
    BOOL poorNow = __atomic_load_n(&g_poorConnection, __ATOMIC_RELAXED) != 0;
    BOOL poorEdge = __atomic_exchange_n(&g_poorEdge, 0, __ATOMIC_RELAXED) != 0;
    obs->poorConnection = poorNow || poorEdge;
}

@implementation AdaptiveBitrateWorker {
    NSString *_host;
    unsigned short _httpsPort;
    NSData *_serverCert;
    int _requestedWireKbps;
    int _audioChannelCount;
    BOOL _lan;
    uint32_t _stop;
    uint32_t _generation;
}

- (instancetype)initWithHost:(NSString *)host
                   httpsPort:(unsigned short)httpsPort
                  serverCert:(NSData *)serverCert
           requestedWireKbps:(int)requestedWireKbps
           audioChannelCount:(int)audioChannelCount
                         lan:(BOOL)lan {
    self = [super init];
    if (self) {
        _host = [host copy];
        _httpsPort = httpsPort;
        _serverCert = [serverCert copy];
        _requestedWireKbps = requestedWireKbps;
        _audioChannelCount = audioChannelCount;
        _lan = lan;
        // A newer worker wins the overlay. Hide a stale figure until this
        // one learns whether the host allows runtime changes.
        [overlayLock() lock];
        _generation = __atomic_add_fetch(&g_abrGeneration, 1, __ATOMIC_RELAXED);
        __atomic_store_n(&g_overlayKbps, 0, __ATOMIC_RELAXED);
        [overlayLock() unlock];
    }
    return self;
}

- (BOOL)isCurrent {
    return __atomic_load_n(&g_abrGeneration, __ATOMIC_RELAXED) == _generation;
}

- (void)publishOverlayKbps:(int)kbps {
    [overlayLock() lock];
    if (_generation == __atomic_load_n(&g_abrGeneration, __ATOMIC_RELAXED)) {
        setOverlayKbps(kbps);
    }
    [overlayLock() unlock];
}

- (void)requestStop {
    __atomic_store_n(&_stop, 1, __ATOMIC_RELAXED);
}

- (BOOL)stopped {
    return __atomic_load_n(&_stop, __ATOMIC_RELAXED) != 0;
}

- (void)main {
    @autoreleasepool {
        HttpManager *http = [[HttpManager alloc] initWithAddress:_host httpsPort:_httpsPort serverCert:_serverCert];
        BOOL runtimeBitrate = NO;
        if (![http requestAbrRuntimeBitrate:&runtimeBitrate]) {
            if ([self isCurrent]) {
                Log(LOG_I, @"Adaptive bitrate: capability check failed; leaving the stream bitrate alone");
            }
            return;
        }
        if (!runtimeBitrate) {
            if ([self isCurrent]) {
                Log(LOG_I, @"Adaptive bitrate: host does not list runtime_bitrate; leaving the stream bitrate alone");
            }
            return;
        }
        if ([self stopped] || ![self isCurrent]) {
            return;
        }

        int ceiling = wireCeilingKbps(_requestedWireKbps);
        int audio = assumedAudioKbps(_audioChannelCount, _lan);
        AbrController controller;
        abrInit(&controller, ceiling, audio);
        [self publishOverlayKbps:controller.wire];
        Log(LOG_I, @"Adaptive bitrate: host allows runtime changes, ceiling %d kbps", controller.ceiling);

        AbrObservation baseline;
        fillObservation(&baseline);
        abrPrime(&controller, &baseline);

        while (![self stopped]) {
            for (int step = 0; step < 15 && ![self stopped]; step++) {
                [NSThread sleepForTimeInterval:0.1];
            }
            if ([self stopped]) {
                break;
            }

            AbrObservation obs;
            fillObservation(&obs);
            AbrDecision decision = abrTick(&controller, &obs);
            [self publishOverlayKbps:decision.wireKbps];
            if (!decision.send || [self stopped] || ![self isCurrent]) {
                continue;
            }

            int applied = 0;
            if ([http requestSetEncoderBitrateKbps:decision.encoderKbps appliedKbps:&applied]) {
                Log(LOG_I, @"Adaptive bitrate: %@ wire %d kbps, encoder request %d kbps, host applied %d",
                    decision.action == AbrCut ? @"cut" : @"raise",
                    decision.wireKbps,
                    decision.encoderKbps,
                    applied);
            }
            else {
                Log(LOG_W, @"Adaptive bitrate: host rejected the change to %d kbps", decision.encoderKbps);
            }
        }

        [self publishOverlayKbps:0];
    }
}

@end
