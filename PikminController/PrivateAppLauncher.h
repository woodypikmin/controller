
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PrivateAppLauncher : NSObject

+ (BOOL)isApplicationInstalled:(NSString *)bundleIdentifier
                         known:(BOOL *)known;

+ (BOOL)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier;

@end

NS_ASSUME_NONNULL_END
