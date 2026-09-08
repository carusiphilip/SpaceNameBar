#import "WindowSpaceBridge.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>

static void *skyLight(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
    });
    return handle;
}

uint32_t SNBWindowID(AXUIElementRef window) {
    typedef AXError (*GetWindow)(AXUIElementRef, uint32_t *);
    GetWindow get = (GetWindow)dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
    uint32_t value = 0;
    if (get && get(window, &value) == kAXErrorSuccess) return value;
    return 0;
}

CFArrayRef SNBCopyWindowSpaces(uint32_t windowID) {
    void *handle = skyLight();
    if (!handle) return NULL;
    int32_t (*connection)(void) = dlsym(handle, "CGSMainConnectionID");
    CFArrayRef (*copy)(int32_t, int32_t, CFArrayRef) = dlsym(handle, "CGSCopySpacesForWindows");
    if (!connection || !copy) return NULL;
    return copy(connection(), 7, (__bridge CFArrayRef)@[@(windowID)]);
}

bool SNBCanMoveWindows(void) {
    void *handle = skyLight();
    Class cls = handle ? NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation") : Nil;
    return cls && [cls instancesRespondToSelector:sel_registerName("initWithWindows:spaceID:")] &&
        [cls instancesRespondToSelector:sel_registerName("performWithWMBridgeDelegate")];
}

bool SNBMoveWindow(uint32_t windowID, uint64_t spaceID) {
    if (!SNBCanMoveWindows() || !windowID || !spaceID) return false;
    @try {
        Class cls = NSClassFromString(@"SLSBridgedMoveWindowsToManagedSpaceOperation");
        SEL selector = sel_registerName("initWithWindows:spaceID:");
        if (![cls instancesRespondToSelector:selector]) return false;
        id operation = ((id (*)(id, SEL, id, uint64_t))objc_msgSend)([cls alloc], selector, @[@(windowID)], spaceID);
        if (!operation) return false;
        ((void (*)(id, SEL))objc_msgSend)(operation, sel_registerName("performWithWMBridgeDelegate"));
        return true;
    } @catch (NSException *exception) {
        return false;
    }
}
