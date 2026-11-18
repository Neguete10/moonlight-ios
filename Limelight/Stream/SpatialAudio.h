//
//  SpatialAudio.h
//  Moonlight
//
//  Surround playback for headphones and the built-in speakers.
//  The setting is off unless the user turns it on. The normal SDL path
//  is what plays when it is off.
//

#import <Foundation/Foundation.h>
#import <stdint.h>

typedef NS_ENUM(NSInteger, TwilightSpatialLayout) {
    TwilightSpatialLayoutNone = 0,
    TwilightSpatialLayout51 = 6,
    TwilightSpatialLayout71 = 8,
};

typedef NS_ENUM(NSInteger, TwilightSpatialRouteKind) {
    TwilightSpatialRouteHeadphones = 0,
    TwilightSpatialRouteSpeakers = 1,
    TwilightSpatialRouteExternal = 2,
};

NSString *TwilightSpatialAudioEnabledKey(void);
NSString *TwilightSpatialHeadTrackingEnabledKey(void);

BOOL TwilightSpatialAudioEnabled(void);
BOOL TwilightSpatialHeadTrackingEnabled(void);
void TwilightSpatialSetAudioEnabled(BOOL enabled);
void TwilightSpatialSetHeadTrackingEnabled(BOOL enabled);

// 8 when surround should be requested from the host, otherwise 0 so the
// caller keeps its existing channel choice.
int TwilightSpatialSurroundChannelCount(BOOL enabled);

TwilightSpatialLayout TwilightSpatialLayoutForChannelCount(int channelCount);
NSString *TwilightSpatialLayoutName(TwilightSpatialLayout layout);
// 0 when this channel count is not a surround bed the mixer can place.
uint32_t TwilightSpatialChannelLayoutTag(int channelCount);

TwilightSpatialRouteKind TwilightSpatialRouteKindForPort(NSString *portType);
TwilightSpatialRouteKind TwilightSpatialCurrentRouteKind(void);
NSString *TwilightSpatialRouteName(TwilightSpatialRouteKind kind);

NSString *TwilightSpatialStatusLine(BOOL enabled,
                                     BOOL active,
                                     BOOL headTracking,
                                     TwilightSpatialLayout layout,
                                     TwilightSpatialRouteKind route,
                                     BOOL fallback,
                                     BOOL passthrough);

// Interleaved S16. channels is 6 (L R C LFE BL BR) or 8 (plus SL SR).
void TwilightSpatialDownmixToStereo(const int16_t *interleaved,
                                    int frames,
                                    int channels,
                                    int16_t *stereoOut);

// Starts the spatial mixer. Returns NO when the route, the channel count,
// or the audio unit cannot be used. The caller then keeps the normal path.
BOOL TwilightSpatialStart(int sampleRate, int channels, int samplesPerFrame, BOOL headTracking);
void TwilightSpatialStop(void);
BOOL TwilightSpatialIsActive(void);
void TwilightSpatialSubmitS16(const int16_t *interleaved, int frames, int channels);

// Remember a non-spatial result so the stats line can name it.
void TwilightSpatialNotePassthrough(int channels);
void TwilightSpatialNoteDownmix(int channels);

NSString *TwilightSpatialCurrentStatusLine(void);

// Starts a short 5.1 stream on the current route. Used by the simulator
// test. The simulator may not spatialize; a fallback line is a success.
NSString *TwilightSpatialExerciseTestStream(void);
