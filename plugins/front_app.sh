#!/bin/sh

source "$CONFIG_DIR/plugins/icon_map.sh"

ICONS=""
while IFS= read -r app; do
  [ -z "$app" ] && continue
  __icon_map "$app"
  ICONS="$ICONS $icon_result"
done <<EOF
$(aerospace list-windows --workspace focused --format "%{app-name}" 2>/dev/null)
EOF

sketchybar --set "$NAME" label="${ICONS# }"
