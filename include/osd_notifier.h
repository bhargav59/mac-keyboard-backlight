#ifndef OSD_NOTIFIER_H
#define OSD_NOTIFIER_H

#include <cstdint>

/**
 * Displays the native macOS On-Screen Display (OSD) HUD bezel
 * for keyboard backlight changes (image type 2).
 */
class OSDNotifier {
public:
    OSDNotifier();
    ~OSDNotifier();

    // Initialize the OSD.framework manager
    bool initialize();

    // Display the OSD bezel with the given number of chiclets [0..16]
    void show(int filledChiclets, int totalChiclets = 16);

    // Display the OSD bezel from a brightness float [0.0f..1.0f]
    void showBrightness(float brightness);

    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }

private:
    void* osdManager_{nullptr};
    bool initialized_{false};
    bool enabled_{true};
};

#endif // OSD_NOTIFIER_H
