//
//  TwilightInputLog.m
//  Moonlight
//

#import "TwilightInputLog.h"

@implementation TwilightInputLog {
}

static NSString *logText;
static TwilightInputLogHandler logHandler;
static BOOL logEnabledKnown;
static BOOL logEnabled;

+ (BOOL)isEnabled {
    if (!logEnabledKnown) {
        logEnabledKnown = YES;
        const char *mode = getenv("TWILIGHT_UITEST");
        logEnabled = mode != NULL && mode[0] != '\0';
    }
    return logEnabled;
}

+ (void)reset {
    logText = @"";
    if (logHandler != nil) {
        logHandler(logText);
    }
}

+ (void)setUpdateHandler:(TwilightInputLogHandler)handler {
    logHandler = [handler copy];
}

+ (void)recordKeyCode:(short)keyCode action:(char)action modifiers:(char)modifiers name:(NSString *)name {
    if (![self isEnabled]) {
        return;
    }
    // KEY_ACTION_DOWN is 0x03 and KEY_ACTION_UP is 0x04 in Limelight.h.
    NSString *verb = action == 0x03 ? @"down" : @"up";
    NSString *line = [NSString stringWithFormat:@"%@ %d %d %@\n", verb, (int)keyCode, (int)modifiers, name ?: @""];
    void (^apply)(void) = ^{
        if (logText == nil) {
            logText = @"";
        }
        logText = [logText stringByAppendingString:line];
        if (logHandler != nil) {
            logHandler(logText);
        }
    };
    if ([NSThread isMainThread]) {
        apply();
    }
    else {
        dispatch_async(dispatch_get_main_queue(), apply);
    }
}

+ (NSString *)text {
    return logText ?: @"";
}

@end
