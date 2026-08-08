#!/usr/bin/env bash

# Shared workspace<->monitor grouping rule, sourced by monitor_layout.sh (which
# applies it to AeroSpace's config and to the sketchybar pills' display) and
# workspace_pills.sh (which needs it to know which monitor's focused workspace
# to compare each pill against). Keeping this in one place means the two
# scripts can never disagree on which workspace belongs to which monitor.
#
# 1 monitor  -> all of 1-6 on position 1
# 2 monitors -> 1-3 on position 1, 4-6 on position 2
# 3 monitors -> 1-2 on position 1, 3-4 on position 2, 5-6 on position 3
#
# "position" here is NOT AeroSpace's own monitor numbering — it's ours, and
# build_pos_to_monid() below maps position -> actual AeroSpace monitor-id,
# forcing the built-in display to position 1 whenever it's connected (its
# physical left-to-right placement is irrelevant). When the built-in isn't
# connected, positions just fall back to whichever externals are present, in
# AeroSpace's left-to-right order.

# echoes the position (1/2/3) workspace $1 belongs to, given $2 monitors
workspace_target_monitor() {
  local ws="$1" mon_count="$2"
  if [ "$mon_count" -le 1 ]; then
    echo 1
  elif [ "$mon_count" -eq 2 ]; then
    case "$ws" in
      1|2|3) echo 1 ;;
      *) echo 2 ;;
    esac
  else
    case "$ws" in
      1|2) echo 1 ;;
      3|4) echo 2 ;;
      *) echo 3 ;;
    esac
  fi
}

# Populates the global array POS_TO_MONID[1..mon_count] = AeroSpace
# monitor-id, built-in forced to position 1 when present.
build_pos_to_monid() {
  local mon_count="$1"
  POS_TO_MONID=()
  local built_in_id="" others=() id name name_lc

  while IFS='|' read -r id name; do
    [ -z "$id" ] && continue
    name_lc="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
    case "$name_lc" in
      *built-in*) built_in_id="$id" ;;
      *) others+=("$id") ;;
    esac
  done <<<"$(aerospace list-monitors --format "%{monitor-id}|%{monitor-name}" 2>/dev/null)"

  local pos=1
  if [ -n "$built_in_id" ]; then
    POS_TO_MONID[1]="$built_in_id"
    pos=2
  fi
  for id in "${others[@]}"; do
    POS_TO_MONID[$pos]="$id"
    pos=$((pos + 1))
  done
}
