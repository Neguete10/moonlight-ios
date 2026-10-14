//
//  HttpManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/16/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "HttpResponse.h"
#import "HttpRequest.h"
#import "StreamConfiguration.h"
#import "TemporaryHost.h"

@interface HttpManager : NSObject <NSURLSessionDelegate>

- (id) initWithHost:(TemporaryHost*) host;
- (id) initWithAddress:(NSString*) hostAddressPortString httpsPort:(unsigned short) httpsPort serverCert:(NSData*) serverCert;
- (void) setServerCert:(NSData*) serverCert;
- (NSURLRequest*) newPairRequest:(NSData*)salt clientCert:(NSData*)clientCert;
- (NSURLRequest*) newUnpairRequest;
- (NSURLRequest*) newChallengeRequest:(NSData*)challenge;
- (NSURLRequest*) newChallengeRespRequest:(NSData*)challengeResp;
- (NSURLRequest*) newClientSecretRespRequest:(NSString*)clientPairSecret;
- (NSURLRequest*) newPairChallenge;
- (NSURLRequest*) newAppListRequest;
- (NSURLRequest*) newServerInfoRequest:(bool)fastFail;
- (NSURLRequest*) newHttpServerInfoRequest:(bool)fastFail;
- (NSURLRequest*) newHttpServerInfoRequest;
- (NSURLRequest*) newLaunchOrResumeRequest:(NSString*)verb config:(StreamConfiguration*)config;
- (NSURLRequest*) newQuitAppRequest;
- (NSURLRequest*) newAppAssetRequestWithAppId:(NSString*)appId;
- (void) executeRequestSynchronously:(HttpRequest*)request;

// Paired HTTPS. Returns NO when the request fails. *runtimeBitrate is YES
// only when the body contains "runtime_bitrate".
- (BOOL) requestAbrRuntimeBitrate:(BOOL *)runtimeBitrate;

// Sets the encoder bitrate. The host cap for this call is 500000 kbps.
// Returns NO when the host rejects the request. Does not stop the stream.
- (BOOL) requestSetEncoderBitrateKbps:(int)kbps appliedKbps:(int *)applied;

@end


