#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#include <iostream>
#include <fstream>
#include <cstdlib>
#include "hotkey_manager.h"

static void WriteDaemonTapState(bool active) {
    std::ofstream out("/tmp/keyboardbacklight.state");
    if (out.is_open()) {
        out << (active ? "event_tap=active\n" : "event_tap=inactive\n");
    }
}

// Forward declaration of C-callbacks
static OSStatus CarbonHotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData);
static CGEventRef EventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);
static void AccessibilityCheckTimerCallback(CFRunLoopTimerRef timer, void *info);

static HotkeyManager* g_currentInstance = nullptr;

HotkeyManager::HotkeyManager()
    : lastActionTime_(std::chrono::steady_clock::now() - std::chrono::milliseconds(1000)) {
    g_currentInstance = this;
}

HotkeyManager::~HotkeyManager() {
    stop();
    if (g_currentInstance == this) {
        g_currentInstance = nullptr;
    }
}

bool HotkeyManager::isAccessibilityGranted() {
    return AXIsProcessTrusted();
}

void HotkeyManager::promptAccessibilityPermission() {
    @autoreleasepool {
        NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    }
}

void HotkeyManager::runAccessibilityPromptLoop() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        promptAccessibilityPermission();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [NSApp stop:nil];
            NSEvent* event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                                location:NSMakePoint(0,0)
                                           modifierFlags:0
                                               timestamp:0
                                            windowNumber:0
                                                 context:nil
                                                 subtype:0
                                                   data1:0
                                                   data2:0];
            [NSApp postEvent:event atStart:YES];
        });
        [NSApp run];
    }
}

void HotkeyManager::openAccessibilitySettings() {
    std::system("open \"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility\"");
}

void HotkeyManager::triggerAction(HotkeyAction action) {
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - lastActionTime_).count();
    if (elapsed < DEBOUNCE_MS) {
        // Debounce duplicate invocations from dual interceptors
        return;
    }
    lastActionTime_ = now;

    if (callback_) {
        callback_(action);
    }
}

static OSStatus CarbonHotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData) {
    (void)nextHandler;
    HotkeyManager* manager = static_cast<HotkeyManager*>(userData);
    if (!manager) return noErr;

    EventHotKeyID hkId;
    OSStatus status = GetEventParameter(theEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hkId), NULL, &hkId);
    if (status != noErr) return noErr;

    if (hkId.id == 1 || hkId.id == 4) {
        manager->triggerAction(HotkeyAction::BRIGHTNESS_DOWN);
    } else if (hkId.id == 2 || hkId.id == 5) {
        manager->triggerAction(HotkeyAction::BRIGHTNESS_UP);
    } else if (hkId.id == 3) {
        manager->triggerAction(HotkeyAction::BRIGHTNESS_TOGGLE);
    }

    return noErr;
}

static CGEventRef EventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    (void)proxy;
    HotkeyManager* manager = static_cast<HotkeyManager*>(refcon);
    if (!manager) return event;

    // Handle tap timeouts / disablements
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (manager && manager->getEventTap()) {
            CGEventTapEnable((CFMachPortRef)manager->getEventTap(), true);
        }
        return event;
    }

    CGEventFlags flags = CGEventGetFlags(event);
    CGEventFlags liveFlags = CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState);
    bool cmdPressed = ((flags & kCGEventFlagMaskCommand) != 0) ||
                      ((liveFlags & kCGEventFlagMaskCommand) != 0);
    bool shiftPressed = ((flags & kCGEventFlagMaskShift) != 0) ||
                        ((liveFlags & kCGEventFlagMaskShift) != 0);

    // Check SystemDefined (Media key) events
    if (type == 14) { // NSSystemDefined / NX_SYSDEFINED
        @autoreleasepool {
            NSEvent *nsEvent = [NSEvent eventWithCGEvent:event];
            if (nsEvent && [nsEvent type] == NSEventTypeSystemDefined && [nsEvent subtype] == 8) {
                int data1 = [nsEvent data1];
                int keyCode = (data1 & 0xFFFF0000) >> 16;
                int keyFlags = (data1 & 0x0000FFFF);
                bool isDown = (((keyFlags & 0xFF00) >> 8) == 0xA);
                bool isRepeat = (keyFlags & 0x1) != 0;
                bool isCmd = cmdPressed || (([nsEvent modifierFlags] & NSEventModifierFlagCommand) != 0);
                bool isShift = shiftPressed || (([nsEvent modifierFlags] & NSEventModifierFlagShift) != 0);

                // NX_KEYTYPE_BRIGHTNESS_DOWN = 3, NX_KEYTYPE_BRIGHTNESS_UP = 2
                // NX_KEYTYPE_ILLUMINATION_DOWN = 22, NX_KEYTYPE_ILLUMINATION_UP = 21
                if (isCmd && (isDown || isRepeat)) {
                    if (keyCode == 3 || keyCode == 22) { // Screen Brightness Down or Illumination Down
                        if (isShift) {
                            manager->triggerAction(HotkeyAction::BRIGHTNESS_TOGGLE);
                        } else {
                            manager->triggerAction(HotkeyAction::BRIGHTNESS_DOWN);
                        }
                        return NULL; // Swallow event so screen brightness is untouched
                    } else if (keyCode == 2 || keyCode == 21) { // Screen Brightness Up or Illumination Up
                        manager->triggerAction(HotkeyAction::BRIGHTNESS_UP);
                        return NULL; // Swallow event so screen brightness is untouched
                    }
                }
            }
        }
    }

    // Check standard KeyDown events (when F1/F2 or F5/F6 are pressed)
    if (type == kCGEventKeyDown) {
        if (cmdPressed) {
            int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
            // 0x7A = 122 = F1, 0x60 = 96 = F5
            // 0x78 = 120 = F2, 0x61 = 97 = F6
            if (keycode == 0x7A || keycode == 0x60) {
                if (shiftPressed) {
                    manager->triggerAction(HotkeyAction::BRIGHTNESS_TOGGLE);
                } else {
                    manager->triggerAction(HotkeyAction::BRIGHTNESS_DOWN);
                }
                return NULL; // Swallow event
            } else if (keycode == 0x78 || keycode == 0x61) {
                manager->triggerAction(HotkeyAction::BRIGHTNESS_UP);
                return NULL; // Swallow event
            }
        }
    }

    return event;
}

static void AccessibilityCheckTimerCallback(CFRunLoopTimerRef timer, void *info) {
    (void)timer;
    HotkeyManager* manager = static_cast<HotkeyManager*>(info);
    if (manager && !manager->isEventTapActive()) {
        if (HotkeyManager::isAccessibilityGranted()) {
            if (manager->setupEventTap()) {
                std::cout << "\n[Hotkey] Accessibility granted! CoreGraphics Event Tap is now ACTIVE." << std::endl;
                std::cout << "[Hotkey] You can now press Cmd + F1 and Cmd + F2 directly." << std::endl;
                std::cout.flush();
            }
        }
    }
}

bool HotkeyManager::setupCarbonHotkeys() {
    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;

    EventHandlerRef handlerRef = nullptr;
    OSStatus status = InstallApplicationEventHandler(
        &CarbonHotKeyHandler,
        1,
        &eventType,
        this,
        &handlerRef
    );

    if (status != noErr) {
        std::cerr << "[Error] Failed to install Carbon event handler (status: " << status << ")" << std::endl;
        return false;
    }
    carbonHandlerRef_ = handlerRef;

    // HotKey 1: Cmd + F1 (0x7A = 122) -> Decrement / Turn Off
    EventHotKeyRef refDown = nullptr;
    EventHotKeyID idDown = {'KB01', 1};
    status = RegisterEventHotKey(0x7A, cmdKey, idDown, GetApplicationEventTarget(), 0, &refDown);
    if (status != noErr) {
        std::cerr << "[Warning] Failed to register Carbon HotKey Cmd+F1 (status: " << status << ")" << std::endl;
    }
    hotkeyRefDown_ = refDown;

    // HotKey 2: Cmd + F2 (0x78 = 120) -> Increment / Turn On
    EventHotKeyRef refUp = nullptr;
    EventHotKeyID idUp = {'KB02', 2};
    status = RegisterEventHotKey(0x78, cmdKey, idUp, GetApplicationEventTarget(), 0, &refUp);
    if (status != noErr) {
        std::cerr << "[Warning] Failed to register Carbon HotKey Cmd+F2 (status: " << status << ")" << std::endl;
    }
    hotkeyRefUp_ = refUp;

    // HotKey 3: Cmd + Shift + F1 (0x7A = 122) -> Instant Toggle ON/OFF
    EventHotKeyRef refToggle = nullptr;
    EventHotKeyID idToggle = {'KB03', 3};
    status = RegisterEventHotKey(0x7A, cmdKey | shiftKey, idToggle, GetApplicationEventTarget(), 0, &refToggle);
    if (status != noErr) {
        std::cerr << "[Warning] Failed to register Carbon HotKey Cmd+Shift+F1 (status: " << status << ")" << std::endl;
    }
    hotkeyRefToggle_ = refToggle;

    // Also register Cmd+F5 (0x60 = 96) and Cmd+F6 (0x61 = 97) for compatibility
    EventHotKeyRef refF5 = nullptr;
    EventHotKeyID idF5 = {'KB05', 4};
    RegisterEventHotKey(0x60, cmdKey, idF5, GetApplicationEventTarget(), 0, &refF5);

    EventHotKeyRef refF6 = nullptr;
    EventHotKeyID idF6 = {'KB06', 5};
    RegisterEventHotKey(0x61, cmdKey, idF6, GetApplicationEventTarget(), 0, &refF6);

    return (hotkeyRefDown_ != nullptr && hotkeyRefUp_ != nullptr);
}

bool HotkeyManager::setupEventTap() {
    if (eventTap_) return true;

    CGEventMask eventMask = (1ULL << kCGEventKeyDown) | (1ULL << 14); // 14 = NSSystemDefined

    // Prefer HID-level tap so brightness keys & Cmd+F1 are intercepted before WindowServer
    CFMachPortRef tap = CGEventTapCreate(
        kCGHIDEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        eventMask,
        EventTapCallback,
        this
    );

    if (!tap) {
        tap = CGEventTapCreate(
            kCGSessionEventTap,
            kCGHeadInsertEventTap,
            kCGEventTapOptionDefault,
            eventMask,
            EventTapCallback,
            this
        );
    }

    if (!tap) {
        return false;
    }

    eventTap_ = tap;
    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
    if (!source) {
        CFRelease(tap);
        eventTap_ = nullptr;
        return false;
    }

    runLoopSource_ = source;
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(tap, true);
    WriteDaemonTapState(true);
    return true;
}

void HotkeyManager::tearDownCarbonHotkeys() {
    if (hotkeyRefDown_) {
        UnregisterEventHotKey((EventHotKeyRef)hotkeyRefDown_);
        hotkeyRefDown_ = nullptr;
    }
    if (hotkeyRefUp_) {
        UnregisterEventHotKey((EventHotKeyRef)hotkeyRefUp_);
        hotkeyRefUp_ = nullptr;
    }
    if (hotkeyRefToggle_) {
        UnregisterEventHotKey((EventHotKeyRef)hotkeyRefToggle_);
        hotkeyRefToggle_ = nullptr;
    }
    if (carbonHandlerRef_) {
        RemoveEventHandler((EventHandlerRef)carbonHandlerRef_);
        carbonHandlerRef_ = nullptr;
    }
}

void HotkeyManager::tearDownEventTap() {
    if (runLoopSource_) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), (CFRunLoopSourceRef)runLoopSource_, kCFRunLoopCommonModes);
        CFRelease((CFRunLoopSourceRef)runLoopSource_);
        runLoopSource_ = nullptr;
    }
    if (eventTap_) {
        CGEventTapEnable((CFMachPortRef)eventTap_, false);
        CFRelease((CFMachPortRef)eventTap_);
        eventTap_ = nullptr;
    }
}

bool HotkeyManager::start() {
    // Initialize NSApplication for proper event pumping across Cocoa and Carbon
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    std::cout << "[Hotkey] Setting up listeners..." << std::endl;

    bool carbonOk = setupCarbonHotkeys();
    if (carbonOk) {
        std::cout << "[Hotkey] Carbon hotkeys active: Cmd+F1 (Down), Cmd+F2 (Up), Cmd+Shift+F1 (Toggle)" << std::endl;
    }

    bool tapOk = setupEventTap();
    if (tapOk) {
        std::cout << "[Hotkey] CoreGraphics Event Tap is ACTIVE: Direct Cmd+F1 and Cmd+F2 ready!" << std::endl;
    } else {
        WriteDaemonTapState(false);
        std::cout << "\n========================================================" << std::endl;
        std::cout << " [NOTICE] Accessibility Permission Needed for Direct Media Keys" << std::endl;
        std::cout << "========================================================" << std::endl;
        std::cout << " 1. TO USE DIRECT Cmd+F1 / Cmd+F2 (WITHOUT Fn):" << std::endl;
        std::cout << "    Enable Accessibility permission in System Settings." << std::endl;
        std::cout << "    (Run 'kb-backlight --permissions' to open the settings pane)." << std::endl;
        std::cout << " 2. TO USE RIGHT NOW WITH ZERO PERMISSIONS:" << std::endl;
        std::cout << "    Press Fn + Cmd + F1  (Brightness Down / OFF)" << std::endl;
        std::cout << "    Press Fn + Cmd + F2  (Brightness Up / ON)" << std::endl;
        std::cout << "========================================================\n" << std::endl;

        // Schedule timer to check for permission every 1.0s
        CFRunLoopTimerContext context = {0, this, NULL, NULL, NULL};
        CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + 1.0,
            1.0,
            0,
            0,
            AccessibilityCheckTimerCallback,
            &context
        );
        if (timer) {
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
            checkTimer_ = timer;
        }
    }

    if (!carbonOk && !tapOk) {
        std::cerr << "[Error] Failed to initialize any hotkey mechanism." << std::endl;
        return false;
    }

    std::cout << "[Hotkey] Running event loop. Press Ctrl+C to exit." << std::endl;
    std::cout.flush();

    [NSApp run];
    return true;
}

void HotkeyManager::stop() {
    if (checkTimer_) {
        CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), (CFRunLoopTimerRef)checkTimer_, kCFRunLoopCommonModes);
        CFRelease((CFRunLoopTimerRef)checkTimer_);
        checkTimer_ = nullptr;
    }
    tearDownEventTap();
    tearDownCarbonHotkeys();

    if (NSApp) {
        [NSApp stop:nil];
        NSEvent* event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                            location:NSMakePoint(0,0)
                                       modifierFlags:0
                                           timestamp:0
                                        windowNumber:0
                                             context:nil
                                             subtype:0
                                               data1:0
                                               data2:0];
        [NSApp postEvent:event atStart:YES];
    }
}
