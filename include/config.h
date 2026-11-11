#ifndef CONFIG_H
#define CONFIG_H

#include <string>

struct AppConfig {
    float lastNonZeroBrightness{0.5f};
    bool showOSD{true};
    int stepCount{16};

    static std::string getConfigFilePath();
    bool load(const std::string& path = getConfigFilePath());
    bool save(const std::string& path = getConfigFilePath()) const;
};

#endif // CONFIG_H
