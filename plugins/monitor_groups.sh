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
# load_monitors() below maps position -> actual AeroSpace monitor-id,
# forcing the built-in display to position 1 whenever it's connected (its
# physical left-to-right placement is irrelevant). When the built-in isn't
# connected, positions just fall back to whichever externals are present, in
# AeroSpace's left-to-right order.

# Positions we actually group workspaces onto. A 4th+ monitor stays connected
# and usable, it just doesn't get a workspace group of its own.
MAX_POSITIONS=3

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

########################################
# Bounded AeroSpace CLI calls
########################################
# The AeroSpace CLI does not fail fast when AeroSpace.app isn't running — it
# blocks on its socket, indefinitely. Observed in the wild: one
# `aerospace list-monitors` stuck for nearly three days, holding
# workspace_pills.sh's lock the whole time, which froze every pill on the bar
# until the process was killed by hand. Nothing in this config may call
# `aerospace` directly for a query; route it through aero() so a dead or
# still-starting AeroSpace costs a couple of seconds instead of the session.

AERO_TIMEOUT="${AERO_TIMEOUT:-2}"

_AERO_TIMEOUT_CMD=""
for _aero_c in timeout gtimeout /opt/homebrew/bin/timeout /opt/homebrew/bin/gtimeout; do
  if command -v "$_aero_c" >/dev/null 2>&1; then
    _AERO_TIMEOUT_CMD="$_aero_c"
    break
  fi
done
unset _aero_c

# aero <aerospace args...> — stdout is the command's stdout, exit status is
# the command's, or 124 when it had to be killed for running long.
aero() {
  if [ -n "$_AERO_TIMEOUT_CMD" ]; then
    "$_AERO_TIMEOUT_CMD" -k 1 "$AERO_TIMEOUT" aerospace "$@" 2>/dev/null
    return $?
  fi

  # Fallback for a PATH without coreutils: run it detached and reap it
  # ourselves once the deadline passes.
  local out pid waited=0 rc
  out="$(mktemp)"
  aerospace "$@" >"$out" 2>/dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge $((AERO_TIMEOUT * 10)) ]; then
      kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      rm -f "$out"
      return 124
    fi
    /bin/sleep 0.1
    waited=$((waited + 1))
  done
  wait "$pid"
  rc=$?
  cat "$out"
  rm -f "$out"
  return "$rc"
}

########################################
# Monitor discovery
########################################
# Populates, from a single `list-monitors` round-trip:
#   MON_COUNT      - how many monitors AeroSpace sees (>= 1)
#   POS_TO_MONID[] - our position (1..MAX_POSITIONS) -> AeroSpace monitor-id,
#                    built-in forced to position 1 when present
#   SB_DISPLAY[]   - AeroSpace monitor-id -> sketchybar associated_display.
#                    sketchybar always calls the *main* display 1 and numbers
#                    the rest 2..N left-to-right, which is a different order
#                    from AeroSpace's, hence this second bridge.
#
# Returns non-zero — leaving all three untouched — when AeroSpace can't be
# reached. Callers must check: a layout derived from an empty monitor list is
# how aerospace.toml previously ended up with `"1" = ` written into it.
load_monitors() {
  command -v aerospace >/dev/null 2>&1 || return 1

  local raw
  raw="$(aero list-monitors --format "%{monitor-id}|%{monitor-name}|%{monitor-is-main}")" || return 1
  [ -n "$raw" ] || return 1

  local built_in_id="" main_id="" others=() count=0
  local id name is_main name_lc
  while IFS='|' read -r id name is_main; do
    # Skip anything that isn't a monitor row — notably the CLI's own
    # "Can't connect to AeroSpace server" text, which otherwise parses as a
    # monitor and yields a bogus layout.
    case "$id" in ''|*[!0-9]*) continue ;; esac
    count=$((count + 1))
    [ "$is_main" = "true" ] && main_id="$id"
    name_lc="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
    case "$name_lc" in
      *built-in*) built_in_id="$id" ;;
      *) others+=("$id") ;;
    esac
  done <<<"$raw"

  [ "$count" -ge 1 ] || return 1

  POS_TO_MONID=()
  local pos=1
  if [ -n "$built_in_id" ]; then
    POS_TO_MONID[1]="$built_in_id"
    pos=2
  fi
  for id in ${others[@]+"${others[@]}"}; do
    POS_TO_MONID[$pos]="$id"
    pos=$((pos + 1))
  done

  SB_DISPLAY=()
  [ -n "$main_id" ] || main_id=1
  SB_DISPLAY[$main_id]=1
  local next=2 i
  for i in $(seq 1 "$count"); do
    [ "$i" = "$main_id" ] && continue
    SB_DISPLAY[$i]=$next
    next=$((next + 1))
  done

  MON_COUNT="$count"
  return 0
}

# True only when every position a workspace can be routed to resolves to a
# real monitor-id, and that id resolves to a sketchybar display. Anything
# that writes to disk or repositions a pill must gate on this.
monitors_loaded_ok() {
  case "$MON_COUNT" in ''|*[!0-9]*) return 1 ;; esac
  [ "$MON_COUNT" -ge 1 ] || return 1

  local needed="$MON_COUNT" pos mon_id
  [ "$needed" -gt "$MAX_POSITIONS" ] && needed="$MAX_POSITIONS"

  for pos in $(seq 1 "$needed"); do
    mon_id="${POS_TO_MONID[$pos]}"
    case "$mon_id" in ''|*[!0-9]*) return 1 ;; esac
    case "${SB_DISPLAY[$mon_id]}" in ''|*[!0-9]*) return 1 ;; esac
  done
  return 0
}
