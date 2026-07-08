#!/usr/bin/env bash

# How many monitors according to AeroSpace?
if command -v aerospace >/dev/null 2>&1; then
  MON_COUNT="$(aerospace list-monitors 2>/dev/null | grep '|' | wc -l)"
else
  MON_COUNT=1
fi

SPACE_MON1=("1" "2" "3" "4" "5")
SPACE_MON2=("6" "7" "8" "9" "0")

# Must match WORKSPACE_MAX_WINDOWS in sketchybarrc.
WORKSPACE_MAX_WINDOWS=10

# A pill's bracket has its own associated_display, but its member items
# (num, slot.0..N, gap) each carry their own independent one too — setting
# it on the bracket alone leaves the members pinned to whichever display
# they were created on, so they never render once that display is gone.
set_pill_display() {
  local prefix="$1" sid="$2" display="$3"
  sketchybar --set "$prefix.$sid" associated_display="$display" drawing=on
  sketchybar --set "$prefix.$sid.num" associated_display="$display"
  sketchybar --set "$prefix.$sid.gap" associated_display="$display"
  for i in $(seq 0 $((WORKSPACE_MAX_WINDOWS - 1))); do
    sketchybar --set "$prefix.$sid.slot.$i" associated_display="$display"
  done
}

if [ "$MON_COUNT" -le 1 ]; then
  # ===== SINGLE DISPLAY =====

  # All workspaces on display 1
  for sid in "${SPACE_MON1[@]}"; do
    set_pill_display space1 "$sid" 1
  done
  for sid in "${SPACE_MON2[@]}"; do
    set_pill_display space2 "$sid" 1
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
    set_pill_display space1 "$sid" 1
  done

  # External row 6–0 on display 2
  for sid in "${SPACE_MON2[@]}"; do
    set_pill_display space2 "$sid" 2
  done

  # Right side pills on both displays
  sketchybar --set clock   associated_display=1 drawing=on
  # sketchybar --set wifi    associated_display=1 drawing=on
  sketchybar --set battery associated_display=1 drawing=on

  sketchybar --set clock_ext   associated_display=2 drawing=on
  # sketchybar --set wifi_ext    associated_display=2 drawing=on
  sketchybar --set battery_ext associated_display=2 drawing=on
fi
