#!/usr/bin/env bash

# Runs on the `display_change` event (and once at startup, see sketchybarrc)
# to make the whole bar — and AeroSpace's own workspace-to-monitor assignment
# — adapt automatically to however many monitors are connected right now.
# Replaces the old display_adapt.sh, which only ever handled "1 vs 2".
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

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
PLUGIN_DIR="$CONFIG_DIR/plugins"
source "$PLUGIN_DIR/monitor_groups.sh"

if command -v aerospace >/dev/null 2>&1; then
  MON_COUNT="$(aerospace list-monitors --count 2>/dev/null)"
else
  MON_COUNT=1
fi
[ -z "$MON_COUNT" ] && MON_COUNT=1

build_pos_to_monid "$MON_COUNT"

# Must match WORKSPACE_MAX_WINDOWS in sketchybarrc.
WORKSPACE_MAX_WINDOWS=10

SB_DISPLAY=()
if [ "$MON_COUNT" -le 1 ]; then
  SB_DISPLAY[1]=1
else
  MAIN_ID="$(aerospace list-monitors --format "%{monitor-id}|%{monitor-is-main}" 2>/dev/null | awk -F'|' '$2=="true"{print $1}')"
  [ -z "$MAIN_ID" ] && MAIN_ID=1
  SB_DISPLAY[$MAIN_ID]=1
  next=2
  for id in $(seq 1 "$MON_COUNT"); do
    [ "$id" = "$MAIN_ID" ] && continue
    SB_DISPLAY[$id]=$next
    next=$((next + 1))
  done
fi

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
AEROSPACE_TOML="$CONFIG_DIR/aerospace.toml"
BEGIN_MARK="# BEGIN WORKSPACE-MONITOR ASSIGNMENT (auto-managed by plugins/monitor_layout.sh — do not hand-edit)"
END_MARK="# END WORKSPACE-MONITOR ASSIGNMENT"

if command -v aerospace >/dev/null 2>&1 && [ -f "$AEROSPACE_TOML" ]; then
  NEW_BLOCK="$BEGIN_MARK
[workspace-to-monitor-force-assignment]"
  for ws in 1 2 3 4 5 6; do
    pos="$(workspace_target_monitor "$ws" "$MON_COUNT")"
    NEW_BLOCK="$NEW_BLOCK
\"$ws\" = ${POS_TO_MONID[$pos]}"
  done
  NEW_BLOCK="$NEW_BLOCK
$END_MARK"

  # macOS's stock awk chokes ("newline in string") on multi-line -v values,
  # so the marker block is spliced in with head/tail instead.
  begin_line="$(grep -nF "$BEGIN_MARK" "$AEROSPACE_TOML" | head -n1 | cut -d: -f1)"
  end_line="$(grep -nF "$END_MARK" "$AEROSPACE_TOML" | head -n1 | cut -d: -f1)"
  CURRENT_BLOCK="$(sed -n "${begin_line},${end_line}p" "$AEROSPACE_TOML")"

  if [ -n "$begin_line" ] && [ -n "$end_line" ] && [ "$CURRENT_BLOCK" != "$NEW_BLOCK" ]; then
    TMP="$(mktemp)"
    {
      head -n $((begin_line - 1)) "$AEROSPACE_TOML"
      printf '%s\n' "$NEW_BLOCK"
      tail -n +$((end_line + 1)) "$AEROSPACE_TOML"
    } >"$TMP" && mv "$TMP" "$AEROSPACE_TOML"
    aerospace reload-config --no-gui >/dev/null 2>&1
  fi
fi

# Refresh pill colors immediately — monitor connect/disconnect doesn't fire
# any of the events workspace_pills.sh normally subscribes to.
"$PLUGIN_DIR/workspace_pills.sh" &
