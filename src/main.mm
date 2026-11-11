#import <Foundation/Foundation.h>
#include <iostream>
#include <iomanip>
#include <string>
#include <vector>
#include <csignal>
#include <unistd.h>
#include <mach-o/dyld.h>
#include <filesystem>

#include "keyboard_manager.h"
#include "osd_notifier.h"
#include "hotkey_manager.h"
#include "config.h"
#include "daemon_manager.h"

namespace fs = std::filesystem;

static HotkeyManager* g_hotkeyManager = nullptr;
static KeyboardManager* g_keyboardManager = nullptr;
static OSDNotifier* g_osdNotifier = nullptr;
static AppConfig* g_config = nullptr;

static void SignalHandler(int signal) {
    std::cout << "\n[kb-backlight] Caught signal " << signal << ", shutting down..." << std::endl;
    if (g_config && g_keyboardManager) {
        g_config->lastNonZeroBrightness = g_keyboardManager->getLastNonZeroBrightness();
        g_config->save();
    }
    if (g_hotkeyManager) {
        g_hotkeyManager->stop();
    }
    exit(0);
}

static std::string GetExecutablePath() {
    char buf[1024];
    uint32_t size = sizeof(buf);
    if (_NSGetExecutablePath(buf, &size) == 0) {
        return fs::canonical(buf).string();
    }
    return "";
}

static void PrintProgressBar(float brightness) {
    int total = 16;
    int filled = KeyboardManager::brightnessToChiclets(brightness);
    std::cout << "[";
    for (int i = 0; i < total; ++i) {
        if (i < filled) std::cout << "█";
        else std::cout << "░";
    }
    std::cout << "] " << std::fixed << std::setprecision(1) << (brightness * 100.0f)
              << "% (" << filled << "/" << total << " steps)" << std::endl;
}

static void PrintUsage(const char* progName) {
    std::cout << "========================================================\n"
              << "  Mac Keyboard Backlight Controller (C/C++ Native Tool) \n"
              << "========================================================\n"
              << "Usage: " << progName << " [command / option]\n\n"
              << "Hotkeys (when running as daemon):\n"
              << "  Direct Mode (requires Accessibility permission):\n"
              << "    Cmd + F1         : Decrease keyboard brightness / Turn OFF\n"
              << "    Cmd + F2         : Increase keyboard brightness / Turn ON\n"
              << "    Cmd + Shift + F1 : Instant Toggle ON / OFF (restores previous level)\n\n"
              << "  Zero-Permission Mode (works immediately without any setup):\n"
              << "    Fn + Cmd + F1    : Decrease keyboard brightness / Turn OFF\n"
              << "    Fn + Cmd + F2    : Increase keyboard brightness / Turn ON\n\n"
              << "Commands:\n"
              << "  --daemon               Run hotkey listener service in foreground\n"
              << "  --status               Show current keyboard brightness and devices\n"
              << "  --up                   Increase keyboard brightness by 1 step\n"
              << "  --down                 Decrease keyboard brightness by 1 step\n"
              << "  --toggle               Toggle keyboard backlight ON / OFF\n"
              << "  --on                   Turn keyboard backlight ON (restores previous level)\n"
              << "  --off                  Turn keyboard backlight completely OFF\n"
              << "  --set <0.0-1.0>        Set exact brightness level (e.g. 0.5 or 50%)\n"
              << "  --install              Install and start as background LaunchAgent (starts on login)\n"
              << "  --uninstall            Stop and remove background LaunchAgent\n"
              << "  --daemon-status        Check if background LaunchAgent is active\n"
              << "  --permissions          Open System Settings to grant Accessibility permission\n"
              << "  --help                 Show this help message\n"
              << "========================================================\n";
}

int main(int argc, char* argv[]) {
    @autoreleasepool {
        KeyboardManager kb;
        OSDNotifier osd;
        AppConfig config;

        config.load();
        kb.setLastNonZeroBrightness(config.lastNonZeroBrightness);
        osd.setEnabled(config.showOSD);

        g_keyboardManager = &kb;
        g_osdNotifier = &osd;
        g_config = &config;

        std::string command = (argc > 1) ? argv[1] : "--help";

        if (command == "--help" || command == "-h") {
            PrintUsage(argv[0]);
            return 0;
        }

        if (command == "--permissions" || command == "--request-permission") {
            std::cout << "Opening System Settings > Privacy & Security > Accessibility...\n";
            HotkeyManager::openAccessibilitySettings();
            HotkeyManager::promptAccessibilityPermission();
            std::cout << "\nPlease ensure your Terminal (or kb-backlight) switch is toggled ON.\n";
            std::cout << "Once enabled, Cmd + F1 and Cmd + F2 will work directly without needing the Fn key.\n";
            return 0;
        }

        if (!kb.initialize()) {
            std::cerr << "[Error] Failed to initialize keyboard backlight controller." << std::endl;
            return 1;
        }

        if (command == "--status") {
            float current = kb.getBrightness();
            std::cout << "Keyboard Backlight Status:\n";
            std::cout << "  State: " << (kb.isOn() ? "ON" : "OFF") << "\n";
            std::cout << "  Brightness: ";
            PrintProgressBar(current);
            std::cout << "  Last Active Brightness: " << (config.lastNonZeroBrightness * 100.0f) << "%\n";
            std::cout << "  Detected Backlight Devices: " << kb.getKeyboardIDs().size() << "\n";
            for (auto id : kb.getKeyboardIDs()) {
                std::cout << "    - Device ID: " << id << "\n";
            }
            DaemonManager::printStatus();
            bool trusted = HotkeyManager::isAccessibilityGranted();
            std::cout << "  Accessibility Permission: "
                      << (trusted ? "GRANTED (Direct Cmd+F1/F2 active)" : "NOT GRANTED (Use Fn+Cmd+F1/F2, or run 'kb-backlight --permissions')")
                      << "\n";
            return 0;
        }

        if (command == "--up") {
            float next = kb.increaseBrightness();
            osd.showBrightness(next);
            config.lastNonZeroBrightness = kb.getLastNonZeroBrightness();
            config.save();
            std::cout << "Keyboard brightness increased: ";
            PrintProgressBar(next);
            return 0;
        }

        if (command == "--down") {
            float next = kb.decreaseBrightness();
            osd.showBrightness(next);
            config.lastNonZeroBrightness = kb.getLastNonZeroBrightness();
            config.save();
            std::cout << "Keyboard brightness decreased: ";
            PrintProgressBar(next);
            return 0;
        }

        if (command == "--toggle") {
            float next = kb.toggleBrightness(config.lastNonZeroBrightness);
            osd.showBrightness(next);
            config.lastNonZeroBrightness = kb.getLastNonZeroBrightness();
            config.save();
            std::cout << "Keyboard backlight toggled (" << (kb.isOn() ? "ON" : "OFF") << "): ";
            PrintProgressBar(next);
            return 0;
        }

        if (command == "--on") {
            float target = (config.lastNonZeroBrightness > 0.001f) ? config.lastNonZeroBrightness : 0.5f;
            kb.setBrightness(target);
            osd.showBrightness(target);
            std::cout << "Keyboard backlight turned ON: ";
            PrintProgressBar(target);
            return 0;
        }

        if (command == "--off") {
            float cur = kb.getBrightness();
            if (cur > 0.001f) {
                config.lastNonZeroBrightness = cur;
                config.save();
            }
            kb.setBrightness(0.0f);
            osd.showBrightness(0.0f);
            std::cout << "Keyboard backlight turned OFF.\n";
            return 0;
        }

        if (command == "--set") {
            if (argc < 3) {
                std::cerr << "Usage: " << argv[0] << " --set <0.0-1.0 or percentage e.g. 50%>\n";
                return 1;
            }
            std::string valStr = argv[2];
            float val = 0.0f;
            try {
                if (valStr.back() == '%') {
                    val = std::stof(valStr.substr(0, valStr.size() - 1)) / 100.0f;
                } else {
                    val = std::stof(valStr);
                }
            } catch (...) {
                std::cerr << "Invalid value: " << valStr << "\n";
                return 1;
            }
            kb.setBrightness(val);
            float actual = kb.getBrightness();
            osd.showBrightness(actual);
            config.lastNonZeroBrightness = kb.getLastNonZeroBrightness();
            config.save();
            std::cout << "Keyboard brightness set to: ";
            PrintProgressBar(actual);
            return 0;
        }

        if (command == "--install") {
            std::string execPath = GetExecutablePath();
            if (execPath.empty()) {
                std::cerr << "[Error] Cannot determine executable path.\n";
                return 1;
            }
            bool ok = DaemonManager::install(execPath);
            if (ok) {
                if (!HotkeyManager::isAccessibilityGranted()) {
                    std::cout << "\n[TIP] For direct Cmd+F1/F2 without holding Fn:" << std::endl;
                    std::cout << "Run: kb-backlight --permissions\n" << std::endl;
                }
                return 0;
            }
            return 1;
        }

        if (command == "--uninstall") {
            DaemonManager::uninstall();
            return 0;
        }

        if (command == "--daemon-status") {
            DaemonManager::printStatus();
            return 0;
        }

        if (command == "--daemon") {
            std::signal(SIGINT, SignalHandler);
            std::signal(SIGTERM, SignalHandler);

            HotkeyManager hotkeyManager;
            g_hotkeyManager = &hotkeyManager;

            hotkeyManager.setCallback([&](HotkeyAction action) {
                switch (action) {
                    case HotkeyAction::BRIGHTNESS_DOWN: {
                        float next = kb.decreaseBrightness();
                        osd.showBrightness(next);
                        config.lastNonZeroBrightness = kb.getLastNonZeroBrightness();
                        config.save();
                        std::cout << "[Action] Brightness Down -> " << (next * 100.0f) << "%\n";
                        std::cout.flush();
                        break;
                    }
                    case HotkeyAction::BRIGHTNESS_UP: {
                        float next = kb.increaseBrightness();
                        osd.showBrightness(next);
                        config.lastNonZeroBrightness = kb.getLastNonZeroBrightness();
                        config.save();
                        std::cout << "[Action] Brightness Up -> " << (next * 100.0f) << "%\n";
                        std::cout.flush();
                        break;
                    }
                    case HotkeyAction::BRIGHTNESS_TOGGLE: {
                        float next = kb.toggleBrightness(config.lastNonZeroBrightness);
                        osd.showBrightness(next);
                        config.lastNonZeroBrightness = kb.getLastNonZeroBrightness();
                        config.save();
                        std::cout << "[Action] Brightness Toggle -> " << (next * 100.0f) << "%\n";
                        std::cout.flush();
                        break;
                    }
                }
            });

            std::cout << "========================================================\n"
                      << "  Starting Mac Keyboard Backlight Daemon                \n"
                      << "========================================================\n";

            hotkeyManager.start();
            return 0;
        }

        std::cerr << "Unknown command: " << command << "\n";
        PrintUsage(argv[0]);
        return 1;
    }
}
