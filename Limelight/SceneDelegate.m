//
//  SceneDelegate.m
//  Moonlight
//
//  iOS 27 traps in UIApplicationMain when an iOS app still launches through
//  UIMainStoryboardFile and never adopts UIScene. This delegate creates the
//  one window for that scene.
//

#import "SceneDelegate.h"
#import "AppDelegate.h"
#import "MainFrameViewController.h"
#import "SWRevealViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    if (self.window == nil) {
        NSString *storyboardName = [self storyboardNameForWindowScene:windowScene];
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:storyboardName bundle:nil];
        UIViewController *root = [storyboard instantiateInitialViewController];
        if (root == nil) {
            Log(LOG_E, @"Storyboard %@ has no initial view controller", storyboardName);
            return;
        }

        UIWindow *window = [[UIWindow alloc] initWithWindowScene:windowScene];
        // Publish before the root view loads so viewDidLoad can read AppDelegate.window.
        self.window = window;
        [self publishWindow];
        window.rootViewController = root;
        [window makeKeyAndVisible];
        Log(LOG_I, @"Opened %@ storyboard for idiom %ld", storyboardName, (long)windowScene.traitCollection.userInterfaceIdiom);
    }
    else {
        [self publishWindow];
    }

    // Cold start delivers the shortcut here. A warm start uses the method below.
    [self acceptShortcutItem:connectionOptions.shortcutItem completion:nil];
}

- (void)windowScene:(UIWindowScene *)windowScene performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {
    [self acceptShortcutItem:shortcutItem completion:completionHandler];
    MainFrameViewController *mainFrame = [self mainFrameInController:self.window.rootViewController];
    if (mainFrame != nil && mainFrame.isViewLoaded && mainFrame.view.window != nil) {
        [mainFrame handlePendingShortcutAction];
    }
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    [(AppDelegate *)UIApplication.sharedApplication.delegate saveContext];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    [(AppDelegate *)UIApplication.sharedApplication.delegate saveContext];
}

- (NSString *)storyboardNameForWindowScene:(UIWindowScene *)windowScene {
    // visionOS Designed for iPad runs this binary. The idiom is Pad, and on
    // newer systems it can also report Vision. Both use the iPad storyboard.
    // A phone stays on iPhone.storyboard. One UISceneStoryboardFile cannot
    // express that, so the storyboard is chosen here instead of in the manifest.
    UIUserInterfaceIdiom idiom = windowScene.traitCollection.userInterfaceIdiom;
    if (idiom == UIUserInterfaceIdiomUnspecified) {
        idiom = UIDevice.currentDevice.userInterfaceIdiom;
    }
    if (idiom == UIUserInterfaceIdiomPad) {
        return @"iPad";
    }
    if (@available(iOS 17.0, *)) {
        if (idiom == UIUserInterfaceIdiomVision) {
            return @"iPad";
        }
    }
    return @"iPhone";
}

- (void)publishWindow {
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    appDelegate.window = self.window;
}

- (void)acceptShortcutItem:(UIApplicationShortcutItem *)shortcutItem completion:(void (^)(BOOL))completion {
    if (shortcutItem == nil) {
        return;
    }
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    appDelegate.pcUuidToLoad = [shortcutItem.userInfo objectForKey:@"UUID"];
    appDelegate.shortcutCompletionHandler = completion;
}

- (MainFrameViewController *)mainFrameInController:(UIViewController *)controller {
    if (controller == nil) {
        return nil;
    }
    if ([controller isKindOfClass:[MainFrameViewController class]]) {
        return (MainFrameViewController *)controller;
    }
    if ([controller isKindOfClass:[UINavigationController class]]) {
        for (UIViewController *child in ((UINavigationController *)controller).viewControllers) {
            MainFrameViewController *found = [self mainFrameInController:child];
            if (found != nil) {
                return found;
            }
        }
    }
    if ([controller isKindOfClass:[SWRevealViewController class]]) {
        return [self mainFrameInController:((SWRevealViewController *)controller).frontViewController];
    }
    for (UIViewController *child in controller.childViewControllers) {
        MainFrameViewController *found = [self mainFrameInController:child];
        if (found != nil) {
            return found;
        }
    }
    return nil;
}

@end
