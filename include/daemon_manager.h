#ifndef DAEMON_MANAGER_H
#define DAEMON_MANAGER_H

#include <string>

class DaemonManager {
public:
    static constexpr const char* PLIST_LABEL = "io.github.bhargav59.keyboardbacklight";
    static constexpr const char* BUNDLE_ID = "io.github.bhargav59.keyboardbacklight";

    // Returns path to ~/Library/LaunchAgents/io.github.bhargav59.keyboardbacklight.plist
    static std::string getPlistPath();

    // Install and start the LaunchAgent daemon
    static bool install(const std::string& binaryPath);

    // Stop and remove the LaunchAgent daemon
    static bool uninstall();

    // Check daemon status
    static bool isRunning();
    static void printStatus();
};

#endif // DAEMON_MANAGER_H
