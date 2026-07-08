# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal macOS status bar configuration for [SketchyBar](https://felixkratz.github.io/SketchyBar/), paired with [AeroSpace](https://github.com/nikitabobko/AeroSpace) as the tiling window manager. There is no build system — this is a set of shell scripts that SketchyBar executes directly.

## Running / reloading

SketchyBar runs as a Homebrew launchd service (`homebrew.mxcl.sketchybar`), started at login and kept alive (`KeepAlive`). There is no dev server or build step.

```sh
brew services restart sketchybar   # reload after editing sketchybarrc/themes.sh/plugins
sketchybar --reload                # faster reload if the service is already running
tail -f /opt/homebrew/var/log/sketchybar/sketchybar.{out,err}.log   # debug output
```

To sanity-check a plugin script in isolation, run it directly with the same env vars sketchybar would set (`NAME`, `SENDER`, `INFO`, etc. depend on the event — check the script for which ones it reads).

AeroSpace itself is configured in `aerospace.toml` and reloaded via `aerospace reload-config` (or the `esc` binding in service mode, see below).

## Architecture

**`sketchybarrc`** is the single entry point. It sources `themes.sh` for colors, sets bar-wide defaults, then declaratively adds every item via `sketchybar --add item ... --set ... --subscribe ...`. Item scripts are invoked with absolute paths built from `PLUGIN_DIR="$CONFIG_DIR/plugins"`. Read this file top-to-bottom to see the full bar layout — it's the map of what items exist and which plugin script backs each one.

**`themes.sh`** defines the color palette as a `case` over `$THEME` (`gruvbox` | `monokai_octagon` | `tokyonight`, default tokyonight), exporting variables like `SPACE_BG`, `SPACE_ACTIVE_BG`, `BAR_FG`, etc. Plugin scripts `source "$CONFIG_DIR/themes.sh"` themselves when they need to react to workspace state, since they run as separate processes and don't inherit sketchybarrc's shell state. `$CONFIG_DIR` doesn't need to be exported manually — sketchybar itself injects it into every script/event invocation, set to the absolute path of the directory holding the loaded config file (see `sketchybar-events.5`). It's only unset if you invoke a plugin script by hand outside of sketchybar, which is why `sketchybarrc` re-derives it with a `${CONFIG_DIR:-$HOME/.config/sketchybar}` fallback for its own top-level use.

**Dual-monitor workspace model** — this is the trickiest part of the config: AeroSpace workspaces `1-5` are assigned to the laptop display (monitor 2) and `6-0` to the external display (monitor 1), per `aerospace.toml`'s `[workspace-to-monitor-force-assignment]`. `sketchybarrc` creates two rows of items (`space1.1`..`space1.5` and `space2.6`..`space2.0`) each with `associated_display` set accordingly. Each space item's `script` is `plugins/aerospace_workspaces_per_monitor.sh <workspace_id> <other_monitor_id>` — it queries `aerospace list-monitors`/`list-workspaces` to determine focus and paints active/empty/inactive pill colors from `themes.sh`. `plugins/display_adapt.sh` runs on the `display_change` event (and once at startup) to collapse everything onto display 1 when only one monitor is connected, and to show/hide the `_ext`-suffixed duplicate items (`clock_ext`, `battery_ext`) when a second monitor is attached.

**`front_app`** is a single global item (`associated_display_mask=0`, shown on every display identically) that renders one glyph per *window* currently open in the focused AeroSpace workspace — not just the frontmost app's name. `plugins/front_app.sh` queries `aerospace list-windows --workspace focused --format "%{window-id}|%{app-name}"`, maps each app name to a glyph via `plugins/icon_map.sh`'s `__icon_map` function, and splits the result across the item's two fields: the window that matches `aerospace list-windows --focused` (the actually-focused window) goes in the `icon` field colored with `$SPACE_ACTIVE_BORDER` so it stands out, and every other window's glyph is concatenated into `label` in the default color. Both fields use the `sketchybar-app-font` cask (`icon.font`/`label.font` set in `sketchybarrc`). Multiple windows of the same app each get their own icon (no de-duplication). If you touch this, note it re-derives everything from `aerospace` on every event rather than trusting `$INFO`/`$FOCUSED_WORKSPACE` — simpler and avoids drift between the three subscribed events (`front_app_switched`, `aerospace_workspace_change`, `front_app_focus_changed`). The third one exists because macOS's frontmost-app notification (`front_app_switched`) doesn't fire when focus moves between two windows of the *same* app — `aerospace.toml`'s `on-focus-changed` callback fires on every AeroSpace focus change regardless of app and triggers the custom `front_app_focus_changed` SketchyBar event to cover that gap.

**Not currently wired up** — several plugin scripts exist under `plugins/` but are not referenced anywhere in `sketchybarrc` (no `--add item` uses them): `space.sh`, `aerospace.sh`, `aerospace_workspaces.sh` (superseded by `aerospace_workspaces_per_monitor.sh`), `wifi.sh`, `calendar_event.sh`, `things_todo.sh`. The latter two also `source "$CONFIG_DIR/colors.sh"`, a file that doesn't exist in this repo — they will error if invoked as-is. Treat these as either scratch/reference scripts or half-finished features; don't assume they're live, and check `sketchybarrc` before assuming any plugin script is actually reachable.

**`aerospace.toml`** — window manager config. Notable bits beyond the monitor assignment above: `after-startup-command` launches both `sketchybar` and [`borders`](https://github.com/FelixKratz/JankyBorders) (active/inactive window border coloring); `exec-on-workspace-change` triggers the custom `aerospace_workspace_change` SketchyBar event so bar items can react without polling. Keybindings use `alt` as the main modifier and a `service` mode (entered with `alt-shift-;`) for less-frequent operations (reload config, flatten tree, float toggle, join-with).
