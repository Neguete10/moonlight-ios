//
//  TwilightInputLog.h
//  Moonlight
//
//  Test seam. Production sends are unchanged. When TWILIGHT_UITEST is set,
//  key events are also appended here so XCUITest can read them back.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TwilightInputLogHandler)(NSString *text);

@interface TwilightInputLog : NSObject

+ (BOOL)isEnabled;
+ (void)reset;
+ (void)setUpdateHandler:(nullable TwilightInputLogHandler)handler;
+ (void)recordKeyCode:(short)keyCode action:(char)action modifiers:(char)modifiers name:(nullable NSString *)name;
+ (NSString *)text;

@end

NS_ASSUME_NONNULL_END
