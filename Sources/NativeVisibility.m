#import "NativeVisibility.h"
#import <dlfcn.h>
#import <objc/message.h>

// Adapted from Hidden Bar's native visibility bridge.
// Copyright (c) 2026 Dwarves Foundation. MIT license, see THIRD_PARTY_NOTICES.md.

// macOS 27's menu-bar-only visibility restriction. Resolve at runtime because
// these private interfaces may change independently of the public SDK.
BOOL MFNativeVisibilityAvailable(void) {
    static void *framework;
    if (!framework) {
        framework = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_LAZY | RTLD_LOCAL);
    }
    Class config = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
    return framework && config && assertion
        && [config instancesRespondToSelector:NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:")]
        && [assertion instancesRespondToSelector:NSSelectorFromString(@"activateWithConfiguration:completionHandler:")]
        && [assertion instancesRespondToSelector:NSSelectorFromString(@"invalidate")];
}

void MFActivateVisibility(NSArray<NSString *> *allowedBundles, void (^completion)(id, NSError *)) {
    void (^finish)(id, NSError *) = ^(id handle, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(handle, error); });
    };
    @try {
        if (!MFNativeVisibilityAvailable()) {
            finish(nil, [NSError errorWithDomain:@"MenuFold" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"当前系统的菜单栏收纳接口不可用。"}]);
            return;
        }
        NSMutableArray *systemItems = [NSMutableArray array];
        for (NSInteger index = 0; index < 64; index++) { [systemItems addObject:@(index)]; }
        id configuration = ((id (*)(id, SEL, id, id))objc_msgSend)(
            [NSClassFromString(@"MBAssessmentModeConfiguration") alloc],
            NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:"),
            systemItems, allowedBundles);
        id handle = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(handle,
            NSSelectorFromString(@"activateWithConfiguration:completionHandler:"),
            configuration, ^(NSError *error) { finish(error ? nil : handle, error); });
    } @catch (NSException *exception) {
        finish(nil, [NSError errorWithDomain:@"MenuFold" code:2
            userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"菜单栏接口调用失败。"}]);
    }
}

void MFReleaseVisibility(id assertion) {
    if (!assertion) { return; }
    @try {
        ((void (*)(id, SEL))objc_msgSend)(assertion, NSSelectorFromString(@"invalidate"));
    } @catch (NSException *exception) {
        NSLog(@"MenuFold visibility release failed: %@", exception.reason);
    }
}
