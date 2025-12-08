#!/usr/bin/env bash

WORKSPACE_ID="$1"

# Workspace passed from Aerospace trigger
FOCUSED="$FOCUSED_WORKSPACE"

if [ "$WORKSPACE_ID" = "$FOCUSED" ]; then
  sketchybar --set "$NAME" background.drawing=on
else
  sketchybar --set "$NAME" background.drawing=off
fi
