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

**1/2/3-monitor adaptive workspace model** — this is the trickiest part of the config: there are 6 AeroSpace workspaces total, and how they're grouped onto physical monitors depends on how many are connected right now, with the built-in display always pinned to position 1 whenever it's connected (position ≠ AeroSpace's own monitor numbering, see below):

- 1 monitor connected: all of `1-6` on it.
- 2 monitors: `1-3` on position 1, `4-6` on position 2.
- 3 monitors: `1-2` on position 1, `3-4` on position 2, `5-6` on position 3.

If the built-in is closed/disconnected, position 1 just falls to whichever external is leftmost — the workspace split above doesn't change, only which physical monitor plays position 1.

This "position" concept (`plugins/monitor_groups.sh`) has two parts:
- `workspace_target_monitor(ws, mon_count)` — the grouping rule above, workspace → position (1/2/3).
- `build_pos_to_monid(mon_count)` — populates `POS_TO_MONID[]`, position → actual AeroSpace monitor-id, by querying `aerospace list-monitors` for a name matching `*built-in*` and forcing it to position 1; the remaining monitors keep AeroSpace's left-to-right order (this is name-based, not hardcoded to a specific model, so it survives hardware changes).

Both scripts source `monitor_groups.sh` so they can't drift apart, but each still needs its own extra mapping on top of `POS_TO_MONID`, driven by `plugins/monitor_layout.sh` (on the `display_change` event and once at startup):

1. **AeroSpace's own workspace routing** — `aerospace.toml`'s `[workspace-to-monitor-force-assignment]` block (between the `BEGIN/END WORKSPACE-MONITOR ASSIGNMENT` markers) is *generated*, not hand-maintained. `monitor_layout.sh` rewrites it (workspace → `POS_TO_MONID[position]`, i.e. an actual AeroSpace monitor-id) and runs `aerospace reload-config` whenever the generated block actually changes — AeroSpace has no monitor-count-conditional config syntax of its own, so this can't be done declaratively in the TOML alone.
2. **Which sketchybar display each pill renders on** — `associated_display` on each `space.N` bracket (and its member items). This needs a *second* bridge, `SB_DISPLAY[]` (AeroSpace monitor-id → sketchybar display), because sketchybar's own numbering disagrees with AeroSpace's in yet a different way: sketchybar always puts the *main* display at `associated_display=1` and numbers the rest 2..N in left-to-right order, regardless of physical position — verified empirically (a 3-monitor setup where the laptop, main but physically rightmost, is AeroSpace monitor 3 but sketchybar display 1). `monitor_layout.sh` builds `SB_DISPLAY[]` at runtime from `aerospace list-monitors`' `monitor-is-main` field rather than hardcoding it.

So placing a pill is a two-hop lookup: `workspace_target_monitor` → position → `POS_TO_MONID` → AeroSpace monitor-id → `SB_DISPLAY` → sketchybar display.

**Workspace pills** — each pill (e.g. `space.3`) is a `sketchybar --add bracket` merging a `space.3.num` item (the workspace digit, shown via `icon`) with a fixed pool of `space.3.slot.0`..`slot.9` items (`WORKSPACE_MAX_WINDOWS` in `sketchybarrc`, must match `MAX_SLOTS` in the plugin) — one slot per potential window in that workspace, each showing an app glyph (`sketchybar-app-font`, mapped via `plugins/icon_map.sh`'s `__icon_map`) with its own `click_script="aerospace focus --window-id <id>"`. Members default to a transparent background; the bracket itself carries `background.color`/`border`/`corner_radius`, so the group renders as one pill. A trailing `space.3.gap` spacer item (fixed `width=8`) sits after each bracket — brackets ignore their own `padding_left`/`padding_right` for inter-item spacing (verified empirically), so a spacer is the only way to put visible space between two pills.

All 6 pills are driven by a *single* invisible controller item, `workspace_pills` (script `plugins/workspace_pills.sh`, subscribed to `aerospace_workspace_change`, `front_app_switched`, and `front_app_focus_changed`) — it is not one script per pill. On each run it fetches `aerospace list-monitors`, the visible workspace per monitor, the focused window id, and **one** `aerospace list-windows --all` call bucketed by workspace, then loops over all 6 workspace ids in-process, coloring the globally-focused window's icon slot with `SPACE_FOCUSED_FG` and every other slot with the pill's active/empty/inactive state color from `themes.sh`. Every `sketchybar --set` for the whole run is accumulated into one `ARGS` array and issued as a single batched `sketchybar` invocation at the end, rather than one process per property change — with 6 pills × ~10 slots that's the difference between roughly a dozen and roughly a hundred process spawns per workspace switch, and was a deliberate fix for perceptibly slow pill updates. A single-pill-per-script design was tried first and discarded for exactly that reason: each pill independently re-querying AeroSpace meant ~40 CLI round-trips for one workspace change.

Note: macOS's stock `/bin/bash` (3.2, no associative arrays) is what `#!/usr/bin/env bash` resolves to when sketchybar runs as a launchd service — there's no Homebrew bash on this machine's `PATH` in that context. `workspace_pills.sh` therefore stores the bucketed `list-windows --all` output as one grep-able string, not a hash map; it uses regular indexed arrays (fine in bash 3.2) to hold the focused workspace per monitor (up to 3).

`plugins/monitor_layout.sh` runs on the `display_change` event (and once at startup) and does everything described above: regenerates `aerospace.toml`'s monitor assignment, repositions all 6 workspace pills, and shows/hides the `_ext`/`_ext2`-suffixed duplicate right-side items (`clock_ext`/`battery_ext` for a 2nd monitor, `clock_ext2`/`battery_ext2` for a 3rd) depending on how many monitors are connected. It also re-runs `workspace_pills.sh` at the end, since a monitor being plugged/unplugged doesn't fire any of the AeroSpace events that script normally subscribes to.

**Not currently wired up** — several plugin scripts exist under `plugins/` but are not referenced anywhere in `sketchybarrc` (no `--add item` uses them): `space.sh`, `aerospace.sh`, `aerospace_workspaces.sh` (superseded by `workspace_pills.sh`), `wifi.sh`, `calendar_event.sh`, `things_todo.sh`. The latter two also `source "$CONFIG_DIR/colors.sh"`, a file that doesn't exist in this repo — they will error if invoked as-is. Treat these as either scratch/reference scripts or half-finished features; don't assume they're live, and check `sketchybarrc` before assuming any plugin script is actually reachable.

**`aerospace.toml`** — window manager config. Notable bits beyond the monitor assignment above: `after-startup-command` launches both `sketchybar` and [`borders`](https://github.com/FelixKratz/JankyBorders) (active/inactive window border coloring); `exec-on-workspace-change` triggers the custom `aerospace_workspace_change` SketchyBar event so bar items can react without polling. Keybindings use `alt` as the main modifier and a `service` mode (entered with `alt-shift-;`) for less-frequent operations (reload config, flatten tree, float toggle, join-with).
