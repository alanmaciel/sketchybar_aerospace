#!/usr/bin/env bash

WS_ID="$1"       # workspace id (e.g. "1", "2", "6", "7")
MONITOR_ID="$2"  # AeroSpace monitor index: "1", "2", ...

# How many monitors does AeroSpace see?
MON_COUNT="$(aerospace list-monitors 2>/dev/null | grep '|' | wc -l)"

if [ "$MON_COUNT" -le 1 ]; then
  # Single-monitor setup: just use the focused workspace
  FOCUSED_ON_MONITOR="$(aerospace list-workspaces --focused 2>/dev/null | head -n 1)"
else
  # Multi-monitor: use the workspace visible on this monitor
  FOCUSED_ON_MONITOR="$(
    aerospace list-workspaces --monitor "$MONITOR_ID" --visible 2>/dev/null | head -n 1
  )"
fi

# Load theme colors
source "$CONFIG_DIR/themes.sh"

if [ "$WS_ID" = "$FOCUSED_ON_MONITOR" ]; then
  sketchybar --animate sin 25 --set "$NAME" \
    background.drawing=on \
    background.color="$SPACE_ACTIVE_BG" \
    background.border_width=2 \
    background.border_color="$SPACE_ACTIVE_BORDER" \
    label.color="$SPACE_ACTIVE_FG"
else
  sketchybar --animate sin 25 --set "$NAME" \
    background.drawing=on \
    background.color="$SPACE_BG" \
    background.border_width=0 \
    background.border_color="$SPACE_BG" \
    label.color="$SPACE_FG"
fi
