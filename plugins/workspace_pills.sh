#!/usr/bin/env bash

# Single controller for all workspace pills (space1.1..5, space2.6..0).
# Runs once per event and fans out to every pill internally, instead of
# each pill running its own copy of this script — that used to mean ~40
# separate `aerospace` CLI round-trips (list-monitors/list-workspaces/
# list-windows, several per pill) for a single workspace change, which is
# what made switching workspaces feel sluggish. Here every needed fact is
# fetched exactly once and reused for all 10 pills.
#
# The `sketchybar --set` calls are batched into one invocation at the end
# too (ARGS accumulator) rather than issued one at a time — each is its own
# process talking to the sketchybar daemon over its socket, so ~120
# individual calls (10 pills x up to 12 property updates each) noticeably
# adds up over one batched call with ~120 fragments.

source "$CONFIG_DIR/themes.sh"
source "$CONFIG_DIR/plugins/icon_map.sh"

# Must match WORKSPACE_MAX_WINDOWS in sketchybarrc.
MAX_SLOTS=10

SPACE_MON1=(1 2 3 4 5)
SPACE_MON2=(6 7 8 9 0)

# How many monitors does AeroSpace see?
MON_COUNT="$(aerospace list-monitors 2>/dev/null | grep -c '|')"

if [ "$MON_COUNT" -le 1 ]; then
  # Single-monitor setup: both rows just track the one focused workspace.
  FOCUSED_WS="$(aerospace list-workspaces --focused 2>/dev/null | head -n 1)"
  FOCUSED_MON1="$FOCUSED_WS"
  FOCUSED_MON2="$FOCUSED_WS"
else
  # Laptop display (space1.*) is AeroSpace monitor 2; external (space2.*)
  # is monitor 1 — same mapping used throughout sketchybarrc.
  FOCUSED_MON1="$(aerospace list-workspaces --monitor 2 --visible 2>/dev/null | head -n 1)"
  FOCUSED_MON2="$(aerospace list-workspaces --monitor 1 --visible 2>/dev/null | head -n 1)"
fi

FOCUSED_WINDOW_ID="$(aerospace list-windows --focused --format "%{window-id}" 2>/dev/null)"

# One `list-windows --all` call for every window on every workspace, instead
# of a separate `list-windows --workspace` call per pill. macOS ships bash
# 3.2 (no associative arrays), so each pill greps its own lines back out of
# this cached string below — still just local text filtering, not another
# round-trip to the AeroSpace daemon.
ALL_WINDOWS="$(aerospace list-windows --all --format "%{workspace}|%{window-id}|%{app-name}" 2>/dev/null)"

ARGS=()

update_pill() {
  local prefix="$1" sid="$2" focused_ws="$3"
  local bracket="$prefix.$sid"
  local num="$bracket.num"
  local slot_prefix="$bracket.slot"

  local state_fg bg_color border_width border_color
  if [ "$sid" = "$focused_ws" ]; then
    # Active workspace
    state_fg="$SPACE_ACTIVE_FG"
    bg_color="$SPACE_ACTIVE_BG"
    border_width=2
    border_color="$SPACE_ACTIVE_BORDER"
  else
    # Empty vs. inactive-with-windows is decided below once window_count is
    # known; default to the "has windows" colors here.
    state_fg="$SPACE_FG"
    bg_color="$SPACE_BG"
    border_width=0
    border_color="$SPACE_BG"
  fi

  # Fill one slot per window with that app's icon (so an app with two
  # windows open here shows its icon twice). The focused window's icon gets
  # a dedicated highlight color; every other icon gets this pill's state
  # color. No separator between icons — a plain space renders too wide in
  # the icon font, and the glyphs already carry their own side bearing.
  local window_count i=0 icon_color
  while IFS='|' read -r id app; do
    [ -z "$id" ] && continue
    [ "$i" -ge "$MAX_SLOTS" ] && break

    __icon_map "$app"

    if [ "$id" = "$FOCUSED_WINDOW_ID" ]; then
      icon_color="$SPACE_FOCUSED_FG"
    else
      icon_color="$state_fg"
    fi

    ARGS+=(--set "$slot_prefix.$i" \
      drawing=on \
      label="$icon_result" \
      label.color="$icon_color" \
      label.padding_right=0 \
      click_script="aerospace focus --window-id $id")

    i=$((i + 1))
  done <<<"$(echo "$ALL_WINDOWS" | grep "^$sid|" | cut -d'|' -f2-)"
  window_count="$i"

  while [ "$i" -lt "$MAX_SLOTS" ]; do
    ARGS+=(--set "$slot_prefix.$i" drawing=off)
    i=$((i + 1))
  done

  local num_padding_right=10
  if [ "$window_count" -gt 0 ]; then
    # Give the pill's right-edge padding back to the last visible icon, and
    # widen the number's gap before the first one.
    ARGS+=(--set "$slot_prefix.$((window_count - 1))" label.padding_right=10)
    num_padding_right=16
  elif [ "$sid" != "$focused_ws" ]; then
    # Empty, inactive workspace
    state_fg="$SPACE_EMPTY_FG"
    bg_color="$SPACE_EMPTY_BG"
    border_width=0
    border_color="$SPACE_EMPTY_BG"
  fi

  ARGS+=(--animate sin 25 --set "$bracket" \
    background.drawing=on \
    background.color="$bg_color" \
    background.border_width="$border_width" \
    background.border_color="$border_color")

  ARGS+=(--set "$num" icon.color="$state_fg" icon.padding_right="$num_padding_right")
}

for sid in "${SPACE_MON1[@]}"; do
  update_pill space1 "$sid" "$FOCUSED_MON1"
done

for sid in "${SPACE_MON2[@]}"; do
  update_pill space2 "$sid" "$FOCUSED_MON2"
done

sketchybar "${ARGS[@]}"
