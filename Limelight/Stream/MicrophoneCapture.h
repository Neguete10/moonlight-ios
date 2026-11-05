#import <Foundation/Foundation.h>

// Opt-in microphone passthrough. A missing permission, a missing input
// route, or a host that does not play these packets must not stop the stream.
// tvOS builds keep the same calls and do not open a capture device.
@interface MicrophoneCapture : NSObject

+ (void)startIfEnabled:(BOOL)enabled;
+ (void)stop;

@end
