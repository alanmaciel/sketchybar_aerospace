#!/usr/bin/env bash

WS_ID="$1"       # workspace id (e.g. "1", "2", "6", "7")
MONITOR_ID="$2"  # AeroSpace monitor index: "1", "2", ...

source "$CONFIG_DIR/themes.sh"
source "$CONFIG_DIR/plugins/icon_map.sh"

# Must match WORKSPACE_MAX_WINDOWS in sketchybarrc.
MAX_SLOTS=10

# $NAME is the "num" item this script is attached to, e.g. "space1.3.num".
BRACKET_NAME="${NAME%.num}"
SLOT_PREFIX="$BRACKET_NAME.slot"

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

FOCUSED_WINDOW_ID="$(aerospace list-windows --focused --format "%{window-id}" 2>/dev/null)"

# Fill one slot per window with that app's icon (so an app with two windows
# open here shows its icon twice), remembering which slot is the globally
# focused window so it can be colored differently below.
FOCUSED_SLOT=""
i=0
while IFS='|' read -r id app; do
  [ -z "$id" ] && continue
  [ "$i" -ge "$MAX_SLOTS" ] && break

  __icon_map "$app"

  sketchybar --set "$SLOT_PREFIX.$i" \
    drawing=on \
    label="$icon_result" \
    click_script="aerospace focus --window-id $id"

  [ "$id" = "$FOCUSED_WINDOW_ID" ] && FOCUSED_SLOT="$i"

  i=$((i + 1))
done <<EOF
$(aerospace list-windows --workspace "$WS_ID" --format "%{window-id}|%{app-name}" 2>/dev/null)
EOF
WINDOW_COUNT="$i"

while [ "$i" -lt "$MAX_SLOTS" ]; do
  sketchybar --set "$SLOT_PREFIX.$i" drawing=off
  i=$((i + 1))
done

if [ "$WS_ID" = "$FOCUSED_ON_MONITOR" ]; then
  # Active workspace
  STATE_FG="$SPACE_ACTIVE_FG"
  BG_COLOR="$SPACE_ACTIVE_BG"
  BORDER_WIDTH=2
  BORDER_COLOR="$SPACE_ACTIVE_BORDER"
elif [ "$WINDOW_COUNT" -eq 0 ]; then
  # Empty workspace
  STATE_FG="$SPACE_EMPTY_FG"
  BG_COLOR="$SPACE_EMPTY_BG"
  BORDER_WIDTH=0
  BORDER_COLOR="$SPACE_EMPTY_BG"
else
  # Inactive workspace with windows
  STATE_FG="$SPACE_FG"
  BG_COLOR="$SPACE_BG"
  BORDER_WIDTH=0
  BORDER_COLOR="$SPACE_BG"
fi

# Color each visible icon: the focused window gets a dedicated highlight
# color, every other icon in this pill gets the workspace's state color.
# The last visible icon also gets the pill's right-edge padding back, since
# no separator is used between icons (a plain space renders too wide in the
# icon font — the glyphs already carry their own side bearing).
j=0
while [ "$j" -lt "$WINDOW_COUNT" ]; do
  if [ "$j" = "$FOCUSED_SLOT" ]; then
    ICON_COLOR="$SPACE_FOCUSED_FG"
  else
    ICON_COLOR="$STATE_FG"
  fi

  if [ "$j" -eq "$((WINDOW_COUNT - 1))" ]; then
    PADDING_RIGHT=10
  else
    PADDING_RIGHT=0
  fi

  sketchybar --set "$SLOT_PREFIX.$j" label.color="$ICON_COLOR" label.padding_right="$PADDING_RIGHT"
  j=$((j + 1))
done

# No icons: mirror the number's left padding on its right so it stays
# centered; otherwise give it a wider gap before the first icon.
if [ "$WINDOW_COUNT" -eq 0 ]; then
  NUM_PADDING_RIGHT=10
else
  NUM_PADDING_RIGHT=16
fi

sketchybar --animate sin 25 --set "$BRACKET_NAME" \
  background.drawing=on \
  background.color="$BG_COLOR" \
  background.border_width="$BORDER_WIDTH" \
  background.border_color="$BORDER_COLOR"

sketchybar --set "$NAME" icon.color="$STATE_FG" icon.padding_right="$NUM_PADDING_RIGHT"
