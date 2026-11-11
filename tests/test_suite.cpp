#include <iostream>
#include <cassert>
#include <cmath>
#include <cstdlib>
#include <filesystem>

#include "keyboard_manager.h"
#include "osd_notifier.h"
#include "config.h"

namespace fs = std::filesystem;

#define TEST_ASSERT(cond, msg) \
    do { \
        if (!(cond)) { \
            std::cerr << "[FAIL] " << msg << " (" << #cond << ") at line " << __LINE__ << std::endl; \
            return false; \
        } else { \
            std::cout << "  [PASS] " << msg << std::endl; \
        } \
    } while(0)

bool TestChicletMath() {
    std::cout << "\n--- Running TestChicletMath ---" << std::endl;

    TEST_ASSERT(KeyboardManager::brightnessToChiclets(0.0f) == 0, "0.0f brightness is 0 chiclets");
    TEST_ASSERT(KeyboardManager::brightnessToChiclets(1.0f) == 16, "1.0f brightness is 16 chiclets");
    TEST_ASSERT(KeyboardManager::brightnessToChiclets(0.5f) == 8, "0.5f brightness is 8 chiclets");
    TEST_ASSERT(KeyboardManager::brightnessToChiclets(0.0625f) == 1, "0.0625f brightness is 1 chiclet");

    TEST_ASSERT(std::fabs(KeyboardManager::chicletsToBrightness(0) - 0.0f) < 0.0001f, "0 chiclets is 0.0f");
    TEST_ASSERT(std::fabs(KeyboardManager::chicletsToBrightness(16) - 1.0f) < 0.0001f, "16 chiclets is 1.0f");
    TEST_ASSERT(std::fabs(KeyboardManager::chicletsToBrightness(8) - 0.5f) < 0.0001f, "8 chiclets is 0.5f");

    // Round-trip test for all 16 levels
    for (int i = 0; i <= 16; ++i) {
        float b = KeyboardManager::chicletsToBrightness(i);
        int c = KeyboardManager::brightnessToChiclets(b);
        TEST_ASSERT(c == i, "Round-trip chiclet conversion holds for level " + std::to_string(i));
    }

    return true;
}

bool TestBoundaryConditions() {
    std::cout << "\n--- Running TestBoundaryConditions ---" << std::endl;

    TEST_ASSERT(KeyboardManager::brightnessToChiclets(-0.5f) == 0, "Negative brightness clamps to 0");
    TEST_ASSERT(KeyboardManager::brightnessToChiclets(2.5f) == 16, ">1.0 brightness clamps to 16");

    TEST_ASSERT(std::fabs(KeyboardManager::chicletsToBrightness(-5) - 0.0f) < 0.0001f, "Negative chiclets clamp to 0.0f");
    TEST_ASSERT(std::fabs(KeyboardManager::chicletsToBrightness(30) - 1.0f) < 0.0001f, ">16 chiclets clamp to 1.0f");

    return true;
}

bool TestConfigPersistence() {
    std::cout << "\n--- Running TestConfigPersistence ---" << std::endl;

    std::string tempPath = "/tmp/kb_backlight_test_config.json";
    fs::remove(tempPath);

    AppConfig cfg;
    cfg.lastNonZeroBrightness = 0.75f;
    cfg.showOSD = true;
    cfg.stepCount = 16;

    TEST_ASSERT(cfg.save(tempPath), "Config save should succeed");

    AppConfig loadedCfg;
    loadedCfg.lastNonZeroBrightness = 0.1f;
    loadedCfg.showOSD = false;
    loadedCfg.stepCount = 8;

    TEST_ASSERT(loadedCfg.load(tempPath), "Config load should succeed");
    TEST_ASSERT(std::fabs(loadedCfg.lastNonZeroBrightness - 0.75f) < 0.01f, "Loaded brightness matches saved");
    TEST_ASSERT(loadedCfg.showOSD == true, "Loaded showOSD matches saved");
    TEST_ASSERT(loadedCfg.stepCount == 16, "Loaded stepCount matches saved");

    fs::remove(tempPath);
    return true;
}

bool TestHardwareClient(bool isCI) {
    std::cout << "\n--- Running TestHardwareClient ---" << std::endl;

    KeyboardManager kb;
    if (!kb.initialize()) {
        if (isCI) {
            std::cout << "  [SKIP] No backlit keyboard hardware in CI VM environment." << std::endl;
            return true;
        }
        TEST_ASSERT(false, "KeyboardManager initializes with CoreBrightness");
    }

    float initial = kb.getBrightness();
    TEST_ASSERT(initial >= 0.0f && initial <= 1.0f, "Initial brightness is within [0.0, 1.0]");
    std::cout << "  [INFO] Hardware reported current brightness: " << initial << std::endl;

    const auto& ids = kb.getKeyboardIDs();
    TEST_ASSERT(!ids.empty(), "At least one keyboard device ID detected");
    std::cout << "  [INFO] Detected " << ids.size() << " keyboard ID(s): " << ids.front() << std::endl;

    float testVal = (initial > 0.5f) ? 0.3f : 0.7f;
    TEST_ASSERT(kb.setBrightness(testVal), "Setting brightness succeeds");

    float readBack = kb.getBrightness();
    TEST_ASSERT(std::fabs(readBack - testVal) < 0.02f, "Read back brightness matches set value");

    TEST_ASSERT(kb.setBrightness(initial), "Restoring original brightness succeeds");
    TEST_ASSERT(std::fabs(kb.getBrightness() - initial) < 0.02f, "Original brightness restored correctly");

    return true;
}

bool TestOSDNotifier(bool isCI) {
    std::cout << "\n--- Running TestOSDNotifier ---" << std::endl;

    OSDNotifier osd;
    if (!osd.initialize()) {
        if (isCI) {
            std::cout << "  [SKIP] OSD.framework / WindowServer unavailable in CI VM environment." << std::endl;
            return true;
        }
        TEST_ASSERT(false, "OSDNotifier successfully links with OSD.framework");
    } else {
        std::cout << "  [PASS] OSDNotifier successfully links with OSD.framework" << std::endl;
    }

    if (!isCI) {
        osd.show(8, 16);
        std::cout << "  [INFO] OSD HUD triggered for 8/16 chiclets." << std::endl;
    }

    return true;
}

int main() {
    bool isCI = (std::getenv("CI") != nullptr);

    std::cout << "========================================" << std::endl;
    std::cout << "   Keyboard Backlight Unit Test Suite   " << std::endl;
    std::cout << "========================================" << std::endl;

    int passed = 0;
    int total = 5;

    if (TestChicletMath()) passed++;
    if (TestBoundaryConditions()) passed++;
    if (TestConfigPersistence()) passed++;
    if (TestHardwareClient(isCI)) passed++;
    if (TestOSDNotifier(isCI)) passed++;

    std::cout << "\n========================================" << std::endl;
    std::cout << "Summary: " << passed << " / " << total << " test suites passed." << std::endl;
    std::cout << "========================================" << std::endl;

    return (passed == total) ? 0 : 1;
}
