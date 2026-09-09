
#import "XCTestCapabilityProbe.h"

#import <dlfcn.h>
#import <mach/mach.h>
#import <mach/task_special_ports.h>
#import <objc/runtime.h>

@implementation XCTestCapabilityProbe

+ (NSDictionary<NSString *, id> *)probeFrameworkAtPaths:(NSArray<NSString *> *)paths {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];

    BOOL fileExists = NO;
    BOOL loaded = NO;
    NSString *loadedPath = @"";
    NSString *lastError = @"";

    for (NSString *path in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            fileExists = YES;
        }

        dlerror();
        void *handle = dlopen(path.UTF8String, RTLD_NOW | RTLD_LOCAL);

        if (handle) {
            loaded = YES;
            loadedPath = path;
            break;
        }

        const char *err = dlerror();
        if (err) {
            lastError = [NSString stringWithUTF8String:err] ?: @"";
        }
    }

    out[@"fileExistsAtAnyKnownPath"] = @(fileExists);
    out[@"dlopenSuccess"] = @(loaded);
    out[@"loadedPath"] = loadedPath;
    out[@"lastDlopenError"] = lastError;

    return out;
}

+ (NSDictionary<NSString *, id> *)probeClass:(NSString *)name
                                    selectors:(NSArray<NSString *> *)selectors {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];

    Class cls = NSClassFromString(name);
    out[@"present"] = @(cls != Nil);

    if (!cls) {
        return out;
    }

    NSMutableDictionary *selectorResults = [NSMutableDictionary dictionary];

    for (NSString *selectorName in selectors) {
        SEL sel = NSSelectorFromString(selectorName);

        BOOL classResponds = [cls respondsToSelector:sel];

        BOOL instancesRespond = NO;
        if (class_getInstanceMethod(cls, sel) != NULL) {
            instancesRespond = YES;
        }

        selectorResults[selectorName] = @{
            @"classResponds": @(classResponds),
            @"instanceMethodExists": @(instancesRespond)
        };
    }

    out[@"selectors"] = selectorResults;
    return out;
}

+ (NSDictionary<NSString *, id> *)probeMachService:(NSString *)serviceName {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];

    typedef kern_return_t (*bootstrap_look_up_fn)(
        mach_port_t bootstrap_port,
        const char *service_name,
        mach_port_t *service_port
    );

    bootstrap_look_up_fn fn =
        (bootstrap_look_up_fn)dlsym(RTLD_DEFAULT, "bootstrap_look_up");

    if (!fn) {
        out[@"symbolAvailable"] = @NO;
        out[@"success"] = @NO;
        out[@"returnCode"] = @(-9999);
        out[@"description"] = @"bootstrap_look_up symbol unavailable";
        return out;
    }

    out[@"symbolAvailable"] = @YES;

    mach_port_t bootstrap = MACH_PORT_NULL;
    kern_return_t kr = task_get_bootstrap_port(
        mach_task_self(),
        &bootstrap
    );

    if (kr != KERN_SUCCESS || bootstrap == MACH_PORT_NULL) {
        out[@"success"] = @NO;
        out[@"returnCode"] = @(kr);
        out[@"description"] =
            [NSString stringWithFormat:
                @"Could not get TASK_BOOTSTRAP_PORT: %d",
                kr];
        return out;
    }

    mach_port_t servicePort = MACH_PORT_NULL;

    kern_return_t lookup = fn(
        bootstrap,
        serviceName.UTF8String,
        &servicePort
    );

    BOOL success =
        (lookup == KERN_SUCCESS &&
         servicePort != MACH_PORT_NULL);

    out[@"success"] = @(success);
    out[@"returnCode"] = @(lookup);

    out[@"description"] =
        success
        ? @"lookup succeeded"
        : [NSString stringWithFormat:
            @"lookup failed (kern_return_t=%d)",
            (int)lookup];

    if (success) {
        mach_port_deallocate(
            mach_task_self(),
            servicePort
        );
    }

    return out;
}

+ (NSDictionary<NSString *, id> *)runProbe {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    result[@"timestamp"] =
        @([[NSDate date] timeIntervalSince1970]);

    result[@"process"] = @{
        @"bundleIdentifier":
            [[NSBundle mainBundle] bundleIdentifier] ?: @"",
        @"processName":
            [[NSProcessInfo processInfo] processName] ?: @"",
        @"homeDirectory":
            NSHomeDirectory() ?: @""
    };

    // XCTest location varies by iOS / Developer Disk Image generation.
    result[@"XCTestFramework"] =
        [self probeFrameworkAtPaths:@[
            @"/System/Developer/Library/Frameworks/XCTest.framework/XCTest",
            @"/System/Library/Frameworks/XCTest.framework/XCTest"
        ]];

    result[@"XCTestCore"] =
        [self probeFrameworkAtPaths:@[
            @"/System/Developer/Library/PrivateFrameworks/XCTestCore.framework/XCTestCore",
            @"/System/Library/PrivateFrameworks/XCTestCore.framework/XCTestCore"
        ]];

    result[@"XCTAutomationSupport"] =
        [self probeFrameworkAtPaths:@[
            @"/System/Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework/XCTAutomationSupport",
            @"/System/Library/PrivateFrameworks/XCTAutomationSupport.framework/XCTAutomationSupport"
        ]];

    result[@"XCTTargetBootstrap"] =
        [self probeFrameworkAtPaths:@[
            @"/System/Developer/Library/PrivateFrameworks/XCTTargetBootstrap.framework/XCTTargetBootstrap",
            @"/System/Library/PrivateFrameworks/XCTTargetBootstrap.framework/XCTTargetBootstrap"
        ]];

    // Merely inspect Objective-C runtime. We intentionally do NOT instantiate
    // or call XCTestDriver/XCUIApplication in this stage.
    result[@"classes"] = @{
        @"XCTestCase":
            [self probeClass:@"XCTestCase"
                   selectors:@[@"setUp", @"tearDown"]],
        @"XCTestDriver":
            [self probeClass:@"XCTestDriver"
                   selectors:@[@"sharedTestDriver"]],
        @"XCTestConfiguration":
            [self probeClass:@"XCTestConfiguration"
                   selectors:@[]],
        @"XCUIApplication":
            [self probeClass:@"XCUIApplication"
                   selectors:@[@"launch", @"activate", @"terminate"]],
        @"XCUIDevice":
            [self probeClass:@"XCUIDevice"
                   selectors:@[@"sharedDevice"]],
        @"XCTRunnerDaemonSession":
            [self probeClass:@"XCTRunnerDaemonSession"
                   selectors:@[]]
    };

    // Probe likely service names only. No messages are sent to the service.
    result[@"machServices"] = @{
        @"com.apple.testmanagerd":
            [self probeMachService:@"com.apple.testmanagerd"],
        @"com.apple.testmanagerd.control":
            [self probeMachService:@"com.apple.testmanagerd.control"],
        @"com.apple.testmanagerd.runner":
            [self probeMachService:@"com.apple.testmanagerd.runner"],
        @"com.apple.dt.testmanagerd.remote":
            [self probeMachService:@"com.apple.dt.testmanagerd.remote"]
    };

    return result;
}

@end
