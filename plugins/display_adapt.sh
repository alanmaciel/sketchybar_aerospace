#!/usr/bin/env bash

# How many monitors according to AeroSpace?
if command -v aerospace >/dev/null 2>&1; then
  MON_COUNT="$(aerospace list-monitors 2>/dev/null | grep '|' | wc -l)"
else
  MON_COUNT=1
fi

SPACE_MON1=("1" "2" "3" "4" "5")
SPACE_MON2=("6" "7" "8" "9" "0")

if [ "$MON_COUNT" -le 1 ]; then
  # ===== SINGLE DISPLAY =====

  # All workspaces on display 1
  for sid in "${SPACE_MON1[@]}"; do
    sketchybar --set "space1.$sid" associated_display=1 drawing=on
  done
  for sid in "${SPACE_MON2[@]}"; do
    sketchybar --set "space2.$sid" associated_display=1 drawing=on
  done

  # Right side: show only base items on display 1, hide ext copies
  sketchybar --set clock   associated_display=1 drawing=on
  # sketchybar --set wifi    associated_display=1 drawing=on
  sketchybar --set battery associated_display=1 drawing=on

  sketchybar --set clock_ext   drawing=off
  # sketchybar --set wifi_ext    drawing=off
  sketchybar --set battery_ext drawing=off

else
  # ===== MULTI DISPLAY =====

  # Laptop row 1–5 on display 1
  for sid in "${SPACE_MON1[@]}"; do
    sketchybar --set "space1.$sid" associated_display=1 drawing=on
  done

  # External row 6–0 on display 2
  for sid in "${SPACE_MON2[@]}"; do
    sketchybar --set "space2.$sid" associated_display=2 drawing=on
  done

  # Right side pills on both displays
  sketchybar --set clock   associated_display=1 drawing=on
  # sketchybar --set wifi    associated_display=1 drawing=on
  sketchybar --set battery associated_display=1 drawing=on

  sketchybar --set clock_ext   associated_display=2 drawing=on
  # sketchybar --set wifi_ext    associated_display=2 drawing=on
  sketchybar --set battery_ext associated_display=2 drawing=on
fi
