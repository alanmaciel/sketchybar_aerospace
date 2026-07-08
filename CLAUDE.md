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

**Dual-monitor workspace model** — this is the trickiest part of the config: AeroSpace workspaces `1-3` are assigned to the laptop display (monitor 2) and `4-6` to the external display (monitor 1), per `aerospace.toml`'s `[workspace-to-monitor-force-assignment]`. `sketchybarrc` creates two rows of items (`space1.1`..`space1.3` and `space2.4`..`space2.6`) each with `associated_display` set accordingly.

**Workspace pills** — each pill (e.g. `space1.3`) is a `sketchybar --add bracket` merging a `space1.3.num` item (the workspace digit, shown via `icon`) with a fixed pool of `space1.3.slot.0`..`slot.9` items (`WORKSPACE_MAX_WINDOWS` in `sketchybarrc`, must match `MAX_SLOTS` in the plugin) — one slot per potential window in that workspace, each showing an app glyph (`sketchybar-app-font`, mapped via `plugins/icon_map.sh`'s `__icon_map`) with its own `click_script="aerospace focus --window-id <id>"`. Members default to a transparent background; the bracket itself carries `background.color`/`border`/`corner_radius`, so the group renders as one pill. A trailing `space1.3.gap` spacer item (fixed `width=8`) sits after each bracket — brackets ignore their own `padding_left`/`padding_right` for inter-item spacing (verified empirically), so a spacer is the only way to put visible space between two pills.

All 10 pills are driven by a *single* invisible controller item, `workspace_pills` (script `plugins/workspace_pills.sh`, subscribed to `aerospace_workspace_change`, `front_app_switched`, and `front_app_focus_changed`) — it is not one script per pill. On each run it fetches `aerospace list-monitors`, the visible workspace per monitor, the focused window id, and **one** `aerospace list-windows --all` call bucketed by workspace, then loops over all 10 workspace ids in-process, coloring the globally-focused window's icon slot with `SPACE_FOCUSED_FG` and every other slot with the pill's active/empty/inactive state color from `themes.sh`. Every `sketchybar --set` for the whole run is accumulated into one `ARGS` array and issued as a single batched `sketchybar` invocation at the end, rather than one process per property change — with 10 pills × ~10 slots that's the difference between roughly a dozen and roughly a hundred process spawns per workspace switch, and was a deliberate fix for perceptibly slow pill updates. A single-pill-per-script design was tried first and discarded for exactly that reason: each pill independently re-querying AeroSpace meant ~40 CLI round-trips for one workspace change.

Note: macOS's stock `/bin/bash` (3.2, no associative arrays) is what `#!/usr/bin/env bash` resolves to when sketchybar runs as a launchd service — there's no Homebrew bash on this machine's `PATH` in that context. `workspace_pills.sh` therefore stores the bucketed `list-windows --all` output as one grep-able string, not a hash map.

`plugins/display_adapt.sh` runs on the `display_change` event (and once at startup) to collapse everything onto display 1 when only one monitor is connected, and to show/hide the `_ext`-suffixed duplicate items (`clock_ext`, `battery_ext`) when a second monitor is attached.

**Not currently wired up** — several plugin scripts exist under `plugins/` but are not referenced anywhere in `sketchybarrc` (no `--add item` uses them): `space.sh`, `aerospace.sh`, `aerospace_workspaces.sh` (superseded by `workspace_pills.sh`), `wifi.sh`, `calendar_event.sh`, `things_todo.sh`. The latter two also `source "$CONFIG_DIR/colors.sh"`, a file that doesn't exist in this repo — they will error if invoked as-is. Treat these as either scratch/reference scripts or half-finished features; don't assume they're live, and check `sketchybarrc` before assuming any plugin script is actually reachable.

**`aerospace.toml`** — window manager config. Notable bits beyond the monitor assignment above: `after-startup-command` launches both `sketchybar` and [`borders`](https://github.com/FelixKratz/JankyBorders) (active/inactive window border coloring); `exec-on-workspace-change` triggers the custom `aerospace_workspace_change` SketchyBar event so bar items can react without polling. Keybindings use `alt` as the main modifier and a `service` mode (entered with `alt-shift-;`) for less-frequent operations (reload config, flatten tree, float toggle, join-with).
