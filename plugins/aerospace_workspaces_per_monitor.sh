#!/usr/bin/env bash

WS_ID="$1"       # workspace id (e.g. "1", "2", "6", "7")
MONITOR_ID="$2"  # AeroSpace monitor index: "1", "2", ...

source "$CONFIG_DIR/themes.sh"
source "$CONFIG_DIR/plugins/icon_map.sh"

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

# Build the row of app icons for this workspace's windows, one icon per
# window (so an app with two windows open here shows its icon twice).
ICONS=""
while IFS= read -r app; do
  [ -z "$app" ] && continue
  __icon_map "$app"
  ICONS="$ICONS $icon_result"
done <<EOF
$(aerospace list-windows --workspace "$WS_ID" --format "%{app-name}" 2>/dev/null)
EOF
ICONS="${ICONS# }"

# No icons: drop the label entirely and give its right-side padding back to
# the icon, otherwise the reserved (empty) label space pushes the number off
# center in the pill.
if [ -z "$ICONS" ]; then
  LABEL_DRAWING=off
  ICON_PADDING_RIGHT=10
  LABEL_PADDING_LEFT=0
  LABEL_PADDING_RIGHT=0
else
  LABEL_DRAWING=on
  ICON_PADDING_RIGHT=8
  LABEL_PADDING_LEFT=4
  LABEL_PADDING_RIGHT=10
fi

if [ "$WS_ID" = "$FOCUSED_ON_MONITOR" ]; then
  # Active workspace
  sketchybar --animate sin 25 --set "$NAME" \
    background.drawing=on \
    background.color="$SPACE_ACTIVE_BG" \
    background.border_width=2 \
    background.border_color="$SPACE_ACTIVE_BORDER" \
    icon.color="$SPACE_ACTIVE_FG" \
    label.color="$SPACE_ACTIVE_FG" \
    label="$ICONS"
elif [ -z "$ICONS" ]; then
  # Empty workspace
  sketchybar --animate sin 25 --set "$NAME" \
    background.drawing=on \
    background.color="$SPACE_EMPTY_BG" \
    background.border_width=0 \
    background.border_color="$SPACE_EMPTY_BG" \
    icon.color="$SPACE_EMPTY_FG" \
    label.color="$SPACE_EMPTY_FG" \
    label="$ICONS"
else
  # Inactive workspace with windows
  sketchybar --animate sin 25 --set "$NAME" \
    background.drawing=on \
    background.color="$SPACE_BG" \
    background.border_width=0 \
    background.border_color="$SPACE_BG" \
    icon.color="$SPACE_FG" \
    label.color="$SPACE_FG" \
    label="$ICONS"
fi

sketchybar --set "$NAME" \
  label.drawing="$LABEL_DRAWING" \
  icon.padding_right="$ICON_PADDING_RIGHT" \
  label.padding_left="$LABEL_PADDING_LEFT" \
  label.padding_right="$LABEL_PADDING_RIGHT"
