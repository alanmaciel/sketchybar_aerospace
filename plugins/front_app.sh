#!/bin/sh

workspace_is_empty() {
  # Count windows in the focused Aerospace workspace
  COUNT=$(aerospace list-windows --workspace focused --count 2>/dev/null || echo 0)
  [ "$COUNT" -eq 0 ]
}

case "$SENDER" in
  aerospace_workspace_change)
    # Whenever workspace changes, clear label if it has no windows
    if workspace_is_empty; then
      sketchybar --set "$NAME" label=""
    fi
    ;;

  front_app_switched)
    # When the front app changes, only show it if workspace has windows
    if workspace_is_empty; then
      sketchybar --set "$NAME" label=""
    else
      sketchybar --set "$NAME" label="$INFO"
    fi
    ;;
esac

