#ifndef HOTKEY_MANAGER_H
#define HOTKEY_MANAGER_H

#include <functional>
#include <chrono>

enum class HotkeyAction {
    BRIGHTNESS_DOWN,
    BRIGHTNESS_UP,
    BRIGHTNESS_TOGGLE
};

using HotkeyCallback = std::function<void(HotkeyAction)>;

class HotkeyManager {
public:
    HotkeyManager();
    ~HotkeyManager();

    // Register action callback
    void setCallback(HotkeyCallback callback) { callback_ = std::move(callback); }

    // Start listening for hotkeys (enters CFRunLoop)
    bool start();

    // Stop listening and exit runloop
    void stop();

    // Trigger action safely with debounce
    void triggerAction(HotkeyAction action);

    // Check accessibility status
    static bool isAccessibilityGranted();

    // Request accessibility permission prompt from macOS
    static void promptAccessibilityPermission();

    // Open System Settings directly to Privacy & Security -> Accessibility
    static void openAccessibilitySettings();

    // Check if event tap is currently active
    bool isEventTapActive() const { return eventTap_ != nullptr; }

    // Setup Event Tap (can be called dynamically when permission granted)
    bool setupEventTap();

    void* getEventTap() const { return eventTap_; }

private:
    HotkeyCallback callback_;
    void* eventTap_{nullptr};
    void* runLoopSource_{nullptr};
    void* carbonHandlerRef_{nullptr};
    void* hotkeyRefDown_{nullptr};
    void* hotkeyRefUp_{nullptr};
    void* hotkeyRefToggle_{nullptr};
    void* checkTimer_{nullptr};

    std::chrono::steady_clock::time_point lastActionTime_;
    static constexpr int DEBOUNCE_MS = 100;

    bool setupCarbonHotkeys();
    void tearDownCarbonHotkeys();
    void tearDownEventTap();
};

#endif // HOTKEY_MANAGER_H
