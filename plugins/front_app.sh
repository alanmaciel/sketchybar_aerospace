#!/bin/sh

source "$CONFIG_DIR/themes.sh"
source "$CONFIG_DIR/plugins/icon_map.sh"

FOCUSED_ID="$(aerospace list-windows --focused --format "%{window-id}" 2>/dev/null)"

FOCUS_ICON=""
ICONS=""
while IFS='|' read -r id app; do
  [ -z "$id" ] && continue
  __icon_map "$app"
  if [ "$id" = "$FOCUSED_ID" ]; then
    FOCUS_ICON="$icon_result"
  else
    ICONS="$ICONS $icon_result"
  fi
done <<EOF
$(aerospace list-windows --workspace focused --format "%{window-id}|%{app-name}" 2>/dev/null)
EOF

if [ -n "$FOCUS_ICON" ]; then
  sketchybar --set "$NAME" icon.drawing=on icon="$FOCUS_ICON" icon.color="$SPACE_ACTIVE_BORDER" label="${ICONS# }"
else
  sketchybar --set "$NAME" icon.drawing=off label="${ICONS# }"
fi
