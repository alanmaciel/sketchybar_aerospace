# Repository Guidelines

## Project Structure & Module Organization

This repository is a personal macOS status-bar configuration for SketchyBar and AeroSpace; it has no build system or application source tree. `sketchybarrc` is the main entry point: it defines bar items, subscriptions, and absolute plugin paths. `themes.sh` supplies the shared palette, while `aerospace.toml` configures workspace assignments and emits SketchyBar events. Active item scripts live in `plugins/`, especially `workspace_pills.sh`, `clock.sh`, `battery.sh`, and `monitor_layout.sh`, with the shared workspace/monitor grouping rule in `monitor_groups.sh`. Check `sketchybarrc` before treating a plugin as live: several scripts in `plugins/` are retained as reference or unfinished work.

## Build, Test, and Development Commands

There is no compile or automated test command. Use the running macOS services as the verification surface:

```sh
sketchybar --reload                 # Reload configuration after config or plugin edits
brew services restart sketchybar    # Fully restart the SketchyBar service
aerospace reload-config             # Reload aerospace.toml after edits
tail -f /opt/homebrew/var/log/sketchybar/sketchybar.err.log
```

For a script-only syntax check, run `bash -n plugins/workspace_pills.sh`. When changing behavior, reload SketchyBar and exercise the affected event, such as switching workspaces, connecting a display, or clicking the clock/battery item.

## Coding Style & Naming Conventions

Use shell scripts with `#!/usr/bin/env bash` when arrays or Bash features are needed; preserve `#!/bin/sh` in portable existing scripts. Indent continuation arguments two spaces and quote variable expansions (`"$NAME"`). Keep item names aligned with their configuration, e.g. `space1.3.slot.0`. Use lowercase underscore-separated filenames and functions such as `update_pill`.

The workspace-pill controller batches SketchyBar updates intentionally. Preserve the one-query/one-batched-invocation design, and keep `WORKSPACE_MAX_WINDOWS` in `sketchybarrc`, `MAX_SLOTS` in `workspace_pills.sh`, and `WORKSPACE_MAX_WINDOWS` in `monitor_layout.sh` synchronized.

Never call `aerospace` directly for a query — use `aero()` from `monitor_groups.sh`, which bounds every call with a timeout. The CLI does not fail fast when AeroSpace.app is not running; it blocks on its socket indefinitely, and an unbounded call has already frozen the bar for days by wedging the pill lock, and corrupted `aerospace.toml` by writing out an empty monitor list. Treat "AeroSpace is unreachable" as a first-class case in anything that queries it: `load_monitors()` returns failure rather than guessing, and callers must gate on it plus `monitors_loaded_ok()` before writing to disk or repositioning a pill.

## Testing Guidelines

Validate edited scripts with `bash -n` where applicable, then reload and manually verify the relevant bar state. For workspace changes, check all three monitor counts (1, 2 and 3), focused-window highlighting, and empty workspaces. Monitor layouts can be exercised without the hardware by putting a stub `aerospace` on `PATH` that prints canned `list-monitors` rows; cover the built-in display not being monitor 1, the built-in being closed, and the CLI returning its "Can't connect to AeroSpace server" text instead of a monitor list. Do not assume unreferenced plugins execute successfully.

`bash -n` is not enough on its own here: the launchd service runs these scripts under stock `/bin/bash` 3.2, which has no associative arrays, so a hash map that works in your shell will fail silently in service context.

## Commit & Pull Request Guidelines

Use concise, imperative commit subjects such as `Refresh workspace pill icons instantly on window open/close` or `Reduce workspaces from 10 to 6`. Keep each commit focused. Pull requests should describe the visible configuration change, note required tools or fonts, link related issues when present, and include screenshots for layout or color changes.
