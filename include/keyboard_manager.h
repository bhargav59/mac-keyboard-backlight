#ifndef KEYBOARD_MANAGER_H
#define KEYBOARD_MANAGER_H

#include <vector>
#include <string>
#include <cstdint>

/**
 * Manages communication with macOS CoreBrightness framework
 * to control MacBook keyboard backlight brightness.
 */
class KeyboardManager {
public:
    static constexpr int TOTAL_CHICLETS = 16;
    static constexpr float STEP_SIZE = 1.0f / static_cast<float>(TOTAL_CHICLETS);

    KeyboardManager();
    ~KeyboardManager();

    // Initialize CoreBrightness client and discover keyboards
    bool initialize();

    // Query current brightness level [0.0f, 1.0f]
    // Returns negative value on error.
    float getBrightness();

    // Set brightness level [0.0f, 1.0f]
    // Clamped between 0.0f and 1.0f.
    bool setBrightness(float level);

    // Increase brightness by 1 step (1/16th)
    // Returns the new brightness level.
    float increaseBrightness();

    // Decrease brightness by 1 step (1/16th)
    // Returns the new brightness level. Clamps to 0.0f (off).
    float decreaseBrightness();

    // Toggle backlight on/off
    // If currently > 0, turns off (0.0f) and saves previous level.
    // If currently 0, restores previous saved level (or fallback).
    float toggleBrightness(float fallbackLevel = 0.5f);

    // Check if keyboard backlight is currently on
    bool isOn();

    // Convert brightness [0.0f, 1.0f] to chiclets [0, 16]
    static int brightnessToChiclets(float brightness);

    // Convert chiclets [0, 16] to brightness [0.0f, 1.0f]
    static float chicletsToBrightness(int chiclets);

    // Get list of discovered keyboard backlight IDs
    const std::vector<uint64_t>& getKeyboardIDs() const { return keyboardIDs_; }

    // Last non-zero brightness level saved for restoration
    float getLastNonZeroBrightness() const { return lastNonZeroBrightness_; }
    void setLastNonZeroBrightness(float level);

private:
    void* clientInstance_{nullptr};
    std::vector<uint64_t> keyboardIDs_;
    float lastNonZeroBrightness_{0.5f};
    bool initialized_{false};

    bool refreshKeyboardIDs();
};

#endif // KEYBOARD_MANAGER_H
