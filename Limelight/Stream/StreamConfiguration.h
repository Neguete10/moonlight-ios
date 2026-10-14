//
//  StreamConfiguration.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

// The settings controls accept 0.5 Mb/s through 1 Gbps. There is no Unlimited
// choice. A stored value above 1 Gbps is left alone until the user changes
// it. The value copied into a stream is capped here.
#define TWILIGHT_BITRATE_MAX_KBPS 1000000
#define TWILIGHT_BITRATE_SEND_CAP_KBPS 1500000

@interface StreamConfiguration : NSObject

@property NSString* host;
@property unsigned short httpsPort;
@property NSString* appVersion;
@property NSString* gfeVersion;
@property NSString* appID;
@property NSString* appName;
@property NSString* rtspSessionUrl;
@property int serverCodecModeSupport;
@property int width;
@property int height;
@property int frameRate;
@property int bitRate;
@property int riKeyId;
@property NSData* riKey;
@property int gamepadMask;
@property BOOL optimizeGameSettings;
@property BOOL playAudioOnPC;
@property BOOL swapABXYButtons;
@property int audioConfiguration;
@property int supportedVideoFormats;
@property BOOL multiController;
@property BOOL useFramePacing;
@property NSData* serverCert;

@end
