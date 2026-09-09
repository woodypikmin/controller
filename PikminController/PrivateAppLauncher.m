
#import "PrivateAppLauncher.h"
#import <dlfcn.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)applicationIsInstalled:(NSString *)bundleIdentifier;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleIdentifier;
- (void)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier
                              configuration:(id)configuration
                          completionHandler:(void (^)(id result))completionHandler;
@end

@implementation PrivateAppLauncher

+ (id)workspace {
    // Try to make sure LaunchServices/CoreServices classes are loaded.
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices",
           RTLD_LAZY | RTLD_LOCAL);

    dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
           RTLD_LAZY | RTLD_LOCAL);

    Class cls = NSClassFromString(@"LSApplicationWorkspace");

    if (!cls) {
        return nil;
    }

    SEL selector = NSSelectorFromString(@"defaultWorkspace");

    if (![cls respondsToSelector:selector]) {
        return nil;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id workspace = [cls performSelector:selector];
#pragma clang diagnostic pop

    return workspace;
}

+ (BOOL)isApplicationInstalled:(NSString *)bundleIdentifier
                         known:(BOOL *)known {
    id workspace = [self workspace];

    if (!workspace) {
        if (known) {
            *known = NO;
        }
        return NO;
    }

    SEL selector = NSSelectorFromString(@"applicationIsInstalled:");

    if (![workspace respondsToSelector:selector]) {
        if (known) {
            *known = NO;
        }
        return NO;
    }

    if (known) {
        *known = YES;
    }

    // Declare the private method above so ARC generates a normal objc_msgSend
    // call with the correct primitive BOOL return ABI.
    return [(LSApplicationWorkspace *)workspace
            applicationIsInstalled:bundleIdentifier];
}

+ (BOOL)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier {
    id workspace = [self workspace];

    if (!workspace) {
        return NO;
    }

    SEL legacy = NSSelectorFromString(@"openApplicationWithBundleID:");

    if ([workspace respondsToSelector:legacy]) {
        return [(LSApplicationWorkspace *)workspace
                openApplicationWithBundleID:bundleIdentifier];
    }

    SEL newer =
        NSSelectorFromString(
            @"openApplicationWithBundleIdentifier:configuration:completionHandler:"
        );

    if ([workspace respondsToSelector:newer]) {
        [(LSApplicationWorkspace *)workspace
            openApplicationWithBundleIdentifier:bundleIdentifier
                                  configuration:nil
                              completionHandler:^(id result) {
                                  (void)result;
                              }];

        // This newer API reports asynchronously. Reaching here means the
        // selector existed and the request was submitted.
        return YES;
    }

    return NO;
}

@end
