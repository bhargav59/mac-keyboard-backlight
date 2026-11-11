#include "config.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <filesystem>
#include <cstdlib>

namespace fs = std::filesystem;

std::string AppConfig::getConfigFilePath() {
    const char* home = std::getenv("HOME");
    if (!home) {
        return "/tmp/keyboard_backlight_config.json";
    }
    return std::string(home) + "/.config/keyboard_backlight/config.json";
}

bool AppConfig::load(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        return false;
    }

    std::string line;
    while (std::getline(file, line)) {
        // Simple JSON key-value extraction
        if (line.find("\"last_nonzero_brightness\"") != std::string::npos) {
            auto colon = line.find(':');
            if (colon != std::string::npos) {
                try {
                    lastNonZeroBrightness = std::stof(line.substr(colon + 1));
                } catch (...) {}
            }
        } else if (line.find("\"show_osd\"") != std::string::npos) {
            if (line.find("false") != std::string::npos) {
                showOSD = false;
            } else if (line.find("true") != std::string::npos) {
                showOSD = true;
            }
        } else if (line.find("\"step_count\"") != std::string::npos) {
            auto colon = line.find(':');
            if (colon != std::string::npos) {
                try {
                    stepCount = std::stoi(line.substr(colon + 1));
                } catch (...) {}
            }
        }
    }
    return true;
}

bool AppConfig::save(const std::string& path) const {
    try {
        fs::path p(path);
        if (p.has_parent_path()) {
            fs::create_directories(p.parent_path());
        }
    } catch (const std::exception& e) {
        std::cerr << "[Warning] Failed to create config directory: " << e.what() << std::endl;
    }

    std::ofstream file(path);
    if (!file.is_open()) {
        return false;
    }

    file << "{\n";
    file << "  \"last_nonzero_brightness\": " << lastNonZeroBrightness << ",\n";
    file << "  \"show_osd\": " << (showOSD ? "true" : "false") << ",\n";
    file << "  \"step_count\": " << stepCount << "\n";
    file << "}\n";

    return true;
}
