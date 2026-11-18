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

/// Size to request from the host. Percent modes use the screen pixels
/// (a landscape-only phone whose pixel size is still portrait is swapped).
/// Disabled, or a percent of 0, keeps the chosen resolution.
+ (CGSize)hostSizeForNativePixels:(CGSize)nativePixels
                      chosenWidth:(NSInteger)chosenWidth
                     chosenHeight:(NSInteger)chosenHeight
                     scalePercent:(NSInteger)scalePercent
                          enabled:(BOOL)enabled
                    landscapeOnly:(BOOL)landscapeOnly;

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

@end

NS_ASSUME_NONNULL_END
