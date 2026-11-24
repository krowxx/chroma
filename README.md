# Chroma

Chroma is a native macOS menu-bar app for switching between Mission Control Spaces. Each Space gets a color and a label. Full-screen Spaces show their app icons, and Split View tiles can show both.

## Build and run

Chroma targets macOS 14 and later and was tested on macOS 26.5.1. It uses Swift, AppKit, SwiftUI, and macOS system frameworks. Building requires the Xcode command-line tools.

```sh
git clone https://github.com/krowxx/chroma.git
cd chroma
./build.sh
open build/Chroma.app
```

Chroma appears in the menu bar as a stack of squares. In the switcher, click **Allow Accessibility**, then enable Chroma in **System Settings → Privacy & Security → Accessibility**. If the prompt stays visible after you enable it, quit and reopen Chroma.

## Controls

On ISO keyboards, press **Command** and the key just left of **1**. On a German keyboard, that's **⌘ ^**. Chroma uses **Control–Command–Tab** on other keyboard types to preserve the system window shortcut.

| Input | Action |
| --- | --- |
| **Opening shortcut** | Open the switcher with the current Space selected. |
| **Tab** | Cycle forward. |
| **⇧ Tab** | Cycle backward. |
| **Arrow keys** | Move the selection while the switcher is open. |
| **Return** or **click a tile** | Switch to that Space. |
| **C** or **Edit tiles** | Select a tile to rename or recolor it. Clear the name field to restore its default label. |
| **Esc** | Close the switcher. |

The white dot marks the current Space on each display. The outline marks the selected tile. Names and colors are saved locally.

### Trackpad

In **System Settings → Trackpad → More Gestures**, set **Mission Control** to **Swipe Up with Four Fingers**. Then enable **Three-Finger Swipe Up** in Chroma’s menu. Swipe up with three fingers and lift to open Chroma on the current Space. Click a tile or use the usual selection keys to switch.

The optional gesture reads the default trackpad through macOS’s private MultitouchSupport framework. Chroma leaves changes to the macOS gesture assignments to System Settings.

Chroma lists Spaces through macOS's private SkyLight framework and switches via Mission Control Accessibility. Switching can briefly show Mission Control. If macOS creates a new Space identity when an app reenters full screen, Chroma assigns that Space a default name and color.

## License

[MIT](LICENSE)
