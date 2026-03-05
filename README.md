# SmartTile

**AI-powered window manager for macOS.** SmartTile uses a local LLM to analyze your open windows and arrange them intelligently — no cloud, no subscription, completely free.

Unlike traditional tiling window managers that use fixed rules, SmartTile understands *what* your windows are (editor, browser, terminal, chat) and arranges them accordingly. It can also remember layouts you save for specific app combinations.

## Features

- **Smart Arrange** — AI analyzes your open windows and suggests an optimal layout based on window types and screen size
- **Layout Memory** — save your preferred layout for a specific set of apps; next time the exact same apps are open, the saved layout is restored instantly without calling AI
- **Grid Overlay** — Divvy-style interactive grid for precise manual window placement
- **Quick Layouts** — one-click presets from the menu: 2/3/4 column grids, 1/2 + 1/2, 2/3 + 1/3, 1/3 + 2/3 splits
- **Local AI** — runs entirely on your Mac using [llama.cpp](https://github.com/ggerganov/llama.cpp) with a small quantized model (~1 GB)
- **Menu bar app** — lives in the menu bar, no dock icon, zero clutter
- **Zero dependencies** — pure Swift/AppKit, no external frameworks

## How It Works

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  Detect      │────>│  Classify     │────>│  Check saved  │
│  windows     │     │  (editor,     │     │  layouts      │
│  (AXUIElement)│     │   terminal…) │     │              │
└─────────────┘     └──────────────┘     └──────┬───────┘
                                                │
                                    ┌───────────┴───────────┐
                                    │                       │
                              Found saved              No match
                              layout                       │
                                    │                       v
                                    │              ┌──────────────┐
                                    │              │  Local LLM    │
                                    │              │  (llama.cpp)  │
                                    │              └──────┬───────┘
                                    │                     │
                                    v                     v
                              ┌──────────────────────────────┐
                              │  Apply layout via AXUIElement │
                              └──────────────────────────────┘
```

## Installation

### Prerequisites

- macOS 14.0+ (Sonoma or later)
- Xcode 15+ (for building from source)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [llama.cpp](https://github.com/ggerganov/llama.cpp) (for AI features — grid layout works without it)

### Build from Source

```bash
# Install build tools
brew install xcodegen

# Clone and build
git clone https://github.com/mzdev/SmartTile.git
cd SmartTile
xcodegen generate
open SmartTile.xcodeproj
# Press Cmd+R in Xcode to build and run
```

### Set Up AI Model

```bash
# Install llama.cpp
brew install llama.cpp

# The app will guide you through downloading the AI model (~1 GB) in Settings
```

### Grant Permissions

On first launch, macOS will ask for **Accessibility** permission:

> System Settings → Privacy & Security → Accessibility → SmartTile ✓

This is required to discover and move windows.

## Usage

| Shortcut | Action |
|----------|--------|
| `Ctrl+Option+A` | **Smart Arrange** — AI arranges all visible windows |
| `Ctrl+Option+G` | **Grid Tile** — show grid overlay for the frontmost window |
| `Ctrl+Option+S` | **Save Layout** — save current window positions for this app combination |

### Typical Workflow

1. Open your usual apps (editor, browser, terminal…)
2. Press `Ctrl+Option+A` — SmartTile arranges them using AI
3. Not happy with the result? Adjust windows manually
4. Press `Ctrl+Option+S` to save your preferred layout
5. Next time the **same apps** are open, SmartTile restores your saved layout without calling AI

### Grid Overlay

Press `Ctrl+Option+G` to open an interactive grid over your screen:

- Click and drag to select cells for the frontmost window
- Use `+`/`-` to change grid density
- Quick presets at the bottom: Full, Half, Third, Two-thirds
- Press `Esc` to dismiss

### Quick Layouts

Available from the menu bar under **Quick Layout**:

- 2 / 3 / 4 equal columns
- Left 2/3 + Right 1/3
- Left 1/3 + Right 2/3
- Left 1/2 + Right 1/2

## Project Structure

```
SmartTile/
├── SmartTileApp.swift       # Entry point, NSStatusItem menu, global shortcuts
├── Models.swift             # Data structures, window categories
├── WindowManager.swift      # AXUIElement window discovery & manipulation
├── LayoutEngine.swift       # LLM integration + grid fallback + normalization
├── LocalModelManager.swift  # llama.cpp process management & model download
├── PreferenceStore.swift    # Saved layout storage (exact app combination match)
├── OverlayView.swift        # Grid overlay UI
├── SettingsView.swift       # Settings window
├── ToastView.swift          # Notification toasts (pure AppKit)
├── HotkeyManager.swift      # Global keyboard shortcut registration
├── KeyRecorderView.swift    # Custom hotkey recorder
├── Info.plist               # LSUIElement = true (menu bar only)
└── SmartTile.entitlements   # No sandbox + network access
```

## How the AI Works

SmartTile runs a small language model (Qwen 2.5 1.5B, ~1 GB) locally via `llama-cli`. The model receives:

- List of open windows with their app names and categories
- Screen dimensions and usable area
- Instructions to arrange windows as columns, respecting window types

The model's output is post-processed to ensure windows fill the entire screen width, preserving the AI's relative width proportions.

**No data leaves your computer.** The AI runs entirely locally.

## Data Storage

All data is stored locally in `~/Library/Application Support/SmartTile/`:

| File | Purpose |
|------|---------|
| `settings.json` | App configuration |
| `preferences.json` | Saved layouts for specific app combinations |

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

## License

[MIT](LICENSE) — Michal Zielinski © 2026
