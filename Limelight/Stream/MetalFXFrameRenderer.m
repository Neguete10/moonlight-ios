//
//  MetalFXFrameRenderer.m
//  Moonlight
//
//  CVPixelBuffer -> private RGB texture -> MTLFXSpatialScaler -> private
//  output -> render blit into a CAMetalLayer. The scaler never writes the
//  drawable. One present is scheduled at a time, and each in-flight frame
//  has its own scaler and textures.
//

#import "MetalFXFrameRenderer.h"
#import "MetalFXLayout.h"
#import "StreamVideoLayout.h"

#import <Metal/Metal.h>
#import <objc/message.h>
// The simulator SDK does not ship MetalFX.framework. Device SDKs do.
// The stream always falls back to AVSampleBufferDisplayLayer when this is 0.
#if !TARGET_OS_SIMULATOR && __has_include(<MetalFX/MetalFX.h>)
#define TWILIGHT_HAS_METALFX 1
#import <MetalFX/MetalFX.h>
#else
#define TWILIGHT_HAS_METALFX 0
#endif
#import <QuartzCore/CAMetalLayer.h>

static void *MetalFXBoundsContext = &MetalFXBoundsContext;

static NSString *MetalFXShaderSource(void) {
    return
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"struct VertexOut {\n"
    @"    float4 position [[position]];\n"
    @"    float2 uv;\n"
    @"};\n"
    @"struct Params {\n"
    @"    int matrix;\n"
    @"    int fullRange;\n"
    @"    int tenBit;\n"
    @"    int transfer;\n"
    @"};\n"
    @"vertex VertexOut fullscreenVertex(uint vid [[vertex_id]]) {\n"
    @"    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };\n"
    @"    float2 uvs[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };\n"
    @"    VertexOut out;\n"
    @"    out.position = float4(pos[vid], 0.0, 1.0);\n"
    @"    out.uv = uvs[vid];\n"
    @"    return out;\n"
    @"}\n"
    @"float pqToNitsRatio(float n) {\n"
    @"    float m1 = 0.1593017578125;\n"
    @"    float m2 = 78.84375;\n"
    @"    float c1 = 0.8359375;\n"
    @"    float c2 = 18.8515625;\n"
    @"    float c3 = 18.6875;\n"
    @"    float p = pow(clamp(n, 0.0, 1.0), 1.0 / m2);\n"
    @"    float num = max(p - c1, 0.0);\n"
    @"    float den = max(c2 - c3 * p, 1e-5);\n"
    @"    return pow(num / den, 1.0 / m1) * 100.0;\n"
    @"}\n"
    @"float gammaToLinear(float c) {\n"
    @"    c = clamp(c, 0.0, 1.0);\n"
    @"    if (c <= 0.04045) { return c / 12.92; }\n"
    @"    return pow((c + 0.055) / 1.055, 2.4);\n"
    @"}\n"
    @"fragment float4 yuvToRgb(VertexOut in [[stage_in]],\n"
    @"                         texture2d<float> yTex [[texture(0)]],\n"
    @"                         texture2d<float> uvTex [[texture(1)]],\n"
    @"                         constant Params &params [[buffer(0)]]) {\n"
    @"    constexpr sampler s(address::clamp_to_edge, filter::linear);\n"
    @"    float y = yTex.sample(s, in.uv).r;\n"
    @"    float2 uv = uvTex.sample(s, in.uv).rg;\n"
    @"    float yBlack = params.tenBit != 0 ? (64.0 / 1023.0) : (16.0 / 255.0);\n"
    @"    float ySpan = params.tenBit != 0 ? (876.0 / 1023.0) : (219.0 / 255.0);\n"
    @"    float cCenter = params.tenBit != 0 ? (512.0 / 1023.0) : (128.0 / 255.0);\n"
    @"    float cSpan = params.tenBit != 0 ? (896.0 / 1023.0) : (224.0 / 255.0);\n"
    @"    float u;\n"
    @"    float v;\n"
    @"    if (params.fullRange != 0) {\n"
    @"        u = uv.x - cCenter;\n"
    @"        v = uv.y - cCenter;\n"
    @"    } else {\n"
    @"        y = (y - yBlack) / ySpan;\n"
    @"        u = (uv.x - cCenter) / cSpan;\n"
    @"        v = (uv.y - cCenter) / cSpan;\n"
    @"    }\n"
    @"    float3x3 m = float3x3(float3(1.0, 1.0, 1.0), float3(0.0, -0.1873, 1.8556), float3(1.5748, -0.4681, 0.0));\n"
    @"    if (params.matrix == 1) {\n"
    @"        m = float3x3(float3(1.0, 1.0, 1.0), float3(0.0, -0.344136, 1.772), float3(1.402, -0.714136, 0.0));\n"
    @"    } else if (params.matrix == 2) {\n"
    @"        m = float3x3(float3(1.0, 1.0, 1.0), float3(0.0, -0.164553, 1.8814), float3(1.4746, -0.571353, 0.0));\n"
    @"    }\n"
    @"    float3 rgb = m * float3(y, u, v);\n"
    @"    if (params.transfer == 1) {\n"
    @"        rgb = float3(pqToNitsRatio(rgb.r), pqToNitsRatio(rgb.g), pqToNitsRatio(rgb.b));\n"
    @"    } else if (params.transfer == 2) {\n"
    @"        rgb = float3(gammaToLinear(rgb.r), gammaToLinear(rgb.g), gammaToLinear(rgb.b));\n"
    @"    } else {\n"
    @"        rgb = clamp(rgb, 0.0, 1.0);\n"
    @"    }\n"
    @"    return float4(max(rgb, 0.0), 1.0);\n"
    @"}\n"
    @"fragment float4 copyColor(VertexOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {\n"
    @"    constexpr sampler s(address::clamp_to_edge, filter::nearest);\n"
    @"    return tex.sample(s, in.uv);\n"
    @"}\n";
}

typedef struct {
    int matrix;
    int fullRange;
    int tenBit;
    int transfer;
} MetalFXYUVParams;

@interface MetalFXHeldTextures : NSObject
@property (nonatomic, assign) CVMetalTextureRef y;
@property (nonatomic, assign) CVMetalTextureRef uv;
@end

@implementation MetalFXHeldTextures
- (void)dealloc {
    if (_y != NULL) {
        CFRelease(_y);
    }
    if (_uv != NULL) {
        CFRelease(_uv);
    }
}
@end

@interface MetalFXTiming : NSObject
@property (nonatomic, assign) CFTimeInterval decodedAt;
@property (nonatomic, assign) double queueMs;
@property (nonatomic, assign) double textureMs;
@property (nonatomic, assign) double yuvMs;
@property (nonatomic, assign) double scalerMs;
@property (nonatomic, assign) double drawableMs;
@property (nonatomic, assign) double gpuMs;
@property (nonatomic, assign) CFTimeInterval presentCommit;
@property (nonatomic, assign) CFTimeInterval readyAt;
@property (nonatomic, assign) int inW;
@property (nonatomic, assign) int inH;
@property (nonatomic, assign) int outW;
@property (nonatomic, assign) int outH;
@property (nonatomic, assign) uint64_t serial;
@end

@implementation MetalFXTiming
@end

@interface MetalFXSlot : NSObject
@property (nonatomic, strong) id scaler;
@property (nonatomic, strong) id<MTLTexture> rgb;
@property (nonatomic, strong) id<MTLTexture> scaled;
@property (nonatomic, assign) NSUInteger inW;
@property (nonatomic, assign) NSUInteger inH;
@property (nonatomic, assign) NSUInteger outW;
@property (nonatomic, assign) NSUInteger outH;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL ready;
@property (nonatomic, assign) BOOL presenting;
@property (nonatomic, assign) BOOL discard;
@property (nonatomic, strong) MetalFXTiming *timing;
@end

@implementation MetalFXSlot
@end

static NSString *MetalFXCommandStatusName(MTLCommandBufferStatus status) {
    switch (status) {
        case MTLCommandBufferStatusNotEnqueued: return @"notEnqueued";
        case MTLCommandBufferStatusEnqueued: return @"enqueued";
        case MTLCommandBufferStatusCommitted: return @"committed";
        case MTLCommandBufferStatusScheduled: return @"scheduled";
        case MTLCommandBufferStatusCompleted: return @"completed";
        case MTLCommandBufferStatusError: return @"error";
    }
    return @"unknown";
}

@implementation MetalFXFrameRenderer {
    UIView *_view;
    CAMetalLayer *_layer;
    CADisplayLink *_paceLink;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLCommandQueue> _presentQueue;
    id<MTLRenderPipelineState> _yuvPipeline;
    id<MTLRenderPipelineState> _blitPipeline;
    CVMetalTextureCacheRef _textureCache;
    MetalFXSlot *_slots[2];
    MTLPixelFormat _colorFormat;
    BOOL _hdr;
    BOOL _expects10Bit;
    int _matrix;
    BOOL _fullRange;
    BOOL _observing;
    BOOL _invalid;
    BOOL _tornDown;
    BOOL _announcedFrame;
    NSInteger _skippedForLayout;
    NSInteger _nilDrawables;
    int _layoutDeferred;
    CGFloat _streamAspectRatio;
    CGSize _viewPixels;
    dispatch_queue_t _renderQueue;
    NSLock *_pendingLock;
    CVPixelBufferRef _pendingBuffer;
    CFTimeInterval _pendingDecodedAt;
    uint64_t _pendingSerial;
    uint64_t _latestSerial;
    BOOL _gpuBusy;
    uint64_t _gpuSerial;
    uint64_t _droppedFrames;
    NSUInteger _droppedPublished;
    BOOL _renderQueued;
    MetalFXFrameSchedule *_schedule;
    double _emaTotal;
    double _emaQueue;
    double _emaTexture;
    double _emaYuv;
    double _emaScaler;
    double _emaDrawable;
    double _emaGpu;
    double _emaPresent;
    int _latencySamples;
    int _latencyPublishedTenths;
    NSString *_latencyPublishedStage;
    int _publishedW;
    int _publishedH;
    int _publishedOutW;
    int _publishedOutH;
    CGSize _screenPixels;
    NSLock *_lock;
}

static NSLock *gStatsLock;
static NSString *gStatsLine;

+ (void)initialize {
    if (self != [MetalFXFrameRenderer class]) {
        return;
    }
    gStatsLock = [[NSLock alloc] init];
    gStatsLine = @"MetalFX off";
}

+ (NSString *)statsLine {
    [gStatsLock lock];
    NSString *line = gStatsLine ?: @"MetalFX off";
    [gStatsLock unlock];
    return line;
}

+ (void)publishStatsLine:(NSString *)line {
    if (line.length == 0) {
        line = @"MetalFX off";
    }
    [gStatsLock lock];
    gStatsLine = [line copy];
    [gStatsLock unlock];
}

+ (void)publishOff {
    [self publishStatsLine:[MetalFXLayout statsLineForMode:MetalFXStatsModeOff input:CGSizeZero output:CGSizeZero]];
}

+ (void)publishOffIfNotIdle {
    if ([[self statsLine] hasPrefix:@"MetalFX idle"]) {
        return;
    }
    [self publishOff];
}

+ (void)publishIdleStreamWidth:(NSInteger)width height:(NSInteger)height {
    [self publishStatsLine:[MetalFXLayout statsLineForMode:MetalFXStatsModeIdle
                                                     input:CGSizeMake(width, height)
                                                    output:CGSizeZero]];
}

+ (void)publishFallback {
    [self publishStatsLine:[MetalFXLayout statsLineForMode:MetalFXStatsModeFallback input:CGSizeZero output:CGSizeZero]];
}

+ (void)publishStarting {
    [self publishStatsLine:[MetalFXLayout statsLineForMode:MetalFXStatsModeStarting input:CGSizeZero output:CGSizeZero]];
}

+ (void)publishActiveInput:(CGSize)input output:(CGSize)output {
    [self publishStatsLine:[MetalFXLayout statsLineForMode:MetalFXStatsModeActive input:input output:output]];
}

+ (BOOL)deviceSupportsSpatialScaler {
#if TWILIGHT_HAS_METALFX
    if (@available(iOS 16.0, tvOS 16.0, *)) {
        // Weak-linked. A missing framework must not be messaged.
        if (NSClassFromString(@"MTLFXSpatialScalerDescriptor") == Nil) {
            return NO;
        }
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) {
            return NO;
        }
        return [MTLFXSpatialScalerDescriptor supportsDevice:device];
    }
#endif
    return NO;
}

+ (BOOL)hdrScalerAvailableOnDevice:(id<MTLDevice>)device {
#if TWILIGHT_HAS_METALFX
    if (@available(iOS 17.0, tvOS 17.0, *)) {
        if (device == nil || ![MTLFXSpatialScalerDescriptor supportsDevice:device]) {
            return NO;
        }
#if !TARGET_OS_TV
        if (UIScreen.mainScreen.potentialEDRHeadroom <= 1.0) {
            return NO;
        }
#endif
        return YES;
    }
#else
    (void)device;
#endif
    return NO;
}

+ (nullable instancetype)rendererForView:(UIView *)view hdr:(BOOL)hdr streamAspectRatio:(CGFloat)streamAspectRatio {
    if (view == nil || ![self deviceSupportsSpatialScaler]) {
        [self publishFallback];
        return nil;
    }
    MetalFXFrameRenderer *renderer = [[self alloc] init];
    renderer->_streamAspectRatio = streamAspectRatio;
    if (![renderer prepareWithView:view hdr:hdr]) {
        [renderer invalidate];
        [self publishFallback];
        return nil;
    }
    [self publishStarting];
    return renderer;
}

- (BOOL)prepareWithView:(UIView *)view hdr:(BOOL)hdr {
    _lock = [[NSLock alloc] init];
    _schedule = [[MetalFXFrameSchedule alloc] init];
    _view = view;
    _matrix = hdr ? 2 : 0;
    _device = MTLCreateSystemDefaultDevice();
    if (_device == nil) {
        Log(LOG_W, @"MetalFX: no Metal device");
        return NO;
    }
    if (hdr) {
        if (![MetalFXFrameRenderer hdrScalerAvailableOnDevice:_device]) {
            Log(LOG_W, @"MetalFX: HDR spatial scaler is not available, using the display layer");
            return NO;
        }
        _hdr = YES;
        _expects10Bit = YES;
        _colorFormat = MTLPixelFormatRGBA16Float;
    }
    else {
        _colorFormat = MTLPixelFormatBGRA8Unorm;
    }
    _queue = [_device newCommandQueue];
    _presentQueue = [_device newCommandQueue];
    if (_queue == nil || _presentQueue == nil) {
        Log(LOG_W, @"MetalFX: command queue was not created");
        return NO;
    }
    CVReturn cacheStatus = CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, _device, NULL, &_textureCache);
    if (cacheStatus != kCVReturnSuccess || _textureCache == NULL) {
        Log(LOG_W, @"MetalFX: texture cache failed (%d)", (int)cacheStatus);
        return NO;
    }
    NSError *error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:MetalFXShaderSource() options:[MTLCompileOptions new] error:&error];
    if (library == nil) {
        Log(LOG_W, @"MetalFX: shader compile failed: %@", error);
        return NO;
    }
    id<MTLFunction> vertex = [library newFunctionWithName:@"fullscreenVertex"];
    id<MTLFunction> yuv = [library newFunctionWithName:@"yuvToRgb"];
    id<MTLFunction> copy = [library newFunctionWithName:@"copyColor"];
    if (vertex == nil || yuv == nil || copy == nil) {
        Log(LOG_W, @"MetalFX: shader functions are missing");
        return NO;
    }
    _yuvPipeline = [self pipelineWithDevice:_device vertex:vertex fragment:yuv format:_colorFormat error:&error];
    _blitPipeline = [self pipelineWithDevice:_device vertex:vertex fragment:copy format:_colorFormat error:&error];
    if (_yuvPipeline == nil || _blitPipeline == nil) {
        Log(LOG_W, @"MetalFX: pipeline failed: %@", error);
        return NO;
    }

    _layer = [CAMetalLayer layer];
    _layer.device = _device;
    _layer.pixelFormat = _colorFormat;
    // A render blit targets the drawable. MetalFX writes a private texture, not this one.
    _layer.framebufferOnly = YES;
    _layer.opaque = YES;
    _layer.backgroundColor = [UIColor blackColor].CGColor;
    // One present is scheduled at a time. A third drawable keeps nextDrawable
    // from blocking when the one on screen has not been returned yet.
    _layer.maximumDrawableCount = 3;
    _layer.presentsWithTransaction = NO;
    [self lockLayerToScreenRate];
    [self startPaceLink];
#if !TARGET_OS_TV
    if (@available(iOS 18.0, *)) {
        _layer.allowsNextDrawableTimeout = YES;
    }
#endif
    // A hidden layer does not return drawables, so nextDrawable would block.
    _layer.hidden = NO;
    _renderQueue = dispatch_queue_create("twilight.metalfx.render", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
    _pendingLock = [[NSLock alloc] init];
    _latencyPublishedTenths = -1;
    if (_hdr) {
        if (@available(iOS 16.0, tvOS 16.0, *)) {
#if !TARGET_OS_TV
            // 10-bit frames are converted to linear light for the HDR scaler.
            // The extended-range flag matches that. It is not the present wait:
            // that wait is the layer's refresh interval, printed as "present".
            _layer.wantsExtendedDynamicRangeContent = YES;
#endif
            CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearITUR_2020);
            if (space == NULL) {
                space = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
            }
            _layer.colorspace = space;
            if (space != NULL) {
                CGColorSpaceRelease(space);
            }
        }
    }
    [self syncLayerToView];
    [_view.layer insertSublayer:_layer atIndex:0];
    [_view addObserver:self forKeyPath:@"bounds" options:0 context:MetalFXBoundsContext];
    _observing = YES;
    return YES;
}

- (id<MTLRenderPipelineState>)pipelineWithDevice:(id<MTLDevice>)device
                                          vertex:(id<MTLFunction>)vertex
                                        fragment:(id<MTLFunction>)fragment
                                          format:(MTLPixelFormat)format
                                           error:(NSError **)error {
    MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction = vertex;
    desc.fragmentFunction = fragment;
    desc.colorAttachments[0].pixelFormat = format;
    return [device newRenderPipelineStateWithDescriptor:desc error:error];
}

- (BOOL)expects10Bit {
    return _expects10Bit;
}

- (void)setColorMatrix:(int)matrix fullRange:(BOOL)fullRange {
    [_lock lock];
    _matrix = matrix;
    _fullRange = fullRange;
    [_lock unlock];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == MetalFXBoundsContext) {
        [self syncLayerToView];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)paceLinkFired:(CADisplayLink *)link {
    // Nothing to draw here. A link requesting 80–120 Hz is what keeps
    // ProMotion from clocking the panel down while Metal frames are presented.
    (void)link;
}

- (void)startPaceLink {
    void (^start)(void) = ^{
        if (self->_paceLink != nil || self->_invalid || self->_tornDown) {
            return;
        }
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(paceLinkFired:)];
        if (@available(iOS 15.0, tvOS 15.0, *)) {
            link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
        }
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        self->_paceLink = link;
    };
    if ([NSThread isMainThread]) {
        start();
    }
    else {
        dispatch_async(dispatch_get_main_queue(), start);
    }
}

- (void)stopPaceLink {
    void (^stop)(void) = ^{
        [self->_paceLink invalidate];
        self->_paceLink = nil;
    };
    if ([NSThread isMainThread]) {
        stop();
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), stop);
    }
}

- (void)lockLayerToScreenRate {
    if (_layer == nil) {
        return;
    }
    // Stay on the display clock. Turning sync off presents early and can
    // tear or stall drawable reuse. The display link above holds that clock
    // at 120 Hz; CAMetalLayer has no frame-rate property of its own.
    SEL displaySync = NSSelectorFromString(@"setDisplaySyncEnabled:");
    if ([_layer respondsToSelector:displaySync]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(_layer, displaySync, YES);
    }
}

- (void)syncLayerToView {
    if (_layer == nil || _view == nil) {
        return;
    }
    [self lockLayerToScreenRate];
    CGFloat scale = 0;
    if (_view.window.screen != nil) {
        scale = _view.window.screen.scale;
    }
    if (scale < 0.5) {
        scale = UIScreen.mainScreen.scale;
    }
    if (scale < 0.5) {
        scale = 1;
    }
    CGRect videoRect = [MetalFXLayout layerRectForBounds:_view.bounds streamAspectRatio:_streamAspectRatio];
    if (CGRectIsEmpty(videoRect)) {
        videoRect = _view.bounds;
    }
    // Assigning drawableSize drops every drawable the pool is holding.
    // Skip the write when layout has not actually changed.
    if (!CGRectEqualToRect(_layer.frame, videoRect)) {
        _layer.frame = videoRect;
    }
    if (_layer.contentsScale != scale) {
        _layer.contentsScale = scale;
    }
    CGSize drawableSize = CGSizeMake(MAX(1, round(videoRect.size.width * scale)),
                                     MAX(1, round(videoRect.size.height * scale)));
    // Resizing the drawable pool while a present is in flight drops that
    // drawable and can fault the display.
    if (!CGSizeEqualToSize(_layer.drawableSize, drawableSize)) {
        if (_schedule.presentInFlight) {
            __atomic_store_n(&_layoutDeferred, 1, __ATOMIC_RELEASE);
        }
        else {
            _layer.drawableSize = drawableSize;
        }
    }
    CGSize viewPixels = CGSizeMake(MAX(1, round(_view.bounds.size.width * scale)),
                                   MAX(1, round(_view.bounds.size.height * scale)));
    CGSize points = UIScreen.mainScreen.bounds.size;
    CGSize pixels = CGSizeMake(points.width * UIScreen.mainScreen.scale, points.height * UIScreen.mainScreen.scale);
#if TARGET_OS_TV
    BOOL phone = NO;
#else
    BOOL phone = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone;
#endif
    CGSize screen = [StreamVideoLayout interfaceSizeForSize:pixels landscapeOnly:phone];
    [_lock lock];
    _screenPixels = screen;
    _viewPixels = viewPixels;
    [_lock unlock];
}

- (void)failWithReason:(NSString *)reason {
    if (_invalid) {
        return;
    }
    _invalid = YES;
    Log(LOG_W, @"MetalFX fallback: %@", reason);
    [MetalFXFrameRenderer publishFallback];
    void (^handler)(NSString *) = [self.fallbackHandler copy];
    if (handler == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(reason);
    });
}

- (MetalFXSlot *)claimFreeSlot {
    for (int i = 0; i < 2; i++) {
        if (_slots[i] == nil) {
            _slots[i] = [[MetalFXSlot alloc] init];
        }
        if (!_slots[i].busy) {
            MetalFXSlot *slot = _slots[i];
            slot.busy = YES;
            slot.ready = NO;
            slot.presenting = NO;
            slot.discard = NO;
            slot.timing = nil;
            return slot;
        }
    }
    return nil;
}

- (BOOL)configureSlot:(MetalFXSlot *)slot inputWidth:(NSUInteger)inW height:(NSUInteger)inH output:(CGSize)output {
#if !TWILIGHT_HAS_METALFX
    (void)slot;
    (void)inW;
    (void)inH;
    (void)output;
    return NO;
#else
    NSUInteger outW = (NSUInteger)llround(output.width);
    NSUInteger outH = (NSUInteger)llround(output.height);
    if (outW < 2 || outH < 2) {
        return NO;
    }
    if (slot.scaler != nil && slot.rgb != nil && slot.scaled != nil &&
        slot.inW == inW && slot.inH == inH && slot.outW == outW && slot.outH == outH) {
        return YES;
    }
    if (@available(iOS 16.0, tvOS 16.0, *)) {
        MTLFXSpatialScalerDescriptor *desc = [[MTLFXSpatialScalerDescriptor alloc] init];
        desc.inputWidth = inW;
        desc.inputHeight = inH;
        desc.outputWidth = outW;
        desc.outputHeight = outH;
        desc.colorTextureFormat = _colorFormat;
        desc.outputTextureFormat = _colorFormat;
        if (_hdr) {
            if (@available(iOS 17.0, tvOS 17.0, *)) {
                desc.colorProcessingMode = MTLFXSpatialScalerColorProcessingModeHDR;
            }
            else {
                return NO;
            }
        }
        else {
            desc.colorProcessingMode = MTLFXSpatialScalerColorProcessingModePerceptual;
        }
        id<MTLFXSpatialScaler> scaler = [desc newSpatialScalerWithDevice:_device];
        if (scaler == nil) {
            Log(LOG_W, @"MetalFX: scaler was not created for %lux%lu -> %lux%lu", (unsigned long)inW, (unsigned long)inH, (unsigned long)outW, (unsigned long)outH);
            return NO;
        }
        MTLTextureDescriptor *rgbDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:_colorFormat width:inW height:inH mipmapped:NO];
        rgbDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        rgbDesc.storageMode = MTLStorageModePrivate;
        id<MTLTexture> rgb = [_device newTextureWithDescriptor:rgbDesc];
        MTLTextureDescriptor *outDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:_colorFormat width:outW height:outH mipmapped:NO];
        outDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        outDesc.storageMode = MTLStorageModePrivate;
        id<MTLTexture> scaled = [_device newTextureWithDescriptor:outDesc];
        if (rgb == nil || scaled == nil) {
            Log(LOG_W, @"MetalFX: intermediate textures were not created");
            return NO;
        }
        slot.scaler = scaler;
        slot.rgb = rgb;
        slot.scaled = scaled;
        slot.inW = inW;
        slot.inH = inH;
        slot.outW = outW;
        slot.outH = outH;
        return YES;
    }
    return NO;
#endif
}

- (void)finishSlot:(MetalFXSlot *)slot {
    slot.busy = NO;
    slot.ready = NO;
    slot.presenting = NO;
    slot.discard = NO;
    slot.timing = nil;
}

- (void)noteCommandBuffer:(id<MTLCommandBuffer>)buffer label:(NSString *)label {
    if (buffer.status == MTLCommandBufferStatusCompleted) {
        return;
    }
    Log(LOG_E, @"MetalFX %@ command buffer status %@ (%ld) %@",
        label,
        MetalFXCommandStatusName(buffer.status),
        (long)buffer.status,
        buffer.error);
    if (buffer.status == MTLCommandBufferStatusError) {
        [self failWithReason:[NSString stringWithFormat:@"%@ command buffer failed", label]];
    }
}

- (void)announceFirstFrame {
    if (_announcedFrame) {
        return;
    }
    _announcedFrame = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_layer.hidden = NO;
        void (^shown)(void) = self.firstFrameHandler;
        if (shown != nil) {
            shown();
        }
    });
}

- (void)recordTiming:(MetalFXTiming *)timing presentedAt:(CFTimeInterval)presentedAt {
    if (timing == nil || timing.decodedAt <= 0 || _invalid) {
        return;
    }
    double total = (presentedAt - timing.decodedAt) * 1000.0;
    if (total < 0 || total > 500) {
        return;
    }
    double presentMs = timing.presentCommit > 0 ? (presentedAt - timing.presentCommit) * 1000.0 : 0;
    if (presentMs < 0) {
        presentMs = 0;
    }
    if (_latencySamples == 0) {
        _emaTotal = total;
        _emaQueue = timing.queueMs;
        _emaTexture = timing.textureMs;
        _emaYuv = timing.yuvMs;
        _emaScaler = timing.scalerMs;
        _emaDrawable = timing.drawableMs;
        _emaGpu = timing.gpuMs;
        _emaPresent = presentMs;
    }
    else {
        _emaTotal = _emaTotal * 0.8 + total * 0.2;
        _emaQueue = _emaQueue * 0.8 + timing.queueMs * 0.2;
        _emaTexture = _emaTexture * 0.8 + timing.textureMs * 0.2;
        _emaYuv = _emaYuv * 0.8 + timing.yuvMs * 0.2;
        _emaScaler = _emaScaler * 0.8 + timing.scalerMs * 0.2;
        _emaDrawable = _emaDrawable * 0.8 + timing.drawableMs * 0.2;
        _emaGpu = _emaGpu * 0.8 + timing.gpuMs * 0.2;
        _emaPresent = _emaPresent * 0.8 + presentMs * 0.2;
    }
    _latencySamples++;
    NSString *stage = [MetalFXLayout dominantStageNameForQueueMs:_emaQueue
                                                        textureMs:_emaTexture
                                                            yuvMs:_emaYuv
                                                         scalerMs:_emaScaler
                                                       drawableMs:_emaDrawable
                                                            gpuMs:_emaGpu
                                                         presentMs:_emaPresent];
    int tenths = (int)llround(_emaTotal * 10.0);
    NSInteger droppedNow = (NSInteger)__atomic_load_n(&_droppedFrames, __ATOMIC_RELAXED);
    if (tenths == _latencyPublishedTenths && [stage isEqualToString:_latencyPublishedStage] && (NSUInteger)droppedNow == _droppedPublished) {
        return;
    }
    _latencyPublishedTenths = tenths;
    _latencyPublishedStage = stage;
    if (timing.inW >= 2 && timing.inH >= 2) {
        _publishedW = timing.inW;
        _publishedH = timing.inH;
        _publishedOutW = timing.outW;
        _publishedOutH = timing.outH;
    }
    if (_publishedW < 2 || _publishedH < 2) {
        return;
    }
    NSString *base = [MetalFXLayout statsLineForMode:MetalFXStatsModeActive
                                               input:CGSizeMake(_publishedW, _publishedH)
                                              output:CGSizeMake(_publishedOutW, _publishedOutH)];
    NSInteger dropped = (NSInteger)__atomic_load_n(&_droppedFrames, __ATOMIC_RELAXED);
    NSString *line = [MetalFXLayout statsLine:base
                              appendingTotalMs:_emaTotal
                                       queueMs:_emaQueue
                                     textureMs:_emaTexture
                                         yuvMs:_emaYuv
                                      scalerMs:_emaScaler
                                    drawableMs:_emaDrawable
                                         gpuMs:_emaGpu
                                      presentMs:_emaPresent
                                 droppedFrames:dropped];
    (void)stage;
    _droppedPublished = (NSUInteger)dropped;
    [MetalFXFrameRenderer publishStatsLine:line];
    Log(LOG_I, @"%@ (queue %.1f texture %.1f yuv %.1f scaler %.1f drawable %.1f gpu %.1f present %.1f)",
        line, _emaQueue, _emaTexture, _emaYuv, _emaScaler, _emaDrawable, _emaGpu, _emaPresent);
}

- (void)noteDroppedFrame {
    __atomic_fetch_add(&_droppedFrames, 1, __ATOMIC_RELAXED);
}

- (void)discardReadyFramesOlderThan:(uint64_t)serial {
    for (int i = 0; i < 2; i++) {
        MetalFXSlot *slot = _slots[i];
        if (slot == nil || !slot.ready || slot.presenting || slot.timing == nil) {
            continue;
        }
        if (slot.timing.serial < serial) {
            [self noteDroppedFrame];
            [self finishSlot:slot];
        }
    }
}

- (void)drainPendingFrames {
    if (_invalid || _tornDown) {
        return;
    }
    uint64_t pendingSerial = 0;
    [_pendingLock lock];
    BOOL hasPending = _pendingBuffer != NULL;
    pendingSerial = _pendingSerial;
    [_pendingLock unlock];
    if (hasPending) {
        [self discardReadyFramesOlderThan:pendingSerial];
    }
    [self startGpuForPendingFrame];
    [self presentLatestReadyFrame];
}

- (BOOL)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (_invalid || _tornDown || _layer == nil || pixelBuffer == NULL || _renderQueue == nil) {
        return YES;
    }
    // The decode callback only retains the newest buffer and returns.
    // It does not encode, take a drawable, or wait for the GPU.
    CFTimeInterval decodedAt = CACurrentMediaTime();
    CVPixelBufferRetain(pixelBuffer);
    [_pendingLock lock];
    CVPixelBufferRef dropped = _pendingBuffer;
    _latestSerial += 1;
    _pendingBuffer = pixelBuffer;
    _pendingDecodedAt = decodedAt;
    _pendingSerial = _latestSerial;
    BOOL kick = !_renderQueued;
    _renderQueued = YES;
    [_pendingLock unlock];
    if (dropped != NULL) {
        [self noteDroppedFrame];
        CVPixelBufferRelease(dropped);
    }
    if (kick) {
        dispatch_async(_renderQueue, ^{
            [self drainPendingFrames];
        });
    }
    return YES;
}

- (void)presentLatestReadyFrame {
    if (_invalid || _gpuBusy || _schedule.presentInFlight) {
        return;
    }
    uint64_t pendingSerial = 0;
    [_pendingLock lock];
    BOOL hasPending = _pendingBuffer != NULL;
    pendingSerial = _pendingSerial;
    [_pendingLock unlock];
    MetalFXSlot *newest = nil;
    for (int i = 0; i < 2; i++) {
        MetalFXSlot *slot = _slots[i];
        if (slot == nil || !slot.ready || slot.presenting || slot.timing == nil) {
            continue;
        }
        if (hasPending && slot.timing.serial < pendingSerial) {
            [self noteDroppedFrame];
            [self finishSlot:slot];
            continue;
        }
        if (newest == nil || slot.timing.serial > newest.timing.serial) {
            if (newest != nil) {
                [self noteDroppedFrame];
                [self finishSlot:newest];
            }
            newest = slot;
        }
        else {
            [self noteDroppedFrame];
            [self finishSlot:slot];
        }
    }
    if (newest != nil) {
        [self presentSlot:newest];
    }
}

- (void)startGpuForPendingFrame {
    if (_invalid || _tornDown || _gpuBusy) {
        return;
    }
    [_pendingLock lock];
    BOOL hasFrame = _pendingBuffer != NULL;
    [_pendingLock unlock];
    if (!hasFrame) {
        [_pendingLock lock];
        if (_pendingBuffer == NULL) {
            _renderQueued = NO;
        }
        [_pendingLock unlock];
        return;
    }
    MetalFXSlot *slot = [self claimFreeSlot];
    if (slot == nil) {
        // One texture is on the display and the other is the newest GPU result.
        return;
    }
    [_pendingLock lock];
    CVPixelBufferRef buffer = _pendingBuffer;
    CFTimeInterval decodedAt = _pendingDecodedAt;
    uint64_t serial = _pendingSerial;
    _pendingBuffer = NULL;
    if (buffer == NULL) {
        _renderQueued = NO;
        [_pendingLock unlock];
        [self finishSlot:slot];
        return;
    }
    [_pendingLock unlock];
    _gpuBusy = YES;
    _gpuSerial = serial;
    BOOL submitted = [self encodeGpuBuffer:buffer slot:slot decodedAt:decodedAt serial:serial];
    CVPixelBufferRelease(buffer);
    if (!submitted) {
        _gpuBusy = NO;
        [self finishSlot:slot];
    }
    [_pendingLock lock];
    BOOL more = _pendingBuffer != NULL;
    if (!more) {
        _renderQueued = NO;
    }
    [_pendingLock unlock];
    if (more) {
        [self startGpuForPendingFrame];
    }
}

- (void)presentSlot:(MetalFXSlot *)slot {
    if (slot == nil || slot.presenting || _invalid || _layer == nil) {
        return;
    }
    if (![_schedule tryBeginPresent]) {
        return;
    }
    MetalFXTiming *timing = slot.timing;
    CFTimeInterval acquireStart = CACurrentMediaTime();
    id<CAMetalDrawable> drawable = [_layer nextDrawable];
    double acquireMs = (CACurrentMediaTime() - acquireStart) * 1000.0;
    if (timing != nil) {
        double parked = timing.readyAt > 0 ? (acquireStart - timing.readyAt) * 1000.0 : 0;
        if (parked < 0) {
            parked = 0;
        }
        timing.drawableMs = parked + acquireMs;
    }
    if (drawable == nil) {
        [_schedule endPresent];
        _nilDrawables++;
        Log(LOG_W, @"MetalFX nextDrawable returned nil after %.1f ms (%ld in a row)", acquireMs, (long)_nilDrawables);
        slot.discard = YES;
        if (slot.ready) {
            [self finishSlot:slot];
        }
        if (_nilDrawables >= 30) {
            [self failWithReason:@"drawable pool did not return a texture"];
        }
        return;
    }
    _nilDrawables = 0;
    if (drawable.texture.width < slot.outW || drawable.texture.height < slot.outH) {
        [_schedule endPresent];
        slot.discard = YES;
        if (slot.ready) {
            [self finishSlot:slot];
        }
        return;
    }
    CGRect output = CGRectMake(floor((drawable.texture.width - slot.outW) / 2.0),
                               floor((drawable.texture.height - slot.outH) / 2.0),
                               slot.outW,
                               slot.outH);
    id<MTLCommandBuffer> presentBuffer = [_presentQueue commandBuffer];
    if (presentBuffer == nil) {
        [_schedule endPresent];
        [self failWithReason:@"present command buffer was not created"];
        return;
    }
    CGRect viewport = [MetalFXLayout metalViewportForOutputRect:output drawableHeight:drawable.texture.height];
    MTLRenderPassDescriptor *blitPass = [MTLRenderPassDescriptor renderPassDescriptor];
    blitPass.colorAttachments[0].texture = drawable.texture;
    blitPass.colorAttachments[0].loadAction = MTLLoadActionClear;
    blitPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    blitPass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> blit = [presentBuffer renderCommandEncoderWithDescriptor:blitPass];
    if (blit == nil) {
        [_schedule endPresent];
        [self failWithReason:@"blit encoder was not created"];
        return;
    }
    [blit setRenderPipelineState:_blitPipeline];
    [blit setFragmentTexture:slot.scaled atIndex:0];
    MTLViewport metalViewport = {
        viewport.origin.x, viewport.origin.y, viewport.size.width, viewport.size.height, 0, 1
    };
    [blit setViewport:metalViewport];
    [blit drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [blit endEncoding];

    slot.presenting = YES;
    slot.ready = NO;
    if (timing != nil) {
        timing.presentCommit = CACurrentMediaTime();
    }
    MetalFXTiming *presentedTiming = timing;
#if TWILIGHT_HAS_METALFX
    // The simulator Metal headers do not declare addPresentedHandler:.
    [drawable addPresentedHandler:^(id<MTLDrawable> presented) {
        (void)presented;
        CFTimeInterval shownAt = CACurrentMediaTime();
        dispatch_async(self->_renderQueue, ^{
            [self recordTiming:presentedTiming presentedAt:shownAt];
        });
    }];
#else
    (void)presentedTiming;
#endif
    // Plain present. afterMinimumDuration schedules an extra display interval
    // on ProMotion even when the duration is zero.
    [presentBuffer presentDrawable:drawable];
    MetalFXSlot *finished = slot;
    [presentBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_async(self->_renderQueue, ^{
            [self noteCommandBuffer:buffer label:@"present"];
            [self finishSlot:finished];
            [self->_schedule endPresent];
            if (__atomic_exchange_n(&self->_layoutDeferred, 0, __ATOMIC_ACQ_REL)) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self syncLayerToView];
                });
            }
            [self drainPendingFrames];
        });
    }];
    [presentBuffer commit];
    [self announceFirstFrame];
}

- (BOOL)encodeGpuBuffer:(CVPixelBufferRef)pixelBuffer slot:(MetalFXSlot *)slot decodedAt:(CFTimeInterval)decodedAt serial:(uint64_t)serial {
    CFTimeInterval started = CACurrentMediaTime();
    OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
    BOOL tenBit = format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
    BOOL bufferFull = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
    BOOL eightBit = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    if (!tenBit && !eightBit) {
        [self failWithReason:@"decoded frame format is not biplanar YUV"];
        return NO;
    }
    if (tenBit && !_hdr) {
        [self failWithReason:@"10-bit frame on the SDR path"];
        return NO;
    }
    if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
        [self failWithReason:@"decoded frame is not biplanar"];
        return NO;
    }
    size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    size_t uvWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
    size_t uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
    if (width < 2 || height < 2 || uvWidth < 1 || uvHeight < 1) {
        return NO;
    }
    CGSize drawablePixels = _layer.drawableSize;
    if (drawablePixels.width < 2 || drawablePixels.height < 2) {
        return NO;
    }
    CGFloat aspect = (CGFloat)width / (CGFloat)height;
    CGRect output = [MetalFXLayout outputRectForDrawablePixels:drawablePixels streamAspectRatio:aspect];
    if (CGRectIsEmpty(output)) {
        return NO;
    }
    CGSize screen;
    CGSize viewPixels;
    int matrix;
    [_lock lock];
    screen = _screenPixels;
    viewPixels = _viewPixels;
    matrix = _matrix;
    [_lock unlock];
    BOOL settled = screen.width < 2.0 || screen.height < 2.0 ||
        (viewPixels.width >= screen.width * 0.85 && viewPixels.height >= screen.height * 0.85);
    if (![MetalFXLayout canUpscaleInput:CGSizeMake(width, height) toOutput:output.size]) {
        if (!settled && _skippedForLayout < 45) {
            _skippedForLayout++;
            return NO;
        }
        [self failWithReason:@"output is not larger than the stream"];
        return NO;
    }
    if (![self configureSlot:slot inputWidth:width height:height output:output.size]) {
        [self failWithReason:@"spatial scaler setup failed"];
        return NO;
    }

    MetalFXTiming *timing = [[MetalFXTiming alloc] init];
    timing.decodedAt = decodedAt;
    timing.queueMs = (started - decodedAt) * 1000.0;
    timing.inW = (int)width;
    timing.inH = (int)height;
    timing.outW = (int)llround(output.size.width);
    timing.outH = (int)llround(output.size.height);
    timing.serial = serial;
    slot.timing = timing;

    CFTimeInterval textureStart = CACurrentMediaTime();
    MTLPixelFormat yFormat = tenBit ? MTLPixelFormatR16Unorm : MTLPixelFormatR8Unorm;
    MTLPixelFormat uvFormat = tenBit ? MTLPixelFormatRG16Unorm : MTLPixelFormatRG8Unorm;
    MetalFXHeldTextures *held = [[MetalFXHeldTextures alloc] init];
    CVMetalTextureRef yRef = NULL;
    CVMetalTextureRef uvRef = NULL;
    CVReturn yStatus = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, NULL, yFormat, width, height, 0, &yRef);
    CVReturn uvStatus = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, NULL, uvFormat, uvWidth, uvHeight, 1, &uvRef);
    held.y = yRef;
    held.uv = uvRef;
    timing.textureMs = (CACurrentMediaTime() - textureStart) * 1000.0;
    id<MTLTexture> yTex = yRef != NULL ? CVMetalTextureGetTexture(yRef) : nil;
    id<MTLTexture> uvTex = uvRef != NULL ? CVMetalTextureGetTexture(uvRef) : nil;
    if (yStatus != kCVReturnSuccess || uvStatus != kCVReturnSuccess || yTex == nil || uvTex == nil) {
        [self failWithReason:@"Metal texture cache rejected the frame"];
        return NO;
    }

#if !TWILIGHT_HAS_METALFX
    (void)matrix;
    (void)bufferFull;
    (void)held;
    [self failWithReason:@"MetalFX is unavailable"];
    return NO;
#else
    id<MTLCommandBuffer> commandBuffer = [_queue commandBuffer];
    if (commandBuffer == nil) {
        [self failWithReason:@"command buffer was not created"];
        return NO;
    }
    MetalFXYUVParams params;
    params.matrix = matrix;
    params.fullRange = bufferFull ? 1 : 0;
    params.tenBit = tenBit ? 1 : 0;
    if (_hdr && tenBit) {
        params.transfer = 1;
    }
    else if (_hdr) {
        params.transfer = 2;
    }
    else {
        params.transfer = 0;
    }

    CFTimeInterval yuvStart = CACurrentMediaTime();
    MTLRenderPassDescriptor *yuvPass = [MTLRenderPassDescriptor renderPassDescriptor];
    yuvPass.colorAttachments[0].texture = slot.rgb;
    yuvPass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    yuvPass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> yuvEncoder = [commandBuffer renderCommandEncoderWithDescriptor:yuvPass];
    if (yuvEncoder == nil) {
        [self failWithReason:@"YUV encoder was not created"];
        return NO;
    }
    [yuvEncoder setRenderPipelineState:_yuvPipeline];
    [yuvEncoder setFragmentTexture:yTex atIndex:0];
    [yuvEncoder setFragmentTexture:uvTex atIndex:1];
    [yuvEncoder setFragmentBytes:&params length:sizeof(params) atIndex:0];
    [yuvEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [yuvEncoder endEncoding];
    timing.yuvMs = (CACurrentMediaTime() - yuvStart) * 1000.0;

    if (@available(iOS 16.0, tvOS 16.0, *)) {
        CFTimeInterval scalerStart = CACurrentMediaTime();
        id<MTLFXSpatialScaler> scaler = slot.scaler;
        scaler.colorTexture = slot.rgb;
        // Private texture only. A drawable is not a shader-write target, and
        // writing it here faults the GPU.
        scaler.outputTexture = slot.scaled;
        scaler.inputContentWidth = width;
        scaler.inputContentHeight = height;
        [scaler encodeToCommandBuffer:commandBuffer];
        timing.scalerMs = (CACurrentMediaTime() - scalerStart) * 1000.0;
    }
    else {
        [self failWithReason:@"MetalFX is unavailable"];
        return NO;
    }

    CFTimeInterval workCommit = CACurrentMediaTime();
    MetalFXSlot *finished = slot;
    MetalFXTiming *gpuTiming = timing;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        // This buffer does not present, so the handler runs when the GPU
        // finishes the color conversion and the scaler, not at vsync.
        gpuTiming.gpuMs = (CACurrentMediaTime() - workCommit) * 1000.0;
        (void)held;
        dispatch_async(self->_renderQueue, ^{
            [self noteCommandBuffer:buffer label:@"gpu"];
            self->_gpuBusy = NO;
            uint64_t newest = 0;
            [self->_pendingLock lock];
            BOOL newerWaiting = self->_pendingBuffer != NULL && self->_pendingSerial > gpuTiming.serial;
            newest = self->_pendingSerial;
            [self->_pendingLock unlock];
            if (self->_invalid || finished.discard || newerWaiting) {
                if (newerWaiting) {
                    [self noteDroppedFrame];
                }
                (void)newest;
                [self finishSlot:finished];
                [self drainPendingFrames];
                return;
            }
            finished.ready = YES;
            finished.busy = YES;
            if (finished.timing != nil) {
                finished.timing.readyAt = CACurrentMediaTime();
            }
            [self drainPendingFrames];
        });
    }];
    [commandBuffer commit];
    _skippedForLayout = 0;
    return YES;
#endif
}

- (void)invalidate {
    if (_tornDown) {
        return;
    }
    _tornDown = YES;
    _invalid = YES;
    [self stopPaceLink];
    if (_pendingLock != nil) {
        [_pendingLock lock];
        CVPixelBufferRef pending = _pendingBuffer;
        _pendingBuffer = NULL;
        [_pendingLock unlock];
        if (pending != NULL) {
            CVPixelBufferRelease(pending);
        }
    }
    if (_renderQueue != nil) {
        dispatch_sync(_renderQueue, ^{});
    }
    if (_observing && _view != nil) {
        [_view removeObserver:self forKeyPath:@"bounds" context:MetalFXBoundsContext];
        _observing = NO;
    }
    void (^remove)(void) = ^{
        [self->_layer removeFromSuperlayer];
        self->_layer = nil;
    };
    if ([NSThread isMainThread]) {
        remove();
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), remove);
    }
    if (_textureCache != NULL) {
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
    _slots[0] = nil;
    _slots[1] = nil;
    _view = nil;
}

- (void)dealloc {
    [self invalidate];
}

@end
