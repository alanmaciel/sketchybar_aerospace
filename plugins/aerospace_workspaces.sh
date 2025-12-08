#!/usr/bin/env bash

WS_ID="$1"

# FOCUSED_WORKSPACE is passed from AeroSpace via exec-on-workspace-change
FOCUSED="${FOCUSED_WORKSPACE:-$FOCUSED}"

# Fallback: ask AeroSpace directly if env is missing
if [ -z "$FOCUSED" ]; then
  FOCUSED="$(aerospace list-workspaces --focused 2>/dev/null | head -n 1)"
fi

# Load theme colors
source "$CONFIG_DIR/themes.sh"

if [ "$WS_ID" = "$FOCUSED" ]; then
  # Active workspace: animate into active colors
  sketchybar --animate sin 25 --set "$NAME" \
    background.drawing=on \
    background.color="$SPACE_ACTIVE_BG" \
    background.border_width=2 \
    background.border_color="$SPACE_ACTIVE_BORDER" \
    label.color="$SPACE_ACTIVE_FG"
else
  # Inactive workspace: animate back to base pill
  sketchybar --animate sin 25 --set "$NAME" \
    background.drawing=on \
    background.color="$SPACE_BG" \
    background.border_width=0 \
    background.border_color="$SPACE_BG" \
    label.color="$SPACE_FG"
fi
