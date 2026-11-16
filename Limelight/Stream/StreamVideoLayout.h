//
//  StreamVideoLayout.h
//  Moonlight
//
//  Aspect-fit frame for the stream picture, in the view's current bounds.
//  The iPhone app is landscape-only. Callers that still see a portrait size
//  (storyboard frame, or UIWindow.frame in screen coordinates) pass that size
//  through interfaceSizeForSize:landscapeOnly: before laying out.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface StreamVideoLayout : NSObject

/// Aspect-fit rect centered in bounds. aspectRatio is stream width / height.
/// A non-positive ratio, or empty bounds, returns CGRectZero.
+ (CGRect)videoRectForBounds:(CGRect)bounds streamAspectRatio:(CGFloat)aspectRatio;

/// Point size in interface orientation. A landscape-only phone whose bounds
/// are still portrait (width < height) is swapped so the long side is width.
+ (CGSize)interfaceSizeForSize:(CGSize)size landscapeOnly:(BOOL)landscapeOnly;

/// Safe-area insets that match interfaceSizeForSize:landscapeOnly:.
/// When that method swaps a portrait size, top/bottom become left/right.
+ (UIEdgeInsets)interfaceInsets:(UIEdgeInsets)insets forSize:(CGSize)size landscapeOnly:(BOOL)landscapeOnly;

/// Pixel size for the Full (fullBleed) and Safe Area presets.
/// Safe Area keeps the full interface height and trims the horizontal insets,
/// which is what the resolution picker has always stored.
+ (CGSize)streamPixelsForSize:(CGSize)size
                        insets:(UIEdgeInsets)insets
                         scale:(CGFloat)scale
                 landscapeOnly:(BOOL)landscapeOnly
                     fullBleed:(BOOL)fullBleed;

/// Dimensions requested from the host. On a landscape-only phone a stored
/// portrait pair is swapped so the picture is wider than it is tall.
+ (CGSize)streamSizeForWidth:(NSInteger)width height:(NSInteger)height landscapeOnly:(BOOL)landscapeOnly;

@end

NS_ASSUME_NONNULL_END
