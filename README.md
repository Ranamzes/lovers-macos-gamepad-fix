# macOS Gamepad & Compatibility Patcher for Lovers in a Dangerous Spacetime

An open-source utility that resolves gamepad input issues and engine crashes on modern macOS versions (macOS 11 Big Sur through macOS 15 Sequoia), enabling full 4-player local co-op.

---

## What This Fix Does

1. **Resolves macOS 15 Sequoia Crash:** Bypasses the legacy `IOHIDManagerOpen` engine check that prevents the game from launching on macOS Sequoia.
2. **Multi-Controller Support:** Corrects button and axis mappings for Bluetooth wireless gamepads and the Valve Steam Controller.
3. **Eliminates Ghost Players:** Prevents unmapped virtual HID devices from auto-joining pods as uncontrollable players during character selection.
4. **4-Player Pause Menu:** Enables pausing from any connected controller.
5. **Automatic Re-signing:** Re-signs the modified application bundle using macOS `codesign` so the operating system launches it cleanly.

---

## Quick Start (No Terminal Required)

1. Download **`Lovers-Fix-macOS.zip`** from the [Releases](https://github.com/Ranamzes/lovers-macos-gamepad-fix/releases) page *(do **not** use "Code → Download ZIP", as it may strip executable permissions)*.
2. Unzip and double-click **`Lovers Fix.app`**.
   > **Gatekeeper Notice:** Since this tool uses an ad-hoc signature rather than a paid Apple Developer ID, macOS may block the first launch (*"Apple cannot check it for malicious software"*).  
   > To allow it: open **System Settings → Privacy & Security** and click **Open Anyway** (or run `xattr -cr "Lovers Fix.app"` in Terminal).
3. In the window that appears, click **Apply Fix**.
4. Configure Steam Input:
   - In Steam, open **Settings** → **Controller**.
   - Turn **OFF** the option: **"Enable Steam Input for Xbox Controllers"**.
   - *(Note: Keep Steam Input enabled for the Steam Controller if you use one).*
5. Launch the game from Steam and enjoy local co-op!

---

## Controller Compatibility

- **Xbox Wireless Controllers (Bluetooth) & Equivalents (8BitDo, GameSir, Flydigi):** Tested & Fully Working (up to 4 players).
- **Valve Steam Controller:** Tested & Fully Working.
- **PlayStation Controllers (DualShock 4 / DualSense):** 
  > **Note on PlayStation Gamepads:** Untested by the author due to lack of hardware. The underlying input library includes macOS profiles for PlayStation controllers, and this patch permits any recognized controller to join. If you use a PlayStation controller, please disable **"Steam Input for PlayStation Controllers"** in Steam settings to avoid dual-input issues on macOS. Feedback and pull requests are welcome!

---

## Restoring the Original Game

You can restore your game files at any time:
- Open **`Lovers Fix.app`** and click **Restore Original**.
- Alternatively, verify file integrity in Steam (Right-click game → **Properties** → **Installed Files** → **Verify integrity of game files**).

---

## Building from Source

Requirements: macOS with Apple Clang (`clang`).

```bash
git clone https://github.com/Ranamzes/lovers-macos-gamepad-fix.git
cd lovers-macos-gamepad-fix
make
```

This compiles a Universal Mach-O binary (`arm64` and `x86_64`) and packages `Lovers Fix.app` into `releases/Lovers-Fix-macOS.zip`.

---

## License

This project is licensed under the [MIT License](LICENSE).
This repository contains original patching code and does not distribute proprietary game assets or binaries.
