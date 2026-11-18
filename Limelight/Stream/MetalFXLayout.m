//
//  MetalFXLayout.m
//  Moonlight
//

#import "MetalFXLayout.h"
#import "StreamVideoLayout.h"

@implementation MetalFXLayout

+ (BOOL)size:(CGSize)size matches:(CGSize)other {
    return fabs(size.width - other.width) <= 2.0 && fabs(size.height - other.height) <= 2.0;
}

+ (CGSize)nativeBaseForChosenWidth:(NSInteger)chosenWidth
                            height:(NSInteger)chosenHeight
                        safePixels:(CGSize)safePixels
                        fullPixels:(CGSize)fullPixels
                     landscapeOnly:(BOOL)landscapeOnly {
    CGSize chosen = [StreamVideoLayout streamSizeForWidth:chosenWidth
                                                    height:chosenHeight
                                             landscapeOnly:landscapeOnly];
    CGSize safeSize = [StreamVideoLayout streamSizeForWidth:(NSInteger)llround(safePixels.width)
                                                      height:(NSInteger)llround(safePixels.height)
                                               landscapeOnly:landscapeOnly];
    CGSize fullSize = [StreamVideoLayout streamSizeForWidth:(NSInteger)llround(fullPixels.width)
                                                      height:(NSInteger)llround(fullPixels.height)
                                               landscapeOnly:landscapeOnly];
    if ([self size:chosen matches:safeSize]) {
        return safeSize;
    }
    if ([self size:chosen matches:fullSize]) {
        return fullSize;
    }
    return chosen;
}

+ (CGSize)hostSizeForChosenWidth:(NSInteger)chosenWidth
                          height:(NSInteger)chosenHeight
                   landscapeOnly:(BOOL)landscapeOnly {
    return [StreamVideoLayout streamSizeForWidth:chosenWidth
                                          height:chosenHeight
                                   landscapeOnly:landscapeOnly];
}

+ (BOOL)shouldUpscaleStreamWidth:(NSInteger)width
                          height:(NSInteger)height
                    screenPixels:(CGSize)screenPixels
                   landscapeOnly:(BOOL)landscapeOnly {
    CGSize stream = [self hostSizeForChosenWidth:width height:height landscapeOnly:landscapeOnly];
    CGSize screen = [StreamVideoLayout interfaceSizeForSize:screenPixels landscapeOnly:landscapeOnly];
    if (stream.width < 2.0 || stream.height < 2.0 || screen.width < 2.0 || screen.height < 2.0) {
        return NO;
    }
    CGRect output = [self outputRectForDrawablePixels:screen streamAspectRatio:stream.width / stream.height];
    return [self canUpscaleInput:stream toOutput:output.size];
}

+ (CGRect)layerRectForBounds:(CGRect)bounds streamAspectRatio:(CGFloat)aspectRatio {
    return [StreamVideoLayout videoRectForBounds:bounds streamAspectRatio:aspectRatio];
}

+ (CGRect)outputRectForDrawablePixels:(CGSize)drawable streamAspectRatio:(CGFloat)aspectRatio {
    CGRect rect = [StreamVideoLayout videoRectForBounds:CGRectMake(0, 0, drawable.width, drawable.height)
                                     streamAspectRatio:aspectRatio];
    if (CGRectIsEmpty(rect)) {
        return CGRectZero;
    }
    CGRect pixel = CGRectMake(round(rect.origin.x),
                              round(rect.origin.y),
                              round(rect.size.width),
                              round(rect.size.height));
    if (pixel.size.width < 2.0 || pixel.size.height < 2.0) {
        return CGRectZero;
    }
    if (pixel.origin.x < 0) {
        pixel.origin.x = 0;
    }
    if (pixel.origin.y < 0) {
        pixel.origin.y = 0;
    }
    if (CGRectGetMaxX(pixel) > drawable.width) {
        pixel.size.width = MAX(2.0, drawable.width - pixel.origin.x);
    }
    if (CGRectGetMaxY(pixel) > drawable.height) {
        pixel.size.height = MAX(2.0, drawable.height - pixel.origin.y);
    }
    return pixel;
}

+ (CGRect)metalViewportForOutputRect:(CGRect)outputRect drawableHeight:(CGFloat)drawableHeight {
    if (CGRectIsEmpty(outputRect) || drawableHeight < 1.0) {
        return CGRectZero;
    }
    CGFloat y = drawableHeight - CGRectGetMaxY(outputRect);
    if (y < 0) {
        y = 0;
    }
    return CGRectMake(outputRect.origin.x, y, outputRect.size.width, outputRect.size.height);
}

+ (BOOL)canUpscaleInput:(CGSize)input toOutput:(CGSize)output {
    NSInteger inW = (NSInteger)llround(input.width);
    NSInteger inH = (NSInteger)llround(input.height);
    NSInteger outW = (NSInteger)llround(output.width);
    NSInteger outH = (NSInteger)llround(output.height);
    if (inW < 2 || inH < 2 || outW < 2 || outH < 2) {
        return NO;
    }
    if (outW < inW || outH < inH) {
        return NO;
    }
    if (outW == inW && outH == inH) {
        return NO;
    }
    return YES;
}

+ (NSString *)statsLineForMode:(MetalFXStatsMode)mode input:(CGSize)input output:(CGSize)output {
    switch (mode) {
        case MetalFXStatsModeActive:
            if (input.width >= 2.0 && input.height >= 2.0 && output.width >= 2.0 && output.height >= 2.0) {
                return [NSString stringWithFormat:@"MetalFX active %dx%d -> %dx%d",
                        (int)llround(input.width), (int)llround(input.height),
                        (int)llround(output.width), (int)llround(output.height)];
            }
            return @"MetalFX active";
        case MetalFXStatsModeStarting:
            return @"MetalFX starting";
        case MetalFXStatsModeFallback:
            return @"MetalFX fallback";
        case MetalFXStatsModeIdle:
            if (input.width >= 2.0 && input.height >= 2.0) {
                return [NSString stringWithFormat:@"MetalFX idle %dx%d",
                        (int)llround(input.width), (int)llround(input.height)];
            }
            return @"MetalFX idle";
        case MetalFXStatsModeOff:
        default:
            return @"MetalFX off";
    }
}

+ (NSString *)statsLine:(NSString *)line appendingLatencyMs:(double)latencyMs {
    return [self statsLine:line appendingLatencyMs:latencyMs stage:nil];
}

+ (NSString *)statsLine:(NSString *)line appendingLatencyMs:(double)latencyMs stage:(NSString *)stage {
    return [self statsLine:line appendingLatencyMs:latencyMs stage:stage droppedFrames:-1];
}

+ (NSString *)statsLine:(NSString *)line
     appendingLatencyMs:(double)latencyMs
                  stage:(NSString *)stage
          droppedFrames:(NSInteger)droppedFrames {
    if (line.length == 0 || latencyMs < 0) {
        return line ?: @"";
    }
    NSString *timed = stage.length == 0
        ? [NSString stringWithFormat:@"%@ +%.1f ms", line, latencyMs]
        : [NSString stringWithFormat:@"%@ +%.1f ms %@", line, latencyMs, stage];
    if (droppedFrames < 0) {
        return timed;
    }
    return [NSString stringWithFormat:@"%@ drop %ld", timed, (long)droppedFrames];
}

+ (NSString *)dominantStageNameForQueueMs:(double)queueMs
                                 textureMs:(double)textureMs
                                     yuvMs:(double)yuvMs
                                  scalerMs:(double)scalerMs
                                drawableMs:(double)drawableMs
                                     gpuMs:(double)gpuMs
                                  presentMs:(double)presentMs {
    NSString *name = @"queue";
    double best = queueMs;
    if (textureMs > best) { best = textureMs; name = @"texture"; }
    if (yuvMs > best) { best = yuvMs; name = @"yuv"; }
    if (scalerMs > best) { best = scalerMs; name = @"scaler"; }
    if (drawableMs > best) { best = drawableMs; name = @"drawable"; }
    if (gpuMs > best) { best = gpuMs; name = @"gpu"; }
    if (presentMs > best) { name = @"present"; }
    return name;
}

@end

@implementation MetalFXFrameSchedule {
    NSLock *_lock;
    uint64_t _pending;
    BOOL _presenting;
    NSUInteger _submitted;
    NSUInteger _dropped;
    NSUInteger _presented;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (uint64_t)submitFrame:(uint64_t)frameId {
    if (frameId == 0) {
        return 0;
    }
    [_lock lock];
    _submitted++;
    uint64_t dropped = _pending;
    if (dropped != 0) {
        _dropped++;
    }
    _pending = frameId;
    [_lock unlock];
    return dropped;
}

- (uint64_t)beginPresent {
    [_lock lock];
    uint64_t frame = 0;
    if (!_presenting && _pending != 0) {
        frame = _pending;
        _pending = 0;
        _presenting = YES;
        _presented++;
    }
    [_lock unlock];
    return frame;
}

- (BOOL)tryBeginPresent {
    [_lock lock];
    BOOL ok = !_presenting;
    if (ok) {
        _presenting = YES;
    }
    [_lock unlock];
    return ok;
}

- (void)endPresent {
    [_lock lock];
    _presenting = NO;
    [_lock unlock];
}

- (NSUInteger)submittedFrames {
    [_lock lock];
    NSUInteger value = _submitted;
    [_lock unlock];
    return value;
}

- (NSUInteger)droppedFrames {
    [_lock lock];
    NSUInteger value = _dropped;
    [_lock unlock];
    return value;
}

- (NSUInteger)presentedFrames {
    [_lock lock];
    NSUInteger value = _presented;
    [_lock unlock];
    return value;
}

- (BOOL)presentInFlight {
    [_lock lock];
    BOOL value = _presenting;
    [_lock unlock];
    return value;
}

@end
