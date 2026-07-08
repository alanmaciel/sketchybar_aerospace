#!/bin/sh

source "$CONFIG_DIR/themes.sh"
source "$CONFIG_DIR/plugins/icon_map.sh"

# Must match FRONT_APP_MAX_WINDOWS in sketchybarrc.
MAX_SLOTS=10

FOCUSED_ID="$(aerospace list-windows --focused --format "%{window-id}" 2>/dev/null)"

i=0
while IFS='|' read -r id app; do
  [ -z "$id" ] && continue
  [ "$i" -ge "$MAX_SLOTS" ] && break

  __icon_map "$app"

  if [ "$id" = "$FOCUSED_ID" ]; then
    COLOR="$SPACE_ACTIVE_BORDER"
  else
    COLOR="$BAR_FG"
  fi

  sketchybar --set "front_app.$i" \
    drawing=on \
    label="$icon_result" \
    label.color="$COLOR" \
    click_script="aerospace focus --window-id $id"

  i=$((i + 1))
done <<EOF
$(aerospace list-windows --workspace focused --format "%{window-id}|%{app-name}" 2>/dev/null)
EOF

while [ "$i" -lt "$MAX_SLOTS" ]; do
  sketchybar --set "front_app.$i" drawing=off
  i=$((i + 1))
done
