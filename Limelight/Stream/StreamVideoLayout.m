//
//  StreamVideoLayout.m
//  Moonlight
//

#import "StreamVideoLayout.h"

@implementation StreamVideoLayout

+ (CGRect)videoRectForBounds:(CGRect)bounds streamAspectRatio:(CGFloat)aspectRatio {
    if (aspectRatio <= 0.01f || bounds.size.width < 1.0f || bounds.size.height < 1.0f) {
        return CGRectZero;
    }

    // Same aspect-fit the decoder used to apply once, from whatever bounds
    // happened to be current. Width wins when the view is wider than the stream.
    CGSize videoSize;
    if (bounds.size.width > bounds.size.height * aspectRatio) {
        videoSize = CGSizeMake(bounds.size.height * aspectRatio, bounds.size.height);
    }
    else {
        videoSize = CGSizeMake(bounds.size.width, bounds.size.width / aspectRatio);
    }
    CGPoint origin = CGPointMake((bounds.size.width - videoSize.width) / 2.0,
                                  (bounds.size.height - videoSize.height) / 2.0);
    return CGRectMake(origin.x, origin.y, videoSize.width, videoSize.height);
}

+ (BOOL)sizeIsPortrait:(CGSize)size {
    return size.width > 0.5 && size.height > size.width;
}

+ (CGSize)interfaceSizeForSize:(CGSize)size landscapeOnly:(BOOL)landscapeOnly {
    if (landscapeOnly && [self sizeIsPortrait:size]) {
        return CGSizeMake(size.height, size.width);
    }
    return size;
}

+ (UIEdgeInsets)interfaceInsets:(UIEdgeInsets)insets forSize:(CGSize)size landscapeOnly:(BOOL)landscapeOnly {
    if (landscapeOnly && [self sizeIsPortrait:size]) {
        // A 90-degree turn: the portrait top inset is one landscape side.
        return UIEdgeInsetsMake(insets.left, insets.top, insets.right, insets.bottom);
    }
    return insets;
}

+ (CGSize)streamPixelsForSize:(CGSize)size
                        insets:(UIEdgeInsets)insets
                         scale:(CGFloat)scale
                 landscapeOnly:(BOOL)landscapeOnly
                     fullBleed:(BOOL)fullBleed {
    if (scale < 0.1) {
        scale = 1.0;
    }
    CGSize interfaceSize = [self interfaceSizeForSize:size landscapeOnly:landscapeOnly];
    UIEdgeInsets interfaceInsets = [self interfaceInsets:insets forSize:size landscapeOnly:landscapeOnly];
    CGFloat width = interfaceSize.width;
    if (!fullBleed) {
        width -= interfaceInsets.left + interfaceInsets.right;
    }
    if (width < 1.0) {
        width = interfaceSize.width;
    }
    return CGSizeMake(width * scale, interfaceSize.height * scale);
}

+ (CGSize)streamSizeForWidth:(NSInteger)width height:(NSInteger)height landscapeOnly:(BOOL)landscapeOnly {
    if (landscapeOnly && height > width && width > 0) {
        return CGSizeMake(height, width);
    }
    return CGSizeMake(MAX(width, 0), MAX(height, 0));
}

@end
