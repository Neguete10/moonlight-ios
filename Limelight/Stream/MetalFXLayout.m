//
//  MetalFXLayout.m
//  Moonlight
//

#import "MetalFXLayout.h"
#import "StreamVideoLayout.h"

@implementation MetalFXLayout

+ (NSInteger)normalizedScalePercent:(NSInteger)percent {
    if (percent == 50 || percent == 67 || percent == 75) {
        return percent;
    }
    return 0;
}

+ (NSInteger)scalePercentForChoiceIndex:(NSInteger)index {
    switch (index) {
        case 0:
            return 50;
        case 1:
            return 67;
        case 2:
            return 75;
        default:
            return 0;
    }
}

+ (NSInteger)choiceIndexForScalePercent:(NSInteger)percent {
    switch ([self normalizedScalePercent:percent]) {
        case 50:
            return 0;
        case 67:
            return 1;
        case 75:
            return 2;
        default:
            return 3;
    }
}

+ (NSInteger)evenDown:(NSInteger)value {
    if (value < 2) {
        return 2;
    }
    value &= ~1;
    return value < 2 ? 2 : value;
}

+ (NSInteger)scaledEven:(NSInteger)value percent:(NSInteger)percent {
    NSInteger scaled = value;
    if (percent == 50) {
        scaled = value / 2;
    }
    else if (percent == 67) {
        // Two thirds. The settings label says 67%.
        scaled = (value * 2) / 3;
    }
    else if (percent == 75) {
        scaled = (value * 3) / 4;
    }
    return [self evenDown:scaled];
}

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

+ (CGSize)hostSizeForNativePixels:(CGSize)nativePixels
                      chosenWidth:(NSInteger)chosenWidth
                     chosenHeight:(NSInteger)chosenHeight
                     scalePercent:(NSInteger)scalePercent
                          enabled:(BOOL)enabled
                    landscapeOnly:(BOOL)landscapeOnly {
    CGSize chosen = [StreamVideoLayout streamSizeForWidth:chosenWidth
                                                    height:chosenHeight
                                             landscapeOnly:landscapeOnly];
    NSInteger percent = [self normalizedScalePercent:scalePercent];
    if (!enabled || percent == 0) {
        return chosen;
    }
    CGSize native = [StreamVideoLayout interfaceSizeForSize:nativePixels landscapeOnly:landscapeOnly];
    if (native.width < 2.0 || native.height < 2.0) {
        return chosen;
    }
    NSInteger nativeW = [self evenDown:(NSInteger)floor(native.width)];
    NSInteger nativeH = [self evenDown:(NSInteger)floor(native.height)];
    NSInteger width = [self scaledEven:nativeW percent:percent];
    NSInteger height = [self scaledEven:nativeH percent:percent];
    // The upscaler needs the host picture to be smaller than the screen.
    if (width >= nativeW && nativeW > 2) {
        width = [self evenDown:nativeW - 2];
    }
    if (height >= nativeH && nativeH > 2) {
        height = [self evenDown:nativeH - 2];
    }
    return CGSizeMake(width, height);
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
        case MetalFXStatsModeOff:
        default:
            return @"MetalFX off";
    }
}

@end
