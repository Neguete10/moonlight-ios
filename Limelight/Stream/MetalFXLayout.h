//
//  MetalFXLayout.h
//  Moonlight
//
//  Host resolution and screen-fit math for optional MetalFX spatial upscaling.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MetalFXStatsMode) {
    MetalFXStatsModeOff = 0,
    MetalFXStatsModeStarting,
    MetalFXStatsModeActive,
    MetalFXStatsModeFallback,
};

@interface MetalFXLayout : NSObject

/// 50, 67, and 75 are fractions of the screen. Anything else means the
/// resolution the user already picked.
+ (NSInteger)normalizedScalePercent:(NSInteger)percent;
+ (NSInteger)scalePercentForChoiceIndex:(NSInteger)index;
+ (NSInteger)choiceIndexForScalePercent:(NSInteger)percent;

/// Which picture the percent modes shrink. Safe Area uses the safe-area
/// pixels, Full uses the full-bleed pixels, and a fixed resolution uses
/// that resolution so the stream keeps its aspect.
+ (CGSize)nativeBaseForChosenWidth:(NSInteger)chosenWidth
                            height:(NSInteger)chosenHeight
                        safePixels:(CGSize)safePixels
                        fullPixels:(CGSize)fullPixels
                     landscapeOnly:(BOOL)landscapeOnly;

/// Size to request from the host. Percent modes shrink nativePixels
/// (the safe-area size, the full-bleed size, or a fixed resolution).
/// Disabled, or a percent of 0, keeps the chosen resolution.
+ (CGSize)hostSizeForNativePixels:(CGSize)nativePixels
                      chosenWidth:(NSInteger)chosenWidth
                     chosenHeight:(NSInteger)chosenHeight
                     scalePercent:(NSInteger)scalePercent
                          enabled:(BOOL)enabled
                    landscapeOnly:(BOOL)landscapeOnly;

/// The rect the Metal layer occupies. Same aspect-fit rect as the
/// sample-buffer display layer.
+ (CGRect)layerRectForBounds:(CGRect)bounds streamAspectRatio:(CGFloat)aspectRatio;

/// Aspect-fit rect in drawable pixels, origin at the top left.
+ (CGRect)outputRectForDrawablePixels:(CGSize)drawable
                    streamAspectRatio:(CGFloat)aspectRatio;

/// Metal's viewport origin is the bottom left. Same rect, flipped vertically.
+ (CGRect)metalViewportForOutputRect:(CGRect)outputRect
                      drawableHeight:(CGFloat)drawableHeight;

/// Spatial upscale needs a strictly larger output on at least one axis,
/// and neither axis smaller than the input.
+ (BOOL)canUpscaleInput:(CGSize)input toOutput:(CGSize)output;

+ (NSString *)statsLineForMode:(MetalFXStatsMode)mode
                         input:(CGSize)input
                        output:(CGSize)output;

/// Appends " +1.2 ms" when latencyMs is zero or positive. A negative value leaves the line unchanged.
/// The number is decode-callback to on-screen present, not the scaler's GPU time alone.
+ (NSString *)statsLine:(NSString *)line appendingLatencyMs:(double)latencyMs;

/// Same line with the stage that consumed the most of that time: queue, texture,
/// yuv, scaler, drawable, gpu, or present.
+ (NSString *)statsLine:(NSString *)line appendingLatencyMs:(double)latencyMs stage:(nullable NSString *)stage;

/// Name of the largest stage. Equal values keep the earlier name.
+ (NSString *)dominantStageNameForQueueMs:(double)queueMs
                                 textureMs:(double)textureMs
                                     yuvMs:(double)yuvMs
                                  scalerMs:(double)scalerMs
                                drawableMs:(double)drawableMs
                                     gpuMs:(double)gpuMs
                                  presentMs:(double)presentMs;

@end

/// Keeps the newest submitted frame and allows only one present at a time.
/// submitFrame: is safe from the decode thread. beginPresent and endPresent
/// are safe from the render thread at the same time.
@interface MetalFXFrameSchedule : NSObject

@property (nonatomic, readonly) NSUInteger submittedFrames;
@property (nonatomic, readonly) NSUInteger droppedFrames;
@property (nonatomic, readonly) NSUInteger presentedFrames;
@property (nonatomic, readonly) BOOL presentInFlight;

/// Replaces a frame that has not started presenting. Returns the dropped id, or 0.
- (uint64_t)submitFrame:(uint64_t)frameId;

/// Claims the pending frame. Returns 0 when a present is already in flight or nothing is waiting.
- (uint64_t)beginPresent;

/// Marks a present in flight even when the caller tracks the pixel buffer itself.
/// Returns NO if one is already in flight, so the caller does not block on a drawable.
- (BOOL)tryBeginPresent;

- (void)endPresent;

@end

NS_ASSUME_NONNULL_END
