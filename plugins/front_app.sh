#!/bin/sh

workspace_is_empty() {
  # Count windows in the focused Aerospace workspace
  COUNT=$(aerospace list-windows --workspace focused --count 2>/dev/null || echo 0)
  [ "$COUNT" -eq 0 ]
}

case "$SENDER" in
  aerospace_workspace_change)
    # Whenever workspace changes, update or clear label based on workspace state
    if workspace_is_empty; then
      sketchybar --set "$NAME" label=""
    else
      # Get the current front app name
      FRONT_APP=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
      sketchybar --set "$NAME" label="$FRONT_APP"
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

