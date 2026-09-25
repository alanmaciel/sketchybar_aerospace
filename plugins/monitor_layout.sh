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
#   - sketchybar's associated_display is the NSScreen index, which macOS
#     orders main-first and then by its own arrangement — not left to right.
#     On this machine (laptop main at x=0, portrait panel at x=-1080,
#     ultrawide at x=-6200) AeroSpace numbers them ultrawide/portrait/laptop
#     while sketchybar numbers them laptop/portrait/ultrawide.
# SB_DISPLAY bridges AeroSpace monitor-id -> sketchybar display; it comes
# straight from AeroSpace's monitor-appkit-nsscreen-screens-id rather than
# being inferred, see monitor_groups.sh.
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
#
# Losing the race must not *drop* the event, though: plugging or unplugging a
# monitor typically fires display_change more than once, and the later firing
# is the one carrying the settled layout. A loser that simply exited left the
# bar showing whatever the first (still-mid-transition) run committed, with no
# further display_change coming to correct it. Losers now raise a rerun flag
# and the holder does another pass — same shape as workspace_pills.sh.
LOCK_DIR="${TMPDIR:-/tmp}/sketchybar-monitor-layout.lock"
PID_FILE="$LOCK_DIR/pid"
RERUN_FLAG="$LOCK_DIR/rerun"
# A pass can legitimately take a few seconds (it waits for AeroSpace to catch
# up with the new display set), but never this long; a holder older than this
# is wedged and gets broken rather than waited on. Age is read off the pid
# file, which each pass touches — the rerun flag lives inside the directory
# and would otherwise keep resetting its mtime.
LOCK_MAX_AGE=60

lock_age() {
  local mtime now
  mtime="$(stat -f %m "$PID_FILE" 2>/dev/null)"
  case "$mtime" in ''|*[!0-9]*) echo 9999; return ;; esac
  now="$(date +%s)"
  echo $((now - mtime))
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  owner="$(cat "$PID_FILE" 2>/dev/null)"
  if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null && [ "$(lock_age)" -lt "$LOCK_MAX_AGE" ]; then
    # stderr is redirected before the flag so a failure here has somewhere
    # quiet to go (redirections apply left to right).
    : 2>/dev/null >"$RERUN_FLAG" && exit 0
    # The holder finished between the liveness check and here — fall through
    # and take the lock ourselves rather than dropping the event.
  fi
  [ -n "$owner" ] && kill -9 "$owner" 2>/dev/null
  rm -rf "$LOCK_DIR" 2>/dev/null
  mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" >"$PID_FILE"
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
# display_change fires the moment macOS reconfigures the displays, but
# AeroSpace can still be a beat behind — and `list-monitors` doesn't say so,
# it just answers with the *previous* set. That's the quiet failure mode of
# plug/unplug: load_monitors() succeeds, monitors_loaded_ok() passes, a stale
# layout gets committed, and no second display_change ever arrives to correct
# it, so the pills sit on the wrong monitors until the next reload.
#
# So poll until AeroSpace's monitor count matches the display count
# *sketchybar* reports — sketchybar's own view is by definition current, since
# it is what fired the event. Bounded, so a disagreement that never resolves
# still ends in some layout rather than none.
SETTLE_TRIES=20   # x 0.25s ~= 5s

monitors_settled() {
  local want tries=0 fails=0
  want="$(sb_display_count)" || want=""
  while :; do
    if load_monitors && monitors_loaded_ok; then
      fails=0
      # Nothing to cross-check against (sketchybar didn't answer): take it.
      [ -z "$want" ] && return 0
      [ "$MON_COUNT" = "$want" ] && return 0
    else
      # An unreachable AeroSpace isn't something a 5s wait fixes, and each
      # failed attempt costs the full aero() timeout — give up on settling
      # and let the background retry path (3s apart, ten tries) take it.
      fails=$((fails + 1))
      [ "$fails" -ge 2 ] && return 1
    fi
    tries=$((tries + 1))
    [ "$tries" -ge "$SETTLE_TRIES" ] && return 1
    /bin/sleep 0.25
    # Re-read the target too: a second monitor finishing its wake-up moves it.
    want="$(sb_display_count)" || want=""
  done
}

# 0 = AeroSpace isn't reachable at all; touch nothing that needs a monitor list.
have_monitors() {
  monitors_settled && return 0
  # Counts never agreed, but AeroSpace is answering and the layout resolves
  # fully — better to apply it than to leave the bar on a layout we know is
  # stale. A rerun (below) or the next display_change gets another go.
  load_monitors && monitors_loaded_ok
}

########################################
# Apply one layout
########################################

apply_layout() {
  # Heartbeat, so a pass that legitimately spends seconds waiting on AeroSpace
  # isn't mistaken for a wedged holder by the age check above.
  touch "$PID_FILE" 2>/dev/null

  local ARGS=() ws pos mon_id display i

  for ws in 1 2 3 4 5 6; do
    pos="$(workspace_target_monitor "$ws" "$MON_COUNT")"
    mon_id="${POS_TO_MONID[$pos]}"
    display="${SB_DISPLAY[$mon_id]}"

    # A pill's bracket has its own associated_display, but its member items
    # (num, slot.0..N, gap) each carry their own independent one too — setting
    # it on the bracket alone leaves the members pinned to whichever display
    # they were created on, so they never render once that display is gone.
    ARGS+=(--set "space.$ws" associated_display="$display" drawing=on)
    ARGS+=(--set "space.$ws.num" associated_display="$display")
    ARGS+=(--set "space.$ws.gap" associated_display="$display")
    for i in $(seq 0 $((WORKSPACE_MAX_WINDOWS - 1))); do
      ARGS+=(--set "space.$ws.slot.$i" associated_display="$display")
    done
  done

  # Right side: one clock/battery pair per connected display, up to 3.
  ARGS+=(--set clock   associated_display=1 drawing=on)
  ARGS+=(--set battery associated_display=1 drawing=on)

  if [ "$MON_COUNT" -ge 2 ]; then
    ARGS+=(--set clock_ext   associated_display=2 drawing=on)
    ARGS+=(--set battery_ext associated_display=2 drawing=on)
  else
    ARGS+=(--set clock_ext   drawing=off)
    ARGS+=(--set battery_ext drawing=off)
  fi

  if [ "$MON_COUNT" -ge 3 ]; then
    ARGS+=(--set clock_ext2   associated_display=3 drawing=on)
    ARGS+=(--set battery_ext2 associated_display=3 drawing=on)
  else
    ARGS+=(--set clock_ext2   drawing=off)
    ARGS+=(--set battery_ext2 drawing=off)
  fi

  # One invocation rather than ~80 (6 pills x 13 items, plus the right side).
  # Speed is half of it; the other half is that a half-applied layout is a
  # visible, sticky mess — the err log has a monitor_layout run being SIGTERMed
  # partway through its loop of individual `--set`s, leaving some members of a
  # pill on the old display and some on the new.
  sketchybar "${ARGS[@]}"

  sync_aerospace_toml
}

########################################
# Keep AeroSpace's own workspace-to-monitor assignment in sync
########################################

sync_aerospace_toml() {
  [ -f "$AEROSPACE_TOML" ] || return 0
  toml_block_bounds || return 0

  local NEW_BLOCK CURRENT_BLOCK ws pos
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
}

########################################
# Run
########################################

if ! have_monitors; then
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

rm -f "$RERUN_FLAG" 2>/dev/null
apply_layout

# Absorb the display_change firings that arrived while we were busy. A
# plug/unplug usually produces several, and the later ones are the ones that
# describe the settled desktop, so the last pass is the one that must win.
extra=0
while [ -f "$RERUN_FLAG" ] && [ "$extra" -lt 3 ]; do
  rm -f "$RERUN_FLAG" 2>/dev/null
  touch "$PID_FILE" 2>/dev/null
  have_monitors && apply_layout
  extra=$((extra + 1))
done

# Refresh pill colors immediately — monitor connect/disconnect doesn't fire
# any of the events workspace_pills.sh normally subscribes to.
"$PLUGIN_DIR/workspace_pills.sh" &
