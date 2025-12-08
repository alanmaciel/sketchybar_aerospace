#!/usr/bin/env bash

MODE="$1"   # empty on normal update, "click" when icon is clicked

info="$(pmset -g batt | grep -Eo '[0-9]+%.*')"
percent="$(echo "$info" | grep -Eo '[0-9]+' | head -1)"

# Choose icon based on percentage
icon=""  # default empty
if [ "$percent" -ge 80 ] 2>/dev/null; then
  icon=""
elif [ "$percent" -ge 60 ] 2>/dev/null; then
  icon=""
elif [ "$percent" -ge 40 ] 2>/dev/null; then
  icon=""
elif [ "$percent" -ge 20 ] 2>/dev/null; then
  icon=""
fi

if [ "$MODE" = "click" ]; then
  # Try to extract remaining time from pmset output
  # Example fragment: "(3:12 remaining)"
  time_raw="$(pmset -g batt | grep -Eo '\([0-9]+:[0-9]+ remaining\)' | head -1)"
  time="$(echo "$time_raw" | sed -E 's/[()]//g; s/ remaining//')"
  [ -z "$time" ] && time="estimating…"

  sketchybar --set "$NAME" icon="$icon" label="$time"
else
  # Normal periodic update: show percent
  [ -z "$percent" ] && percent="?"
  sketchybar --set "$NAME" icon="$icon" label="${percent}%"
fi
