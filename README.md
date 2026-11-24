# Chroma

Chroma is a native macOS menu-bar app for switching between Mission Control Spaces with **Option–Tab**. Each Space gets a color and a label. Full-screen Spaces show their app icons, and Split View tiles can show both.

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

| Input | Action |
| --- | --- |
| **⌥ Tab** | Hold Option and tap Tab to cycle forward. |
| **⌥ ⇧ Tab** | Cycle backward. |
| **Release Option** | Switch to the selected Space. |
| **Arrow keys** | Move the selection while the switcher is open. |
| **Return** or **click a tile** | Switch to that Space. |
| **C** or **Edit tiles** | Select a tile to rename or recolor it. Clear the name field to restore its default label. |
| **Esc** | Close the switcher. |

The white dot marks the current Space on each display. The outline marks the selected tile. Names and colors are saved locally.

Chroma lists Spaces through macOS's private SkyLight framework and switches via Mission Control Accessibility. Switching can briefly show Mission Control. If macOS creates a new Space identity when an app reenters full screen, Chroma assigns that Space a default name and color.

## License

[MIT](LICENSE)
