#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <cmath>
#include <algorithm>
#include <iostream>
#include "keyboard_manager.h"

KeyboardManager::KeyboardManager() = default;

KeyboardManager::~KeyboardManager() {
    if (clientInstance_) {
        // clientInstance_ is an Obj-C object retained via CFRetain
        CFRelease(clientInstance_);
        clientInstance_ = nullptr;
    }
}

bool KeyboardManager::initialize() {
    @autoreleasepool {
        NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreBrightness.framework"];
        if (!bundle || ![bundle load]) {
            std::cerr << "[Error] Failed to load CoreBrightness.framework" << std::endl;
            return false;
        }

        Class clientClass = objc_getClass("KeyboardBrightnessClient");
        if (!clientClass) {
            std::cerr << "[Error] KeyboardBrightnessClient class not found" << std::endl;
            return false;
        }

        id client = [[clientClass alloc] init];
        if (!client) {
            std::cerr << "[Error] Failed to instantiate KeyboardBrightnessClient" << std::endl;
            return false;
        }

        clientInstance_ = (void*)CFRetain((__bridge CFTypeRef)client);
        initialized_ = refreshKeyboardIDs();

        // Cache initial non-zero brightness if available
        float current = getBrightness();
        if (current > 0.001f) {
            lastNonZeroBrightness_ = current;
        }

        return initialized_;
    }
}

bool KeyboardManager::refreshKeyboardIDs() {
    if (!clientInstance_) return false;

    @autoreleasepool {
        id client = (__bridge id)clientInstance_;
        SEL selCopyIDs = @selector(copyKeyboardBacklightIDs);
        if (![client respondsToSelector:selCopyIDs]) {
            std::cerr << "[Error] KeyboardBrightnessClient does not respond to copyKeyboardBacklightIDs" << std::endl;
            return false;
        }

        NSArray *ids = ((NSArray* (*)(id, SEL))objc_msgSend)(client, selCopyIDs);
        keyboardIDs_.clear();

        if (ids) {
            for (id item in ids) {
                if ([item isKindOfClass:[NSNumber class]]) {
                    keyboardIDs_.push_back([item unsignedLongLongValue]);
                }
            }
        }

        if (keyboardIDs_.empty()) {
            std::cerr << "[Warning] No keyboard backlight hardware detected." << std::endl;
            return false;
        }

        return true;
    }
}

float KeyboardManager::getBrightness() {
    if (!clientInstance_) {
        if (!initialize()) return -1.0f;
    }

    if (keyboardIDs_.empty() && !refreshKeyboardIDs()) {
        return -1.0f;
    }

    @autoreleasepool {
        id client = (__bridge id)clientInstance_;
        SEL selBrightness = @selector(brightnessForKeyboard:);

        float (*getBrightnessFn)(id, SEL, unsigned long long) =
            (float (*)(id, SEL, unsigned long long))objc_msgSend;

        uint64_t primaryID = keyboardIDs_.front();
        float val = getBrightnessFn(client, selBrightness, primaryID);
        return std::clamp(val, 0.0f, 1.0f);
    }
}

bool KeyboardManager::setBrightness(float level) {
    if (!clientInstance_) {
        if (!initialize()) return false;
    }

    if (keyboardIDs_.empty() && !refreshKeyboardIDs()) {
        return false;
    }

    level = std::clamp(level, 0.0f, 1.0f);

    @autoreleasepool {
        id client = (__bridge id)clientInstance_;

        SEL selSuspendIdle = @selector(suspendIdleDimming:forKeyboard:);
        SEL selSetBrightnessFull = @selector(setBrightness:fadeSpeed:commit:forKeyboard:);
        SEL selSetBrightnessSimple = @selector(setBrightness:forKeyboard:);

        bool hasFullMethod = [client respondsToSelector:selSetBrightnessFull];
        bool hasSuspendIdle = [client respondsToSelector:selSuspendIdle];

        BOOL (*suspendIdleFn)(id, SEL, BOOL, unsigned long long) =
            (BOOL (*)(id, SEL, BOOL, unsigned long long))objc_msgSend;
        BOOL (*setBrightnessFullFn)(id, SEL, float, int, BOOL, unsigned long long) =
            (BOOL (*)(id, SEL, float, int, BOOL, unsigned long long))objc_msgSend;
        BOOL (*setBrightnessSimpleFn)(id, SEL, float, unsigned long long) =
            (BOOL (*)(id, SEL, float, unsigned long long))objc_msgSend;

        bool success = true;
        for (uint64_t kid : keyboardIDs_) {
            if (level > 0.001f && hasSuspendIdle) {
                // Wake backlight from idle dimming
                suspendIdleFn(client, selSuspendIdle, YES, kid);
            }

            BOOL ret = NO;
            if (hasFullMethod) {
                // Commit immediately with fadeSpeed = 0
                ret = setBrightnessFullFn(client, selSetBrightnessFull, level, 0, YES, kid);
            } else {
                ret = setBrightnessSimpleFn(client, selSetBrightnessSimple, level, kid);
            }

            if (!ret) {
                success = false;
            }
        }

        if (level > 0.001f) {
            lastNonZeroBrightness_ = level;
        }

        return success;
    }
}

float KeyboardManager::increaseBrightness() {
    float current = getBrightness();
    if (current < 0.0f) current = 0.0f;

    int currentChiclets = brightnessToChiclets(current);
    int nextChiclets = std::min(TOTAL_CHICLETS, currentChiclets + 1);

    float nextLevel = chicletsToBrightness(nextChiclets);
    setBrightness(nextLevel);
    return nextLevel;
}

float KeyboardManager::decreaseBrightness() {
    float current = getBrightness();
    if (current < 0.0f) current = 0.0f;

    int currentChiclets = brightnessToChiclets(current);
    int nextChiclets = std::max(0, currentChiclets - 1);

    float nextLevel = chicletsToBrightness(nextChiclets);
    if (nextChiclets == 0) {
        nextLevel = 0.0f;
    }

    setBrightness(nextLevel);
    return nextLevel;
}

float KeyboardManager::toggleBrightness(float fallbackLevel) {
    float current = getBrightness();
    if (current > 0.001f) {
        lastNonZeroBrightness_ = current;
        setBrightness(0.0f);
        return 0.0f;
    } else {
        float target = (lastNonZeroBrightness_ > 0.001f) ? lastNonZeroBrightness_ : fallbackLevel;
        if (target <= 0.001f) target = 0.5f;
        setBrightness(target);
        return target;
    }
}

bool KeyboardManager::isOn() {
    return getBrightness() > 0.001f;
}

int KeyboardManager::brightnessToChiclets(float brightness) {
    if (brightness <= 0.001f) return 0;
    if (brightness >= 0.999f) return TOTAL_CHICLETS;
    return std::clamp(static_cast<int>(std::round(brightness * TOTAL_CHICLETS)), 0, TOTAL_CHICLETS);
}

float KeyboardManager::chicletsToBrightness(int chiclets) {
    if (chiclets <= 0) return 0.0f;
    if (chiclets >= TOTAL_CHICLETS) return 1.0f;
    return static_cast<float>(chiclets) * STEP_SIZE;
}

void KeyboardManager::setLastNonZeroBrightness(float level) {
    if (level > 0.001f) {
        lastNonZeroBrightness_ = std::clamp(level, 0.0f, 1.0f);
    }
}
