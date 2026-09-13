#!/usr/bin/env bash

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

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/themes.sh"
source "$CONFIG_DIR/plugins/icon_map.sh"
source "$CONFIG_DIR/plugins/monitor_groups.sh"

# Must match WORKSPACE_MAX_WINDOWS in sketchybarrc.
MAX_SLOTS=10

########################################
# Locking
########################################
# This item fires on four events plus a 1s poll, so overlapping runs are
# normal and only one may talk to sketchybar at a time. Two things the
# previous lock got wrong, both of which showed up as "the pills just stop
# responding":
#
#   1. A blocked run held the lock forever. Every `aerospace` query here now
#      goes through aero() (bounded, see monitor_groups.sh), but the lock
#      carries its own age check as a backstop — a holder older than
#      LOCK_MAX_AGE is treated as wedged and killed, not waited on. The bar
#      sat frozen for ~3 days on a single stuck `list-monitors` before this.
#   2. Losing the lock silently dropped the event. During a burst — switching
#      workspaces quickly, or an app opening several windows — the last
#      change would be the one discarded, leaving the pills showing stale
#      state until something else happened to fire. Losers now set a rerun
#      flag and the holder does one more pass, so the final state always wins.

# sketchybarrc is mid-reload: its items are torn down and not all re-added
# yet, so every --set would miss. The staleness bound keeps a sketchybarrc
# that died before its EXIT trap ran from muting the pills for good.
SB_LOADING_FLAG="${TMPDIR:-/tmp}/sketchybar-config-loading"
if [ -f "$SB_LOADING_FLAG" ]; then
  flag_mtime="$(stat -f %m "$SB_LOADING_FLAG" 2>/dev/null)"
  case "$flag_mtime" in
    ''|*[!0-9]*) rm -f "$SB_LOADING_FLAG" 2>/dev/null ;;
    *)
      if [ $(($(date +%s) - flag_mtime)) -lt 30 ]; then
        exit 0
      fi
      rm -f "$SB_LOADING_FLAG" 2>/dev/null
      ;;
  esac
fi

LOCK_DIR="${TMPDIR:-/tmp}/sketchybar-workspace-pills.lock"
PID_FILE="$LOCK_DIR/pid"
RERUN_FLAG="$LOCK_DIR/rerun"
LOCK_MAX_AGE=20

# Age of the current lock, from the pid file rather than the directory: the
# rerun flag is created inside the directory and would otherwise keep
# resetting the directory's mtime, hiding a wedged holder indefinitely.
lock_age() {
  local mtime now
  mtime="$(stat -f %m "$PID_FILE" 2>/dev/null)"
  case "$mtime" in ''|*[!0-9]*) echo 9999; return ;; esac
  now="$(date +%s)"
  echo $((now - mtime))
}

acquire_lock() {
  local attempt owner
  for attempt in 1 2 3; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      printf '%s\n' "$$" >"$PID_FILE"
      return 0
    fi

    owner="$(cat "$PID_FILE" 2>/dev/null)"
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
      if [ "$(lock_age)" -lt "$LOCK_MAX_AGE" ]; then
        # Healthy holder: hand it our turn instead of dropping this event.
        # stderr is redirected before the flag, not after: redirections are
        # applied left to right, so the other order lets the failure below
        # print before it has anywhere quiet to go.
        if : 2>/dev/null >"$RERUN_FLAG"; then
          return 1
        fi
        # The holder finished and removed the directory between the liveness
        # check and here, so there's no one left to hand off to — go back and
        # take the lock ourselves rather than dropping the event.
        continue
      fi
      kill -9 "$owner" 2>/dev/null
    fi

    # Dead or wedged owner (or a directory left behind with no pid file at
    # all, which the old SIGKILL path used to leave).
    rm -rf "$LOCK_DIR" 2>/dev/null
  done
  return 1
}

acquire_lock || exit 0
trap 'rm -rf "$LOCK_DIR"' EXIT

########################################
# One rendering pass
########################################

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
  local window_count i=0 icon_color id app
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

run_pass() {
  # Heartbeat, so a legitimately busy multi-pass run isn't mistaken for a
  # wedged one by the age check in acquire_lock().
  touch "$PID_FILE" 2>/dev/null

  # Bail rather than render from nothing. With AeroSpace unreachable every
  # query comes back empty, which would paint all six pills as empty and
  # inactive — actively worse than leaving the last known-good state up
  # until AeroSpace answers again.
  load_monitors || return 1
  monitors_loaded_ok || return 1

  # Focused/visible workspace per AeroSpace monitor-id, indexed 1..MON_COUNT.
  FOCUSED=()
  if [ "$MON_COUNT" -le 1 ]; then
    FOCUSED[1]="$(aero list-workspaces --focused | head -n 1)"
  else
    local i
    for i in $(seq 1 "$MON_COUNT"); do
      FOCUSED[$i]="$(aero list-workspaces --monitor "$i" --visible | head -n 1)"
    done
  fi

  FOCUSED_WINDOW_ID="$(aero list-windows --focused --format "%{window-id}")"

  # One `list-windows --all` call for every window on every workspace,
  # instead of a separate `list-windows --workspace` call per pill. macOS
  # ships bash 3.2 (no associative arrays), so each pill greps its own lines
  # back out of this cached string below — still just local text filtering,
  # not another round-trip to the AeroSpace daemon.
  ALL_WINDOWS="$(aero list-windows --all --format "%{workspace}|%{window-id}|%{app-name}")"

  ARGS=()
  local ws pos mon_id
  for ws in 1 2 3 4 5 6; do
    pos="$(workspace_target_monitor "$ws" "$MON_COUNT")"
    mon_id="${POS_TO_MONID[$pos]}"
    update_pill "$ws" "${FOCUSED[$mon_id]}"
  done

  sketchybar "${ARGS[@]}"
}

rm -f "$RERUN_FLAG" 2>/dev/null
run_pass

# Absorb whatever arrived while we were busy. Bounded, so a steady stream of
# events can't keep one run alive past LOCK_MAX_AGE and get it killed as if
# it were wedged — anything still pending is picked up by the next event or
# by the 1s poll.
extra=0
while [ -f "$RERUN_FLAG" ] && [ "$extra" -lt 3 ]; do
  rm -f "$RERUN_FLAG" 2>/dev/null
  run_pass
  extra=$((extra + 1))
done
