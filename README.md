# SmartTile

**AI-powered window manager for macOS.** SmartTile uses a local LLM to analyze your open windows and arrange them intelligently — no cloud, no subscription, completely free.

Unlike traditional tiling window managers that use fixed rules, SmartTile understands *what* your windows are (editor, browser, terminal, chat) and arranges them accordingly. It learns your preferred layouts automatically — no manual saving needed.

## Features

- **Smart Arrange** — AI analyzes your open windows and suggests an optimal layout based on window types and screen size
- **Auto-Learn** — SmartTile watches how you adjust windows after arranging and remembers your preferred layouts automatically
- **Layout Templates** — learns abstract layout patterns (not per-app positions), so a "2 columns 50/50" layout works regardless of which specific apps are open
- **Category-Aware Placement** — tracks which types of apps you put where (e.g., editor always on the left, terminal on the right) and reproduces that across sessions
- **Grid Overlay** — Divvy-style interactive grid for precise manual window placement
- **Local AI** — runs entirely on your Mac using [llama.cpp](https://github.com/ggerganov/llama.cpp) with a small quantized model (~1 GB)
- **Menu bar app** — lives in the menu bar, no dock icon, zero clutter
- **Zero dependencies** — pure Swift/AppKit, no external frameworks

## How It Works

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  Detect      │────>│  Classify     │────>│  Check learned│
│  windows     │     │  (editor,     │     │  templates    │
│  (AXUIElement)│     │   terminal…) │     │              │
└─────────────┘     └──────────────┘     └──────┬───────┘
                                                │
                                    ┌───────────┴───────────┐
                                    │                       │
                              Found learned            No match
                              template                      │
                                    │                       v
                                    │              ┌──────────────┐
                                    │              │  Local LLM    │
                                    │              │  (llama.cpp)  │
                                    │              └──────┬───────┘
                                    │                     │
                                    v                     v
                              ┌──────────────────────────────┐
                              │  Apply layout via AXUIElement │
                              └──────────────┬───────────────┘
                                             │
                                             v
                              ┌──────────────────────────────┐
                              │  Auto-learn: watch for user   │
                              │  corrections, save template   │
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
git clone https://github.com/bimbej/SmartTile.git
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

> System Settings > Privacy & Security > Accessibility > SmartTile

This is required to discover and move windows.

## Usage

| Shortcut | Action |
|----------|--------|
| `Ctrl+Option+A` | **Smart Arrange** — AI arranges all visible windows |
| `Ctrl+Option+G` | **Grid Tile** — show grid overlay for the frontmost window |

### Typical Workflow

1. Open your usual apps (editor, browser, terminal...)
2. Press `Ctrl+Option+A` — SmartTile arranges them
3. Not happy? Adjust windows manually — **SmartTile learns automatically**
4. Next time you have the same number of windows, your preferred layout is restored

No manual saving needed. SmartTile detects when you correct a layout and remembers the pattern.

### How Learning Works

SmartTile learns **layout patterns**, not per-app positions:

- After Smart Arrange, it watches for ~30 seconds to see if you move any windows
- If you adjust the layout, it saves the corrected arrangement as a template
- Templates are keyed by window count (e.g., "my preferred 3-window layout")
- Each slot in a template tracks which categories of apps go there
- Over time, editors consistently land in the big slot, terminals in the small one, etc.

### Grid Overlay

Press `Ctrl+Option+G` to open an interactive grid over your screen:

- Click and drag to select cells for the frontmost window
- Use `+`/`-` to change grid density
- Quick presets at the bottom: Full, Half, Third, Two-thirds
- Press `Esc` to dismiss

## Project Structure

```
SmartTile/
├── SmartTileApp.swift        # Entry point, NSStatusItem menu, global shortcuts
├── Models.swift              # Data structures, window categories
├── WindowManager.swift       # AXUIElement window discovery & manipulation
├── LayoutEngine.swift        # Learned templates → LLM → grid fallback
├── PreferenceAnalyzer.swift  # Template extraction, matching, slot assignment
├── PreferenceStore.swift     # Template persistence + auto-learn polling
├── LocalModelManager.swift   # llama.cpp process management & model download
├── OverlayView.swift         # Grid overlay UI
├── SettingsView.swift        # Settings window
├── ToastView.swift           # Notification toasts (pure AppKit)
├── HotkeyManager.swift       # Global keyboard shortcut registration
├── KeyRecorderView.swift     # Custom hotkey recorder
├── Info.plist                # LSUIElement = true (menu bar only)
└── SmartTile.entitlements    # No sandbox + network access
```

## How the AI Works

SmartTile runs a small language model (Qwen 2.5 1.5B, ~1 GB) locally via `llama-cli`. The model receives:

- List of open windows with their app names and categories
- Screen dimensions and usable area
- Instructions to arrange windows optimally, respecting window types

The model's output is post-processed to ensure windows fill the entire screen. Over time, the AI is used less and less as SmartTile learns your preferences.

**No data leaves your computer.** The AI runs entirely locally.

## Data Storage

All data is stored locally in `~/Library/Application Support/SmartTile/`:

| File | Purpose |
|------|---------|
| `settings.json` | App configuration |
| `templates.json` | Learned layout templates |

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

## License

[MIT](LICENSE) — Bim-IT Michal Zielinski © 2026
