#include "daemon_manager.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <filesystem>
#include <cstdlib>
#include <unistd.h>

namespace fs = std::filesystem;

std::string DaemonManager::getPlistPath() {
    const char* home = std::getenv("HOME");
    if (!home) return "";
    return std::string(home) + "/Library/LaunchAgents/" + PLIST_LABEL + ".plist";
}

bool DaemonManager::install(const std::string& binaryPath) {
    const char* home = std::getenv("HOME");
    if (!home) {
        std::cerr << "[Error] Cannot locate HOME directory." << std::endl;
        return false;
    }

    std::string homeDir(home);
    std::string appDir = homeDir + "/Applications/KeyboardBacklight.app";
    std::string contentsDir = appDir + "/Contents";
    std::string macosDir = contentsDir + "/MacOS";
    std::string targetBinary = macosDir + "/KeyboardBacklight";

    // Stop existing daemon before overwriting bundle binary
    uninstall();

    // 1. Create App Bundle structure
    try {
        fs::create_directories(macosDir);
    } catch (const std::exception& e) {
        std::cerr << "[Error] Failed to create application directory: " << e.what() << std::endl;
        return false;
    }

    // 2. Copy binary into app bundle
    try {
        fs::copy_file(binaryPath, targetBinary, fs::copy_options::overwrite_existing);
        fs::permissions(targetBinary, fs::perms::owner_all | fs::perms::group_read | fs::perms::group_exec | fs::perms::others_read | fs::perms::others_exec);
    } catch (const std::exception& e) {
        std::cerr << "[Error] Failed to copy binary to app bundle: " << e.what() << std::endl;
        return false;
    }

    // 3. Write Info.plist
    std::string infoPlistPath = contentsDir + "/Info.plist";
    std::ofstream plistFile(infoPlistPath);
    if (plistFile.is_open()) {
        plistFile << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
        plistFile << "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n";
        plistFile << "<plist version=\"1.0\">\n";
        plistFile << "<dict>\n";
        plistFile << "    <key>CFBundleIdentifier</key>\n";
        plistFile << "    <string>" << BUNDLE_ID << "</string>\n";
        plistFile << "    <key>CFBundleName</key>\n";
        plistFile << "    <string>KeyboardBacklight</string>\n";
        plistFile << "    <key>CFBundleDisplayName</key>\n";
        plistFile << "    <string>Keyboard Backlight Controller</string>\n";
        plistFile << "    <key>CFBundleExecutable</key>\n";
        plistFile << "    <string>KeyboardBacklight</string>\n";
        plistFile << "    <key>CFBundlePackageType</key>\n";
        plistFile << "    <string>APPL</string>\n";
        plistFile << "    <key>LSUIElement</key>\n";
        plistFile << "    <true/>\n";
        plistFile << "    <key>LSBackgroundOnly</key>\n";
        plistFile << "    <false/>\n";
        plistFile << "</dict>\n";
        plistFile << "</plist>\n";
        plistFile.close();
    }

    // 4. Code-sign the App Bundle
    std::string signCmd = "codesign -s - -f --identifier " + std::string(BUNDLE_ID) + " \"" + appDir + "\" >/dev/null 2>&1";
    std::system(signCmd.c_str());

    // 5. Install LaunchAgent plist
    std::string plistPath = getPlistPath();
    try {
        fs::path p(plistPath);
        fs::create_directories(p.parent_path());
    } catch (...) {}

    std::ofstream file(plistPath);
    if (!file.is_open()) {
        std::cerr << "[Error] Failed to write launchd plist at " << plistPath << std::endl;
        return false;
    }

    file << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    file << "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n";
    file << "<plist version=\"1.0\">\n";
    file << "<dict>\n";
    file << "    <key>Label</key>\n";
    file << "    <string>" << PLIST_LABEL << "</string>\n";
    file << "    <key>ProgramArguments</key>\n";
    file << "    <array>\n";
    file << "        <string>" << targetBinary << "</string>\n";
    file << "        <string>--daemon</string>\n";
    file << "    </array>\n";
    file << "    <key>RunAtLoad</key>\n";
    file << "    <true/>\n";
    file << "    <key>KeepAlive</key>\n";
    file << "    <true/>\n";
    file << "    <key>StandardOutPath</key>\n";
    file << "    <string>/tmp/keyboardbacklight.out</string>\n";
    file << "    <key>StandardErrorPath</key>\n";
    file << "    <string>/tmp/keyboardbacklight.err</string>\n";
    file << "    <key>ProcessType</key>\n";
    file << "    <string>Interactive</string>\n";
    file << "</dict>\n";
    file << "</plist>\n";
    file.close();

    std::string loadCmd = "launchctl load \"" + plistPath + "\" 2>&1";
    int ret = std::system(loadCmd.c_str());
    if (ret != 0) {
        std::cerr << "[Warning] launchctl load returned code " << ret << std::endl;
    }

    std::cout << "Successfully created Application Bundle: " << appDir << std::endl;
    std::cout << "Successfully installed LaunchAgent: " << plistPath << std::endl;
    std::cout << "Daemon is active and will automatically launch on every login." << std::endl;
    return true;
}

bool DaemonManager::uninstall() {
    std::string plistPath = getPlistPath();
    if (!plistPath.empty() && fs::exists(plistPath)) {
        std::string unloadCmd = "launchctl unload \"" + plistPath + "\" 2>/dev/null";
        std::system(unloadCmd.c_str());
        try {
            fs::remove(plistPath);
            std::cout << "Removed LaunchAgent plist: " << plistPath << std::endl;
        } catch (...) {}
    }

    // Also unload legacy label if present from earlier version
    const char* home = std::getenv("HOME");
    if (home) {
        std::string legacyPlist = std::string(home) + "/Library/LaunchAgents/com.user.keyboardbacklight.plist";
        if (fs::exists(legacyPlist)) {
            std::string unloadLegacy = "launchctl unload \"" + legacyPlist + "\" 2>/dev/null";
            std::system(unloadLegacy.c_str());
            try { fs::remove(legacyPlist); } catch (...) {}
        }
    }

    // Stop only daemon instances (never kill CLI invocations like --install)
    std::system("pkill -TERM -f 'KeyboardBacklight --daemon' 2>/dev/null || true");
    std::system("pkill -TERM -f 'kb-backlight --daemon' 2>/dev/null || true");

    return true;
}

bool DaemonManager::isRunning() {
    std::string checkCmd = "launchctl list | grep \"" + std::string(PLIST_LABEL) + "\" > /dev/null 2>&1";
    return (std::system(checkCmd.c_str()) == 0);
}

void DaemonManager::printStatus() {
    std::cout << "Daemon Status (" << PLIST_LABEL << "): "
              << (isRunning() ? "RUNNING (active in launchd)" : "STOPPED / NOT INSTALLED")
              << std::endl;
    std::string plistPath = getPlistPath();
    std::cout << "Plist location: " << plistPath << " ("
              << (fs::exists(plistPath) ? "Exists" : "Does not exist") << ")"
              << std::endl;
}
