# SketchyBar Configuration

Personal macOS status bar configuration for [SketchyBar](https://felixkratz.github.io/SketchyBar/), paired with [AeroSpace](https://github.com/nikitabobko/AeroSpace) as the tiling window manager.

## Features

- Dual-monitor workspace management (6 workspaces: 1-3 for laptop, 4-6 for external display)
- Workspace pills showing app icons for each window
- Visual indication of focused window
- Auto-adapts when external monitor is connected/disconnected
- Clock and battery indicators on both displays
- Three color themes: Tokyo Night (default), Gruvbox, and Monokai Octagon

## Prerequisites

- macOS (tested on macOS 15.x)
- [Homebrew](https://brew.sh/) package manager
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) window manager

## Installation

### 1. Install SketchyBar

```bash
brew tap FelixKratz/formulae
brew install sketchybar
```

### 2. Install Required Font

The app icons in workspace pills require a special font:

```bash
brew install font-sketchybar-app-font
```

This font contains icon glyphs for macOS applications and is essential for displaying app icons correctly.

### 3. Install AeroSpace (if not already installed)

```bash
brew install --cask nikitabobko/tap/aerospace
```

### 4. Install Nerd Font

The configuration uses Hack Nerd Font for icons:

```bash
brew install --cask font-hack-nerd-font
```

### 5. Clone/Copy Configuration

Copy this configuration to your SketchyBar config directory:

```bash
# If you're cloning from a repo:
git clone <repo-url> ~/.config/sketchybar

# Or if you already have the files, ensure they're in:
# ~/.config/sketchybar/
```

### 6. Trust the SketchyBar Formula

Homebrew requires tap trust for third-party formulae:

```bash
brew trust --formula felixkratz/formulae/sketchybar
```

### 7. Copy AeroSpace Configuration

The configuration includes an `aerospace.toml` file that must be placed in the AeroSpace config directory:

```bash
# Copy the aerospace.toml to AeroSpace's config directory
cp ~/.config/sketchybar/aerospace.toml ~/.config/aerospace/aerospace.toml
```

### 8. Start SketchyBar Service

```bash
brew services start sketchybar
```

SketchyBar will now start automatically at login and stay running as a background service.

## Usage

### Reloading Configuration

After making changes to any configuration files:

```bash
# Fast reload (if service is running)
sketchybar --reload

# Or full restart
brew services restart sketchybar
```

### Reloading AeroSpace

After changing `aerospace.toml`:

```bash
aerospace reload-config

# Or use the keyboard shortcut (from service mode):
# alt-shift-; then esc
```

### Changing Themes

Edit `themes.sh` and change the `THEME` variable at the top:

```bash
THEME="tokyonight"  # Options: tokyonight, gruvbox, monokai_octagon
```

Then reload SketchyBar.

## Debugging

### View Logs

```bash
# Error log
tail -f /opt/homebrew/var/log/sketchybar/sketchybar.err.log

# Output log
tail -f /opt/homebrew/var/log/sketchybar/sketchybar.out.log
```

### Common Issues

#### Icons Not Showing

If app icons don't appear in workspace pills:

1. Ensure `sketchybar-app-font` is installed:
   ```bash
   brew install font-sketchybar-app-font
   ```

2. Reload SketchyBar:
   ```bash
   sketchybar --reload
   ```

3. Check if the font is available:
   ```bash
   ls ~/Library/Fonts/ | grep sketchybar
   ```

#### Service Won't Start

If you get "could not initialize daemon" errors:

1. Kill any existing processes:
   ```bash
   pkill sketchybar
   ```

2. Trust the formula if needed:
   ```bash
   brew trust --formula felixkratz/formulae/sketchybar
   ```

3. Restart the service:
   ```bash
   brew services restart sketchybar
   ```

#### Zombie Processes

If you see many zombie processes (e.g., old plugin scripts):

```bash
# Clean up zombie processes
pkill -f "front_app.sh"

# Restart SketchyBar
brew services restart sketchybar
```

## Project Structure

```
~/.config/sketchybar/
├── sketchybarrc              # Main configuration file (entry point)
├── themes.sh                 # Color themes (tokyonight, gruvbox, monokai_octagon)
├── aerospace.toml            # AeroSpace window manager config
├── plugins/
│   ├── workspace_pills.sh    # Single controller for all workspace pills
│   ├── icon_map.sh          # App name to icon glyph mapping
│   ├── clock.sh             # Clock widget
│   ├── battery.sh           # Battery indicator
│   └── display_adapt.sh     # Monitor detection and adaptation
├── CLAUDE.md                # Development/maintenance notes
└── README.md                # This file
```

## Architecture Overview

### Workspace Pills

Each workspace (1-6) is rendered as a "pill" containing:
- The workspace number
- Up to 10 app icon slots (configurable via `WORKSPACE_MAX_WINDOWS`)
- Visual highlighting for the focused window

All pills are controlled by a **single script** (`workspace_pills.sh`) for performance. This script:
- Runs on workspace changes and focus events
- Queries AeroSpace once per update
- Batches all SketchyBar updates into a single command
- Colors the focused window's icon differently

### Dual Monitor Setup

- **Display 1** (laptop): Workspaces 1-3
- **Display 2** (external): Workspaces 4-6

When an external monitor is disconnected, all items collapse to Display 1.

### Events

Custom SketchyBar events:
- `aerospace_workspace_change` - Triggered by AeroSpace when workspace changes
- `front_app_switched` - When the frontmost app changes
- `front_app_focus_changed` - When window focus changes within an app

## AeroSpace Key Bindings

Main modifier: `alt`

### Workspace Navigation
- `alt-1` through `alt-6` - Switch to workspace 1-6
- `alt-shift-1` through `alt-shift-6` - Move window to workspace 1-6

### Window Management
- `alt-h/j/k/l` - Focus left/down/up/right
- `alt-shift-h/j/k/l` - Move window left/down/up/right

### Service Mode
- `alt-shift-;` - Enter service mode
  - `esc` - Reload AeroSpace config
  - `f` - Float/unfloat window
  - `r` - Flatten workspace hierarchy

See `aerospace.toml` for complete key bindings.

## Credits

- [SketchyBar](https://github.com/FelixKratz/SketchyBar) by Felix Kratz
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) by Nikita Bobko
- [JankyBorders](https://github.com/FelixKratz/JankyBorders) by Felix Kratz (optional window borders)
