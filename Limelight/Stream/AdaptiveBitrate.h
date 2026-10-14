#import <Foundation/Foundation.h>

// Opt-in client-side adaptive bitrate. The worker is idle until a paired
// host's api/abr/capabilities body contains "runtime_bitrate". A missing
// endpoint leaves the launch bitrate alone.
@interface AdaptiveBitrateWorker : NSThread

- (instancetype)initWithHost:(NSString *)host
                   httpsPort:(unsigned short)httpsPort
                  serverCert:(NSData *)serverCert
           requestedWireKbps:(int)requestedWireKbps
           audioChannelCount:(int)audioChannelCount
                         lan:(BOOL)lan;

- (void)requestStop;

@end

// The stats overlay reads this. Zero hides the adaptive figure.
void TwilightSetPoorConnection(BOOL poor);
void TwilightResetPoorConnection(void);
int TwilightAdaptiveOverlayKbps(void);
