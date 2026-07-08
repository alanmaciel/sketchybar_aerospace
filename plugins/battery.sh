#!/usr/bin/env bash

MODE="$1"   # empty on normal update, "click" when icon is clicked

batt_info="$(pmset -g batt)"
percent="$(echo "$batt_info" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"

# Match only the actively-charging state ("NN%; charging; H:MM remaining").
# A plain \bcharging\b would wrongly match the "AC attached; not charging"
# state too (plugged in, but not actively charging — e.g. macOS holding off
# at a battery-health charge limit).
charging=false
echo "$batt_info" | grep -Eq '; charging;' && charging=true

ac_attached=false
echo "$batt_info" | grep -q "AC Power" && ac_attached=true

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

if $charging; then
  icon="$icon"
elif $ac_attached; then
  icon="$icon"
fi

if [ "$MODE" = "click" ]; then
  # Try to extract remaining time from pmset output
  # Example fragment: "(3:12 remaining)"
  time_raw="$(echo "$batt_info" | grep -Eo '\([0-9]+:[0-9]+ remaining\)' | head -1)"
  time="$(echo "$time_raw" | sed -E 's/[()]//g; s/ remaining//')"
  [ -z "$time" ] && time="estimating…"

  sketchybar --set "$NAME" icon="$icon" label="$time"
else
  # Normal periodic update: show percent
  [ -z "$percent" ] && percent="?"
  sketchybar --set "$NAME" icon="$icon" label="${percent}%"
fi
