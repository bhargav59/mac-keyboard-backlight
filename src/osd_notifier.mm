#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <cmath>
#include <algorithm>
#include <iostream>
#include "osd_notifier.h"

OSDNotifier::OSDNotifier() = default;

OSDNotifier::~OSDNotifier() {
    if (osdManager_) {
        // Manager is a shared singleton, no need to release
        osdManager_ = nullptr;
    }
}

bool OSDNotifier::initialize() {
    @autoreleasepool {
        void* handle = dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_LAZY);
        if (!handle) {
            std::cerr << "[Warning] OSD.framework not available on this system." << std::endl;
            return false;
        }

        Class osdManagerClass = NSClassFromString(@"OSDManager");
        if (!osdManagerClass) {
            std::cerr << "[Warning] OSDManager class not found." << std::endl;
            return false;
        }

        SEL selShared = @selector(sharedManager);
        id manager = ((id (*)(id, SEL))objc_msgSend)(osdManagerClass, selShared);
        if (!manager) {
            std::cerr << "[Warning] Failed to obtain OSDManager instance." << std::endl;
            return false;
        }

        osdManager_ = (__bridge void*)manager;
        initialized_ = true;
        return true;
    }
}

void OSDNotifier::show(int filledChiclets, int totalChiclets) {
    if (!enabled_) return;

    if (!initialized_) {
        if (!initialize()) return;
    }

    @autoreleasepool {
        id manager = (__bridge id)osdManager_;
        SEL selShow = @selector(showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:);
        if (![manager respondsToSelector:selShow]) {
            return;
        }

        // Image type 2 corresponds to Keyboard Backlight in macOS OSD.framework
        const long long kOSDGraphicKeyboardBacklight = 2;
        CGDirectDisplayID displayID = CGMainDisplayID();
        const unsigned int priority = 1;
        const unsigned int msecFade = 1000;
        filledChiclets = std::clamp(filledChiclets, 0, totalChiclets);

        void (*showFn)(id, SEL, long long, unsigned int, unsigned int, unsigned int, unsigned int, unsigned int, BOOL) =
            (void (*)(id, SEL, long long, unsigned int, unsigned int, unsigned int, unsigned int, unsigned int, BOOL))objc_msgSend;

        showFn(manager, selShow,
               kOSDGraphicKeyboardBacklight,
               displayID,
               priority,
               msecFade,
               static_cast<unsigned int>(filledChiclets),
               static_cast<unsigned int>(totalChiclets),
               NO);
    }
}

void OSDNotifier::showBrightness(float brightness) {
    int chiclets = std::clamp(static_cast<int>(std::round(brightness * 16.0f)), 0, 16);
    show(chiclets, 16);
}
