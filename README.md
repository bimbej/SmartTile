# SmartTile

**AI-powered window manager for macOS.** SmartTile uses a local LLM to analyze your open windows and arrange them intelligently — no cloud, no subscription, completely free.

Unlike traditional tiling window managers that use fixed rules, SmartTile understands *what* your windows are (editor, browser, terminal, chat) and arranges them accordingly. It learns your preferred layouts automatically — no manual saving needed.

## Features

- **Smart Arrange** — AI analyzes your open windows and suggests an optimal layout based on window types and screen size
- **Auto-Learn** — SmartTile watches how you adjust windows after arranging and remembers your preferred layouts automatically
- **Layout Templates** — learns abstract layout patterns (not per-app positions), so a "2 columns 50/50" layout works regardless of which specific apps are open
- **Grid Overlay** — interactive full-screen grid for precise manual window placement, with quick presets (halves, quarters, full)
- **Local AI** — runs entirely on your Mac using [llama.cpp](https://github.com/ggerganov/llama.cpp) with a small quantized model (~1 GB)
- **Auto-Update** — checks GitHub for new releases on startup, downloads and installs updates with one click
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

### Download

Download the latest DMG from [GitHub Releases](https://github.com/bimbej/SmartTile/releases/latest), open it, and drag SmartTile to your Applications folder.

SmartTile checks for updates automatically on launch. You can also check manually via the menu bar: **SmartTile > Check for Updates...**

### Build from Source

```bash
# Prerequisites: macOS 14+, Xcode 15+, XcodeGen
brew install xcodegen

# Clone and build
git clone https://github.com/bimbej/SmartTile.git
cd SmartTile
xcodegen generate
xcodebuild -scheme SmartTile -configuration Release build
```

### Set Up AI Model

```bash
# Install llama.cpp
brew install llama.cpp

# The app will guide you through downloading the AI model (~1 GB) in Settings
```

The grid overlay and fallback grid layout work without the AI model.

### Grant Permissions

On first launch, macOS will ask for **Accessibility** permission:

> System Settings > Privacy & Security > Accessibility > SmartTile

This is required to discover and move windows.

## Usage

| Shortcut | Action |
|----------|--------|
| `Ctrl+Option+A` | **Smart Arrange** — AI arranges all visible windows |
| `Ctrl+Option+G` | **Grid Tile** — show grid overlay for the frontmost window |

Shortcuts can be customized in Settings.

### Typical Workflow

1. Open your usual apps (editor, browser, terminal...)
2. Press `Ctrl+Option+A` — SmartTile arranges them
3. Not happy? Adjust windows manually — **SmartTile learns automatically**
4. Next time, your preferred layout is restored — even if you add or remove windows

No manual saving needed. SmartTile detects when you correct a layout and remembers the pattern. Templates are flexible — if no exact match exists for your window count, SmartTile picks the closest saved template and adapts it (extra slots stay empty, or extra windows split into existing slots).

### Grid Overlay

Press `Ctrl+Option+G` to open an interactive grid over your screen:

- Click and drag to select cells for the frontmost window
- Use `+`/`-` to change grid density
- Quick presets: Full, Left/Right ½, Top/Bottom ½, and four quarters
- Press `Esc` to dismiss

The grid covers the entire usable screen area — presets float on top without reducing the available grid space.

## Project Structure

```
SmartTile/
├── SmartTileApp.swift        # Entry point, NSStatusItem menu, global shortcuts
├── Models.swift              # Data structures, window categories
├── WindowManager.swift       # AXUIElement window discovery & manipulation
├── LayoutEngine.swift        # LLM layout + grid fallback (sqrt-based)
├── PreferenceStore.swift     # Template persistence + auto-learn polling
├── LocalModelManager.swift   # llama.cpp process management & model download
├── UpdateChecker.swift       # GitHub release check + self-update
├── OverlayView.swift         # Grid overlay UI (full-screen + floating presets)
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

The model output is post-processed with a 2D normalization algorithm that groups windows into rows and ensures full screen coverage. The grid fallback uses a sqrt-based algorithm (e.g., 4 windows = 2×2 grid, 6 windows = 3×2).

Over time, the AI is used less and less as SmartTile learns your preferences.

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

[MIT](LICENSE) — Bim-IT Michał Zieliński © 2026
