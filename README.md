# SmartTile

**AI-powered window manager for macOS.** SmartTile uses a local LLM to analyze your open windows and arrange them intelligently — no cloud, no subscription, completely free.

Unlike traditional tiling window managers that use fixed rules, SmartTile understands *what* your windows are (editor, browser, terminal...) and arranges them accordingly. It learns your preferred layouts automatically.

## Features

- **Smart Arrange** — AI analyzes your windows and arranges them based on type and screen size
- **Auto-Learn** — remembers how you adjust layouts and restores your preferences next time
- **Flexible Templates** — works even when window count changes; adapts the closest saved layout
- **Screen-Aware** — learns layouts separately for standard and ultrawide screens
- **Grid Overlay** — drag to select screen regions, or use quick presets (halves, quarters)
- **Local AI** — runs entirely on your Mac via [llama.cpp](https://github.com/ggerganov/llama.cpp), no data leaves your computer
- **Auto-Update** — one-click updates from GitHub Releases

## How It Works

```
┌────────────────┐     ┌──────────────┐     ┌─────────────────┐
│  Detect        │────>│  Classify    │────>│  Check learned  │
│  windows       │     │  (editor,    │     │  templates      │
│  (AXUIElement) │     │   terminal…) │     │                 │
└────────────────┘     └──────────────┘     └──────┬──────────┘
                                                   │
                                    ┌──────────────┴────────┐
                                    │                       │
                              Found learned            No match
                              template                      │
                                    │                       v
                                    │              ┌──────────────┐
                                    │              │  Local LLM   │
                                    │              │  (llama.cpp) │
                                    │              └──────┬───────┘
                                    │                     │
                                    v                     v
                              ┌──────────────────────────────┐
                              │ Apply layout via AXUIElement │
                              └──────────────┬───────────────┘
                                             │
                                             v
                              ┌──────────────────────────────┐
                              │  Auto-learn: watch for user  │
                              │  corrections, save template  │
                              └──────────────────────────────┘
```

## Installation

Download the latest DMG from [GitHub Releases](https://github.com/bimbej/SmartTile/releases/latest), open it, and drag SmartTile to Applications.

On first launch, grant **Accessibility** permission when prompted (required to move windows).

> **Note:** After auto-updates, macOS may ask for Accessibility permission again — this is a macOS limitation when the app binary changes.

### AI Model (optional)

```bash
brew install llama.cpp
# Then download the model (~1 GB) via SmartTile Settings
```

The grid overlay and fallback grid layout work without the AI model.

### Build from Source

```bash
brew install xcodegen
git clone https://github.com/bimbej/SmartTile.git
cd SmartTile
xcodegen generate
xcodebuild -scheme SmartTile -configuration Release build
```

## Usage

| Shortcut | Action |
|----------|--------|
| `Ctrl+Option+A` | **Smart Arrange** — AI arranges all visible windows |
| `Ctrl+Option+G` | **Grid Tile** — show grid overlay for the frontmost window |

Shortcuts can be customized in Settings.

### Workflow

1. Open your usual apps (editor, browser, terminal...)
2. Press `Ctrl+Option+A` — SmartTile arranges them
3. Not happy? Adjust windows manually — SmartTile learns automatically
4. Next time, your preferred layout is restored — even if you add or remove windows

### Grid Overlay

Press `Ctrl+Option+G` to open an interactive grid:

- Click and drag to select cells
- `+`/`-` to change grid density
- Quick presets: Full, Left/Right ½, Top/Bottom ½, and four quarters
- `Esc` to dismiss

## Contributing

Contributions welcome! Feel free to open issues or pull requests.

## License

[MIT](LICENSE) — Bim-IT Michał Zieliński © 2026
