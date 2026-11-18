//
//  MetalFXFrameRenderer.h
//  Moonlight
//
//  Draws a decoded biplanar frame through YUV to RGB and MTLFXSpatialScaler.
//  A nil renderer means the caller should keep using AVSampleBufferDisplayLayer.
//

#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MetalFXFrameRenderer : NSObject

+ (BOOL)deviceSupportsSpatialScaler;
+ (NSString *)statsLine;
+ (void)publishOff;
+ (void)publishFallback;
+ (void)publishStarting;
+ (void)publishActiveInput:(CGSize)input output:(CGSize)output;

/// nil when the device, the shader, or an HDR target cannot be set up.
+ (nullable instancetype)rendererForView:(UIView *)view hdr:(BOOL)hdr;

/// The drawable is a linear extended-range target and 10-bit input is preferred.
@property (nonatomic, readonly) BOOL expects10Bit;

/// Called on the main queue after this renderer gives up. The frame in flight
/// is not shown here.
@property (nonatomic, copy, nullable) void (^fallbackHandler)(NSString *reason);

/// Called on the main queue the first time a frame is presented.
@property (nonatomic, copy, nullable) void (^firstFrameHandler)(void);

/// matrix: 0 BT.709, 1 BT.601, 2 BT.2020.
- (void)setColorMatrix:(int)matrix fullRange:(BOOL)fullRange;

/// YES when the frame was consumed (drawn, skipped, or a fallback was scheduled).
/// NO only when the caller should treat the renderer as already abandoned.
- (BOOL)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
