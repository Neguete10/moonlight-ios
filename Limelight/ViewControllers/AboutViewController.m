//
//  AboutViewController.m
//  Twilight
//

#import "AboutViewController.h"

static NSString * const kSourceRepositoryURL = @"https://github.com/Neguete10/moonlight-ios";

@implementation AboutViewController

+ (void)presentFrom:(UIViewController *)presenter {
    AboutViewController *about = [[AboutViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:about];
#if TARGET_OS_TV
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
#else
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
#endif
    [presenter presentViewController:navigation animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"License";
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }

    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectZero];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.selectable = YES;
    textView.backgroundColor = [UIColor clearColor];
    textView.textColor = [UIColor whiteColor];
#if !TARGET_OS_TV
    textView.editable = NO;
    textView.dataDetectorTypes = UIDataDetectorTypeLink;
#endif
    textView.alwaysBounceVertical = YES;
    textView.textContainerInset = UIEdgeInsetsMake(20, 16, 24, 16);
#if TARGET_OS_TV
    textView.font = [UIFont monospacedSystemFontOfSize:24 weight:UIFontWeightRegular];
#else
    textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
#endif
    textView.text = [self licenseText];
    [self.view addSubview:textView];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [textView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [textView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    ]];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                            target:self
                                                                                            action:@selector(dismissAbout)];
}

- (NSString *)licenseText {
    NSString *intro = [NSString stringWithFormat:
                       @"Twilight is free software under the GNU General Public License, version 3.\n\n"
                       @"The App Store Distribution Exception at the end of this license is additional permission under section 7. It allows distribution through an app store when the source is also available under the GPL, with or without that permission, through a channel that does not carry the store's terms.\n\n"
                       @"Source code: %@\n\n"
                       @"----- \n\n",
                       kSourceRepositoryURL];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"LICENSE" ofType:@"txt"];
    NSString *license = nil;
    if (path != nil) {
        license = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    }
    if (license.length == 0) {
        license = @"The license text is missing from this copy of the app.";
    }
    return [intro stringByAppendingString:license];
}

- (void)dismissAbout {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
