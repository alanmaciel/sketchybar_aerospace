#!/usr/bin/env bash

# Runs on the `display_change` event (and once at startup, see sketchybarrc)
# to make the whole bar — and AeroSpace's own workspace-to-monitor assignment
# — adapt automatically to however many monitors are connected right now.
#
# Three numbering schemes are in play and none of them agree with each other:
#   - AeroSpace numbers monitors 1..N left-to-right.
#   - Our own "position" (see monitor_groups.sh) forces the built-in display
#     to position 1 whenever it's connected, regardless of its physical
#     placement — POS_TO_MONID bridges position -> AeroSpace monitor-id.
#   - sketchybar's associated_display always puts the main display at 1, then
#     numbers the rest in left-to-right order. Verified empirically on this
#     machine (3 monitors): AeroSpace has the laptop as monitor 3 (rightmost),
#     sketchybar still shows it as display 1 because it's the main display.
# SB_DISPLAY bridges AeroSpace monitor-id -> sketchybar display.
#
# Both bridges come from load_monitors(), which fails rather than guessing
# when AeroSpace isn't reachable. That distinction matters: this script used
# to apply whatever the (empty) monitor list gave it, which wrote a literal
# `"1" = ` into aerospace.toml. That's invalid TOML, so AeroSpace then
# refused to load its config at all — and with AeroSpace down, the next run
# had no monitor list either, so the breakage was self-sustaining.

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
PLUGIN_DIR="$CONFIG_DIR/plugins"
source "$PLUGIN_DIR/monitor_groups.sh"

# Must match WORKSPACE_MAX_WINDOWS in sketchybarrc.
WORKSPACE_MAX_WINDOWS=10

AEROSPACE_TOML="$CONFIG_DIR/aerospace.toml"
BEGIN_MARK="# BEGIN WORKSPACE-MONITOR ASSIGNMENT (auto-managed by plugins/monitor_layout.sh — do not hand-edit)"
END_MARK="# END WORKSPACE-MONITOR ASSIGNMENT"

# A startup run and a display_change replay can land at the same moment, and
# two copies interleaving their `--set associated_display` calls is what left
# pills pinned to a display that no longer exists.
LOCK_DIR="${TMPDIR:-/tmp}/sketchybar-monitor-layout.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  owner="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
  if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
    exit 0
  fi
  rm -rf "$LOCK_DIR" 2>/dev/null
  mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" >"$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

########################################
# aerospace.toml block helpers
########################################

toml_block_bounds() {
  BEGIN_LINE="$(grep -nF "$BEGIN_MARK" "$AEROSPACE_TOML" 2>/dev/null | head -n1 | cut -d: -f1)"
  END_LINE="$(grep -nF "$END_MARK" "$AEROSPACE_TOML" 2>/dev/null | head -n1 | cut -d: -f1)"
  [ -n "$BEGIN_LINE" ] && [ -n "$END_LINE" ] && [ "$END_LINE" -gt "$BEGIN_LINE" ]
}

# Splice $1 (the full replacement block, markers included) into the file.
# macOS's stock awk chokes ("newline in string") on multi-line -v values, so
# this is done with head/tail rather than awk.
write_toml_block() {
  local new_block="$1" tmp
  tmp="$(mktemp)" || return 1
  {
    head -n $((BEGIN_LINE - 1)) "$AEROSPACE_TOML"
    printf '%s\n' "$new_block"
    tail -n +$((END_LINE + 1)) "$AEROSPACE_TOML"
  } >"$tmp" && mv "$tmp" "$AEROSPACE_TOML"
}

# Every assignment line must be `"<ws>" = <digits>`; the only other lines
# allowed are the two markers and the table header. Guards against writing a
# half-resolved block, and detects one already on disk.
block_is_valid() {
  local line
  while IFS= read -r line; do
    case "$line" in
      "$BEGIN_MARK"|"$END_MARK"|"[workspace-to-monitor-force-assignment]"|"") continue ;;
    esac
    case "$line" in
      '"'[0-9]'" = '[0-9]) continue ;;
      '"'[0-9]'" = '[0-9][0-9]) continue ;;
      *) return 1 ;;
    esac
  done <<<"$1"
  return 0
}

########################################
# Discover monitors
########################################

if ! load_monitors || ! monitors_loaded_ok; then
  # AeroSpace is down or still coming up. Touch nothing that depends on a
  # monitor list — but if a previous run already corrupted the TOML, repair
  # it here, because until it parses AeroSpace can't start, and until
  # AeroSpace starts we can never get a monitor list to repair it with.
  if [ -f "$AEROSPACE_TOML" ] && toml_block_bounds; then
    CURRENT_BLOCK="$(sed -n "${BEGIN_LINE},${END_LINE}p" "$AEROSPACE_TOML")"
    if ! block_is_valid "$CURRENT_BLOCK"; then
      # An empty table is valid TOML and simply means "don't force any
      # workspace onto a particular monitor" — the right neutral state when
      # we genuinely don't know the layout. The next successful run fills it.
      write_toml_block "$BEGIN_MARK
[workspace-to-monitor-force-assignment]
$END_MARK"
    fi
  fi

  # Retry in the background: at login the sketchybar launchd service can win
  # the race against AeroSpace.app, and display_change won't fire again on
  # its own to give us a second chance. Bounded, and single-file because the
  # lock above admits one copy at a time.
  ATTEMPT="${MONITOR_LAYOUT_ATTEMPT:-1}"
  if [ "$ATTEMPT" -lt 10 ]; then
    (
      /bin/sleep 3
      MONITOR_LAYOUT_ATTEMPT=$((ATTEMPT + 1)) "$0"
    ) >/dev/null 2>&1 &
  fi
  exit 0
fi

########################################
# Place the workspace pills
########################################

# A pill's bracket has its own associated_display, but its member items
# (num, slot.0..N, gap) each carry their own independent one too — setting
# it on the bracket alone leaves the members pinned to whichever display
# they were created on, so they never render once that display is gone.
set_pill_display() {
  local sid="$1" display="$2"
  sketchybar --set "space.$sid" associated_display="$display" drawing=on
  sketchybar --set "space.$sid.num" associated_display="$display"
  sketchybar --set "space.$sid.gap" associated_display="$display"
  for i in $(seq 0 $((WORKSPACE_MAX_WINDOWS - 1))); do
    sketchybar --set "space.$sid.slot.$i" associated_display="$display"
  done
}

for ws in 1 2 3 4 5 6; do
  pos="$(workspace_target_monitor "$ws" "$MON_COUNT")"
  mon_id="${POS_TO_MONID[$pos]}"
  set_pill_display "$ws" "${SB_DISPLAY[$mon_id]}"
done

# Right side: one clock/battery pair per connected display, up to 3.
sketchybar --set clock   associated_display=1 drawing=on
sketchybar --set battery associated_display=1 drawing=on

if [ "$MON_COUNT" -ge 2 ]; then
  sketchybar --set clock_ext   associated_display=2 drawing=on
  sketchybar --set battery_ext associated_display=2 drawing=on
else
  sketchybar --set clock_ext   drawing=off
  sketchybar --set battery_ext drawing=off
fi

if [ "$MON_COUNT" -ge 3 ]; then
  sketchybar --set clock_ext2   associated_display=3 drawing=on
  sketchybar --set battery_ext2 associated_display=3 drawing=on
else
  sketchybar --set clock_ext2   drawing=off
  sketchybar --set battery_ext2 drawing=off
fi

########################################
# Keep AeroSpace's own workspace-to-monitor assignment in sync
########################################

if [ -f "$AEROSPACE_TOML" ] && toml_block_bounds; then
  NEW_BLOCK="$BEGIN_MARK
[workspace-to-monitor-force-assignment]"
  for ws in 1 2 3 4 5 6; do
    pos="$(workspace_target_monitor "$ws" "$MON_COUNT")"
    NEW_BLOCK="$NEW_BLOCK
\"$ws\" = ${POS_TO_MONID[$pos]}"
  done
  NEW_BLOCK="$NEW_BLOCK
$END_MARK"

  CURRENT_BLOCK="$(sed -n "${BEGIN_LINE},${END_LINE}p" "$AEROSPACE_TOML")"

  # Never hand AeroSpace a block we just built badly — a config it can't
  # parse takes the window manager down with it.
  if block_is_valid "$NEW_BLOCK" && [ "$CURRENT_BLOCK" != "$NEW_BLOCK" ]; then
    if write_toml_block "$NEW_BLOCK"; then
      aero reload-config --no-gui >/dev/null 2>&1
    fi
  fi
fi

# Refresh pill colors immediately — monitor connect/disconnect doesn't fire
# any of the events workspace_pills.sh normally subscribes to.
"$PLUGIN_DIR/workspace_pills.sh" &
