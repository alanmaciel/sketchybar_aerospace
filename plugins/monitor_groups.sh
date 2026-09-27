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
# sketchybar display discovery
########################################
# sketchybar's display numbers and AeroSpace's monitor-ids are two unrelated
# orderings of the same physical screens, and the only thing the two tools
# agree on is *where the screens are*. So the bridge between them is matched
# geometrically, not computed:
#
#   - AeroSpace numbers monitors left to right, top to bottom, so a
#     monitor-id is that monitor's rank in that order.
#   - `sketchybar --query displays` reports each display's own number
#     (arrangement-id) together with its frame, so sorting that output by
#     x then y produces the same ranking.
#
# Two shortcuts have already shipped here and both broke, each time silently
# swapping the two external monitors — pills for the workspaces AeroSpace put
# on one screen rendered on the other:
#
#   1. "main display is 1, then the rest left-to-right." Wrong because
#      sketchybar's order is not physical order.
#   2. AeroSpace's `monitor-appkit-nsscreen-screens-id`, i.e. the index into
#      AppKit's NSScreen.screens. Very tempting — it is a real, live value
#      and it agreed with sketchybar on this machine for a while. It is still
#      not sketchybar's numbering: with the laptop (main) at x=0, a portrait
#      panel at x=-1080 and an ultrawide at x=-3640, NSScreen orders them
#      laptop/portrait/ultrawide while sketchybar numbers them
#      laptop/ultrawide/portrait. Changing only the ultrawide's resolution
#      was enough to make the two disagree.
#
# If you are tempted by a third shortcut: check it against
# `sketchybar --query displays` with the externals at different resolutions
# first, and note that both previous ones looked right on a static desktop.

# Emits "<x>\t<y>\t<display-number>" per display, sorted left to right and
# then top to bottom — AeroSpace's own monitor ordering.
sb_displays_by_position() {
  sketchybar --query displays 2>/dev/null | awk -F: '
    /"arrangement-id"/ { id=$2; gsub(/[^0-9]/, "", id); have=1; next }
    have && /"x"/ { v=$2; gsub(/[^0-9.+-]/, "", v); x=v+0; next }
    have && /"y"/ { v=$2; gsub(/[^0-9.+-]/, "", v); y=v+0;
                    printf "%d\t%d\t%s\n", x, y, id; have=0; next }
  ' | sort -t"$(printf '\t')" -k1,1n -k2,2n
}

# How many displays *sketchybar* currently sees. This is the authoritative
# count for the bar, and it updates the instant display_change fires —
# AeroSpace's own list can still be a beat behind, so monitor_layout.sh waits
# for the two to agree before it commits a layout. Echoes 0 / returns 1 when
# sketchybar can't be queried.
sb_display_count() {
  local n
  n="$(sb_displays_by_position | wc -l | tr -d ' ')"
  case "$n" in ''|*[!0-9]*) echo 0; return 1 ;; esac
  [ "$n" -ge 1 ] || { echo 0; return 1; }
  echo "$n"
}

########################################
# Monitor discovery
########################################
# Populates, from a single `list-monitors` round-trip:
#   MON_COUNT      - how many monitors AeroSpace sees (>= 1)
#   POS_TO_MONID[] - our position (1..MAX_POSITIONS) -> AeroSpace monitor-id,
#                    built-in forced to position 1 when present
#   SB_DISPLAY[]   - AeroSpace monitor-id -> sketchybar associated_display,
#                    matched geometrically: see sb_displays_by_position().
#                    Do not try to compute this from monitor properties; two
#                    such shortcuts have already shipped and both broke.
#   SB_DISPLAY_SOURCE - how SB_DISPLAY was derived: "geometry" when sketchybar
#                    and AeroSpace agree on the display set (trustworthy),
#                    "nsscreen" when it fell back (sketchybar unqueryable, or
#                    a plug/unplug still in flight), "" when neither worked.
#                    Only "geometry" is safe to *re-assert* pills onto from a
#                    polling caller; see workspace_pills.sh.
#
# Returns non-zero — leaving all three untouched — when AeroSpace can't be
# reached. Callers must check: a layout derived from an empty monitor list is
# how aerospace.toml previously ended up with `"1" = ` written into it.
load_monitors() {
  command -v aerospace >/dev/null 2>&1 || return 1

  local raw
  # monitor-name goes last: it is the only field that could contain a "|",
  # and read's final variable absorbs the remainder of the line.
  raw="$(aero list-monitors --format "%{monitor-id}|%{monitor-is-main}|%{monitor-appkit-nsscreen-screens-id}|%{monitor-name}")" || return 1
  [ -n "$raw" ] || return 1

  local built_in_id="" main_id="" others=() count=0
  local id name is_main ns_id name_lc
  local ns_fallback=1
  NS_SCREEN_ID=()
  while IFS='|' read -r id is_main ns_id name; do
    # Skip anything that isn't a monitor row — notably the CLI's own
    # "Can't connect to AeroSpace server" text, which otherwise parses as a
    # monitor and yields a bogus layout.
    case "$id" in ''|*[!0-9]*) continue ;; esac
    count=$((count + 1))
    [ "$is_main" = "true" ] && main_id="$id"

    # Kept only for the fallback below. An AeroSpace too old to know the
    # placeholder echoes it back verbatim, hence the numeric check.
    case "$ns_id" in
      ''|*[!0-9]*|0) ns_fallback=0 ;;
      *) NS_SCREEN_ID[$id]="$ns_id" ;;
    esac

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

  [ -n "$main_id" ] || main_id=1

  # AeroSpace monitor-id -> sketchybar display, matched by physical position:
  # AeroSpace numbers its monitors left to right, so a monitor-id *is* that
  # monitor's rank in sb_displays_by_position's output. One sketchybar query
  # for the whole mapping — load_monitors() is called once a second by
  # workspace_pills.sh, so this must not be per-monitor.
  SB_DISPLAY=()
  local i geo_ok=1 rows sb_n
  rows="$(sb_displays_by_position)"
  sb_n="$(printf '%s' "$rows" | grep -c . 2>/dev/null)"
  case "$sb_n" in ''|*[!0-9]*) sb_n=0 ;; esac

  # A count that disagrees with AeroSpace's means one of the two is
  # mid-reconfigure; a mapping built from a half-updated list is worse than
  # none. monitor_layout.sh waits that out (see monitors_settled).
  if [ "$sb_n" = "$count" ]; then
    for i in $(seq 1 "$count"); do
      SB_DISPLAY[$i]="$(printf '%s\n' "$rows" | sed -n "${i}p" | cut -f3)"
      case "${SB_DISPLAY[$i]}" in ''|*[!0-9]*) geo_ok=0 ;; esac
    done
  else
    geo_ok=0
  fi

  SB_DISPLAY_SOURCE=geometry
  if [ "$geo_ok" != 1 ]; then
    # Fall back to the NSScreen index — usually, but not always, sketchybar's
    # numbering. Leaving SB_DISPLAY empty is the honest answer when we have
    # neither; monitors_loaded_ok() then keeps every caller from acting.
    SB_DISPLAY=()
    SB_DISPLAY_SOURCE=""
    if [ "$ns_fallback" = 1 ]; then
      for i in $(seq 1 "$count"); do
        SB_DISPLAY[$i]="${NS_SCREEN_ID[$i]}"
      done
      SB_DISPLAY_SOURCE=nsscreen
    fi
  fi

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
