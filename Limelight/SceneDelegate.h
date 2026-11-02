//
//  SceneDelegate.h
//  Moonlight
//
//  iOS and iPadOS scene lifecycle. tvOS keeps UIMainStoryboardFile and does
//  not compile this class.
//

#import <UIKit/UIKit.h>

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic) UIWindow *window;

@end
