# Mac Keyboard Backlight Controller (`kb-backlight`)

A lightweight, native C++17 / Objective-C++ system daemon and CLI for **Apple Silicon MacBooks (M1 / M2 / M3 / M4)** that brings back instant keyboard backlight control using **Command + F1** and **Command + F2**, completely independent of screen brightness.

> **Why this exists:** Starting with Apple Silicon MacBooks, Apple replaced the dedicated keyboard brightness keys (`F5` / `F6`) with Dictation and Focus. Adjusting the keyboard light requires opening Control Center or System Settings. `kb-backlight` lets `F1` / `F2` continue controlling screen brightness normally while `Cmd + F1` / `Cmd + F2` control your keyboard backlight with macOS's native on-screen HUD bezel.

---

## Features

- **Independent Key Bindings**:
  - `Cmd + F1`: Decrease keyboard brightness by 1 step (1/16th) down to **OFF** (`0%`).
  - `Cmd + F2`: Increase keyboard brightness by 1 step (1/16th) up to `100%` (turns **ON** if off).
  - `Cmd + Shift + F1`: Instant **Toggle ON / OFF** (remembers and restores your last active brightness).
  - `F1` / `F2` alone: Screen brightness remains completely untouched.
- **Native macOS OSD Bezel**: Displays Apple's native On-Screen Display keyboard backlight HUD with 16 chiclet steps via `OSD.framework`.
- **Direct Hardware Control**: Uses `CoreBrightness.framework` (`KeyboardBrightnessClient`) and wakes idle-dimmed backlights immediately.
- **Persistent Background Service**: `--install` packages a background app bundle (`~/Applications/KeyboardBacklight.app`) and registers a `launchd` LaunchAgent so it runs automatically on every login.
- **Dual Interception**:
  - **CoreGraphics Event Tap (`CGEventTap`)**: Intercepts and swallows media-key brightness events when `Cmd` is held so screen brightness never changes.
  - **Carbon HotKeys (`RegisterEventHotKey`)**: Zero-permission fallback (`Fn + Cmd + F1` / `Fn + Cmd + F2`, or direct `Cmd + F1/F2` if standard function keys are enabled).

---

## Requirements

- macOS on Apple Silicon (`arm64`) MacBook (also compiles from source on Intel Macs with Touch Bar / supported Apple backlight hardware)
- Xcode Command Line Tools (`xcode-select --install`)

---

## Quick Start

### Install via Homebrew (Recommended)

```bash
brew install bhargav59/tap/kb-backlight
```

To upgrade later:
```bash
brew upgrade kb-backlight
```

### Build from Source

```bash
git clone https://github.com/bhargav59/mac-keyboard-backlight.git
cd mac-keyboard-backlight
make
make test
make install
```

`make install` copies `kb-backlight` to `~/.local/bin/kb-backlight`. Ensure `~/.local/bin` is in your `$PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## Running in the Background (Auto-Start on Login)

1. Install the app bundle and LaunchAgent:
   ```bash
   kb-backlight --install
   ```
   This creates `~/Applications/KeyboardBacklight.app` and loads `~/Library/LaunchAgents/io.github.bhargav59.keyboardbacklight.plist`.

2. **Grant Accessibility Permission (for direct `Cmd + F1` / `Cmd + F2` without `Fn`):**
   ```bash
   kb-backlight --permissions
   ```
   In **System Settings → Privacy & Security → Device Control and Data Access** *(labeled **Accessibility** on macOS 15 and earlier)*:
   - Toggle ON **`Keyboard Backlight Controller`** (`KeyboardBacklight`) — or click `+` → press `Cmd + Shift + G` → enter `~/Applications` → select **`KeyboardBacklight.app`** → toggle **ON**.
   - The running daemon detects the permission within 1 second and activates direct `Cmd + F1` / `Cmd + F2` automatically.

   > **Zero-permission alternative:** Without Accessibility permission, **`Fn + Cmd + F1`**, **`Fn + Cmd + F2`**, and **`Fn + Cmd + Shift + F1`** work immediately (or turn on *Use F1, F2, etc. keys as standard function keys* in System Settings).

---

## CLI Reference

```bash
kb-backlight --status            # Show backlight state, brightness bar, and daemon status
kb-backlight --up                # Increase brightness by 1 step (+6.25%)
kb-backlight --down              # Decrease brightness by 1 step (-6.25%)
kb-backlight --toggle            # Toggle ON / OFF (restores last active level)
kb-backlight --on                # Turn ON to last active brightness
kb-backlight --off               # Turn completely OFF
kb-backlight --set 50%           # Set exact brightness (0.0-1.0 or percentage)
kb-backlight --daemon            # Run foreground hotkey listener
kb-backlight --install           # Install ~/Applications/KeyboardBacklight.app + LaunchAgent
kb-backlight --uninstall         # Stop and remove LaunchAgent
kb-backlight --daemon-status     # Check launchd daemon status
kb-backlight --permissions       # Open Accessibility privacy settings
```

---

## Project Structure

```
mac-keyboard-backlight/
├── Makefile
├── LICENSE
├── README.md
├── .github/workflows/ci.yml
├── include/
│   ├── config.h
│   ├── daemon_manager.h
│   ├── hotkey_manager.h
│   ├── keyboard_manager.h
│   └── osd_notifier.h
├── src/
│   ├── config.cpp
│   ├── daemon_manager.cpp
│   ├── hotkey_manager.mm
│   ├── keyboard_manager.mm
│   ├── main.mm
│   └── osd_notifier.mm
└── tests/
    └── test_suite.cpp
```

---

## License

MIT License — see [LICENSE](LICENSE).
