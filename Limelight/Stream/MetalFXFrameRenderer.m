//
//  MetalFXFrameRenderer.m
//  Moonlight
//
//  CVPixelBuffer -> CVMetalTextureCache -> YUV to RGB -> MTLFXSpatialScaler
//  -> aspect-fit blit into a CAMetalLayer. No CPU frame queue: a second frame
//  that arrives while one is encoding is dropped, and the layer keeps two
//  drawables so the display is not holding an extra queued frame.
//

#import "MetalFXFrameRenderer.h"
#import "MetalFXLayout.h"
#import "StreamVideoLayout.h"

#import <Metal/Metal.h>
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

@implementation MetalFXFrameRenderer {
    UIView *_view;
    CAMetalLayer *_layer;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _yuvPipeline;
    id<MTLRenderPipelineState> _blitPipeline;
    CVMetalTextureCacheRef _textureCache;
    id _scaler;
    id<MTLTexture> _rgbTexture;
    id<MTLTexture> _scaledTexture;
    NSUInteger _scalerInW;
    NSUInteger _scalerInH;
    NSUInteger _scalerOutW;
    NSUInteger _scalerOutH;
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
    int _publishedW;
    int _publishedH;
    int _publishedOutW;
    int _publishedOutH;
    CGSize _screenPixels;
    NSLock *_lock;
    NSLock *_renderLock;
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
        if (UIScreen.mainScreen.potentialEDRHeadroom <= 1.0) {
            return NO;
        }
        return YES;
    }
#else
    (void)device;
#endif
    return NO;
}

+ (nullable instancetype)rendererForView:(UIView *)view hdr:(BOOL)hdr {
    if (view == nil || ![self deviceSupportsSpatialScaler]) {
        [self publishFallback];
        return nil;
    }
    MetalFXFrameRenderer *renderer = [[self alloc] init];
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
    _renderLock = [[NSLock alloc] init];
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
    if (_queue == nil) {
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
    _layer.framebufferOnly = YES;
    _layer.opaque = YES;
    _layer.backgroundColor = [UIColor blackColor].CGColor;
    _layer.maximumDrawableCount = 2;
    _layer.hidden = YES;
    if (_hdr) {
        if (@available(iOS 16.0, tvOS 16.0, *)) {
            _layer.wantsExtendedDynamicRangeContent = YES;
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

- (void)syncLayerToView {
    if (_layer == nil || _view == nil) {
        return;
    }
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
    _layer.frame = _view.bounds;
    _layer.contentsScale = scale;
    _layer.drawableSize = CGSizeMake(MAX(1, round(_view.bounds.size.width * scale)),
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

- (BOOL)rebuildScalerInputWidth:(NSUInteger)inW height:(NSUInteger)inH output:(CGSize)output {
#if !TWILIGHT_HAS_METALFX
    (void)inW;
    (void)inH;
    (void)output;
    return NO;
#else
    NSUInteger outW = (NSUInteger)llround(output.width);
    NSUInteger outH = (NSUInteger)llround(output.height);
    if (_scaler != nil && _scalerInW == inW && _scalerInH == inH && _scalerOutW == outW && _scalerOutH == outH && _scaledTexture != nil && _rgbTexture != nil) {
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
        _scaler = scaler;
        _rgbTexture = rgb;
        _scaledTexture = scaled;
        _scalerInW = inW;
        _scalerInH = inH;
        _scalerOutW = outW;
        _scalerOutH = outH;
        return YES;
    }
    return NO;
#endif
}

- (BOOL)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (_invalid || _tornDown || _layer == nil || pixelBuffer == NULL) {
        return YES;
    }
    if (![_renderLock tryLock]) {
        // A frame is already encoding. Drop this one instead of queueing it.
        return YES;
    }
    BOOL submitted = [self encodePixelBuffer:pixelBuffer];
    [_renderLock unlock];
    return submitted;
}

- (BOOL)encodePixelBuffer:(CVPixelBufferRef)pixelBuffer {
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
        return YES;
    }
    if (_textureCache != NULL) {
        CVMetalTextureCacheFlush(_textureCache, 0);
    }
    CGSize drawablePixels = _layer.drawableSize;
    if (drawablePixels.width < 2 || drawablePixels.height < 2) {
        return YES;
    }
    CGFloat aspect = (CGFloat)width / (CGFloat)height;
    CGRect output = [MetalFXLayout outputRectForDrawablePixels:drawablePixels streamAspectRatio:aspect];
    if (CGRectIsEmpty(output)) {
        return YES;
    }
    CGSize screen;
    int matrix;
    [_lock lock];
    screen = _screenPixels;
    matrix = _matrix;
    [_lock unlock];
    BOOL settled = screen.width < 2.0 || screen.height < 2.0 ||
        (drawablePixels.width >= screen.width * 0.85 && drawablePixels.height >= screen.height * 0.85);
    if (![MetalFXLayout canUpscaleInput:CGSizeMake(width, height) toOutput:output.size]) {
        if (!settled && _skippedForLayout < 45) {
            _skippedForLayout++;
            return YES;
        }
        [self failWithReason:@"output is not larger than the stream"];
        return NO;
    }
    if (![self rebuildScalerInputWidth:width height:height output:output.size]) {
        [self failWithReason:@"spatial scaler setup failed"];
        return NO;
    }

    MTLPixelFormat yFormat = tenBit ? MTLPixelFormatR16Unorm : MTLPixelFormatR8Unorm;
    MTLPixelFormat uvFormat = tenBit ? MTLPixelFormatRG16Unorm : MTLPixelFormatRG8Unorm;
    MetalFXHeldTextures *held = [[MetalFXHeldTextures alloc] init];
    CVMetalTextureRef yRef = NULL;
    CVMetalTextureRef uvRef = NULL;
    CVReturn yStatus = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, NULL, yFormat, width, height, 0, &yRef);
    CVReturn uvStatus = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pixelBuffer, NULL, uvFormat, uvWidth, uvHeight, 1, &uvRef);
    held.y = yRef;
    held.uv = uvRef;
    id<MTLTexture> yTex = yRef != NULL ? CVMetalTextureGetTexture(yRef) : nil;
    id<MTLTexture> uvTex = uvRef != NULL ? CVMetalTextureGetTexture(uvRef) : nil;
    if (yStatus != kCVReturnSuccess || uvStatus != kCVReturnSuccess || yTex == nil || uvTex == nil) {
        [self failWithReason:@"Metal texture cache rejected the frame"];
        return NO;
    }

    id<CAMetalDrawable> metalDrawable = [_layer nextDrawable];
    if (metalDrawable == nil) {
        return YES;
    }
    id<MTLCommandBuffer> commandBuffer = [_queue commandBuffer];
    if (commandBuffer == nil) {
        [self failWithReason:@"command buffer was not created"];
        return NO;
    }

    MetalFXYUVParams params;
    params.matrix = matrix;
    // The decompression session asks for limited range. The buffer's own
    // format is what the sampler produced.
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

    MTLRenderPassDescriptor *yuvPass = [MTLRenderPassDescriptor renderPassDescriptor];
    yuvPass.colorAttachments[0].texture = _rgbTexture;
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

#if !TWILIGHT_HAS_METALFX
    (void)metalDrawable;
    (void)commandBuffer;
    (void)params;
    [self failWithReason:@"MetalFX is unavailable"];
    return NO;
#else
    if (@available(iOS 16.0, tvOS 16.0, *)) {
        id<MTLFXSpatialScaler> scaler = _scaler;
        scaler.colorTexture = _rgbTexture;
        scaler.outputTexture = _scaledTexture;
        scaler.inputContentWidth = width;
        scaler.inputContentHeight = height;
        [scaler encodeToCommandBuffer:commandBuffer];
    }
    else {
        [self failWithReason:@"MetalFX is unavailable"];
        return NO;
    }

    CGRect viewport = [MetalFXLayout metalViewportForOutputRect:output drawableHeight:metalDrawable.texture.height];
    MTLRenderPassDescriptor *blitPass = [MTLRenderPassDescriptor renderPassDescriptor];
    blitPass.colorAttachments[0].texture = metalDrawable.texture;
    blitPass.colorAttachments[0].loadAction = MTLLoadActionClear;
    blitPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    blitPass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> blit = [commandBuffer renderCommandEncoderWithDescriptor:blitPass];
    if (blit == nil) {
        [self failWithReason:@"blit encoder was not created"];
        return NO;
    }
    [blit setRenderPipelineState:_blitPipeline];
    [blit setFragmentTexture:_scaledTexture atIndex:0];
    MTLViewport metalViewport = {
        viewport.origin.x, viewport.origin.y, viewport.size.width, viewport.size.height, 0, 1
    };
    [blit setViewport:metalViewport];
    [blit drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [blit endEncoding];

    [commandBuffer presentDrawable:metalDrawable];
    id scaler = _scaler;
    id<MTLTexture> rgb = _rgbTexture;
    id<MTLTexture> scaled = _scaledTexture;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        (void)held;
        (void)scaler;
        (void)rgb;
        (void)scaled;
        (void)buffer;
    }];
    [commandBuffer commit];

    _skippedForLayout = 0;
    int inW = (int)width;
    int inH = (int)height;
    int outW = (int)llround(output.size.width);
    int outH = (int)llround(output.size.height);
    if (_publishedW != inW || _publishedH != inH || _publishedOutW != outW || _publishedOutH != outH) {
        _publishedW = inW;
        _publishedH = inH;
        _publishedOutW = outW;
        _publishedOutH = outH;
        [MetalFXFrameRenderer publishActiveInput:CGSizeMake(inW, inH) output:CGSizeMake(outW, outH)];
    }
    if (!_announcedFrame) {
        _announcedFrame = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_layer.hidden = NO;
            void (^shown)(void) = self.firstFrameHandler;
            if (shown != nil) {
                shown();
            }
        });
    }
    return YES;
#endif
}

- (void)invalidate {
    if (_tornDown) {
        return;
    }
    _tornDown = YES;
    _invalid = YES;
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
    _scaler = nil;
    _rgbTexture = nil;
    _scaledTexture = nil;
    _view = nil;
}

- (void)dealloc {
    [self invalidate];
}

@end
