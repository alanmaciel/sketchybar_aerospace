#!/usr/bin/env bash

LOCK_DIR="${TMPDIR:-/tmp}/sketchybar-workspace-pills.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  old_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
  if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
printf '%s\n' "$$" >"$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

# Single controller for all 6 workspace pills (space.1..space.6), whichever
# monitor each currently lives on (see monitor_groups.sh — 1/2/3 connected
# monitors changes the grouping). Runs once per event and fans out to every
# pill internally, instead of each pill running its own copy of this script —
# that used to mean ~40 separate `aerospace` CLI round-trips (list-monitors/
# list-workspaces/list-windows, several per pill) for a single workspace
# change, which is what made switching workspaces feel sluggish. Here every
# needed fact is fetched exactly once and reused for all 6 pills.
#
# The `sketchybar --set` calls are batched into one invocation at the end
# too (ARGS accumulator) rather than issued one at a time — each is its own
# process talking to the sketchybar daemon over its socket, so ~120
# individual calls (6 pills x up to 12 property updates each) noticeably
# adds up over one batched call with ~120 fragments.

source "$CONFIG_DIR/themes.sh"
source "$CONFIG_DIR/plugins/icon_map.sh"
source "$CONFIG_DIR/plugins/monitor_groups.sh"

# Must match WORKSPACE_MAX_WINDOWS in sketchybarrc.
MAX_SLOTS=10

# How many monitors does AeroSpace see?
MON_COUNT="$(aerospace list-monitors 2>/dev/null | grep -c '|')"
[ "$MON_COUNT" -ge 1 ] || MON_COUNT=1

build_pos_to_monid "$MON_COUNT"

# Focused/visible workspace per AeroSpace monitor-id, indexed 1..MON_COUNT.
FOCUSED=()
if [ "$MON_COUNT" -le 1 ]; then
  FOCUSED[1]="$(aerospace list-workspaces --focused 2>/dev/null | head -n 1)"
else
  for i in $(seq 1 "$MON_COUNT"); do
    FOCUSED[$i]="$(aerospace list-workspaces --monitor "$i" --visible 2>/dev/null | head -n 1)"
  done
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
  local sid="$1" focused_ws="$2"
  local bracket="space.$sid"
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

  ARGS+=(--set "$bracket" \
    background.drawing=on \
    background.color="$bg_color" \
    background.border_width="$border_width" \
    background.border_color="$border_color")

  ARGS+=(--set "$num" icon.color="$state_fg" icon.padding_right="$num_padding_right")
}

for ws in 1 2 3 4 5 6; do
  pos="$(workspace_target_monitor "$ws" "$MON_COUNT")"
  mon_id="${POS_TO_MONID[$pos]}"
  update_pill "$ws" "${FOCUSED[$mon_id]}"
done

sketchybar "${ARGS[@]}"
