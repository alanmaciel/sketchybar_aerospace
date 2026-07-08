#!/bin/sh

source "$CONFIG_DIR/themes.sh"
source "$CONFIG_DIR/plugins/icon_map.sh"

# Must match FRONT_APP_MAX_WINDOWS in sketchybarrc.
MAX_SLOTS=10

FOCUSED_ID="$(aerospace list-windows --focused --format "%{window-id}" 2>/dev/null)"

# Fills slot pool $1 (e.g. "front_app" or "front_app_ext") with the windows
# of workspace $2, hiding any unused slots.
fill_pool() {
  POOL="$1"
  WS_ID="$2"

  i=0
  if [ -n "$WS_ID" ]; then
    while IFS='|' read -r id app; do
      [ -z "$id" ] && continue
      [ "$i" -ge "$MAX_SLOTS" ] && break

      __icon_map "$app"

      if [ "$id" = "$FOCUSED_ID" ]; then
        COLOR="$SPACE_ACTIVE_BORDER"
      else
        COLOR="$BAR_FG"
      fi

      sketchybar --set "$POOL.$i" \
        drawing=on \
        label="$icon_result" \
        label.color="$COLOR" \
        click_script="aerospace focus --window-id $id"

      i=$((i + 1))
    done <<EOF
$(aerospace list-windows --workspace "$WS_ID" --format "%{window-id}|%{app-name}" 2>/dev/null)
EOF
  fi

  while [ "$i" -lt "$MAX_SLOTS" ]; do
    sketchybar --set "$POOL.$i" drawing=off
    i=$((i + 1))
  done
}

MON_COUNT="$(aerospace list-monitors 2>/dev/null | grep '|' | wc -l)"

if [ "$MON_COUNT" -le 1 ]; then
  # Single-monitor setup: just use the focused workspace, keep the
  # external-display pool empty.
  FOCUSED_WS="$(aerospace list-workspaces --focused 2>/dev/null | head -n 1)"
  fill_pool front_app "$FOCUSED_WS"
  fill_pool front_app_ext ""
else
  # Multi-monitor: each pool shows the workspace actually visible on its own
  # display. Laptop display (sketchybar display 1) is AeroSpace monitor 2;
  # external display (sketchybar display 2) is AeroSpace monitor 1 — same
  # mapping used by aerospace_workspaces_per_monitor.sh.
  WS_LAPTOP="$(aerospace list-workspaces --monitor 2 --visible 2>/dev/null | head -n 1)"
  WS_EXTERNAL="$(aerospace list-workspaces --monitor 1 --visible 2>/dev/null | head -n 1)"

  fill_pool front_app "$WS_LAPTOP"
  fill_pool front_app_ext "$WS_EXTERNAL"
fi
