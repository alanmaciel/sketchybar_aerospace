#!/usr/bin/env bash

# MODE is ignored, we always show simple On/Off
# but we keep the parameter so click_script doesn't break anything.
MODE="$1"

# Try to detect Wi-Fi interface (fallback to en0)
IFACE="$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{getline; print $2}')"
[ -z "$IFACE" ] && IFACE="en0"

# "Connected" = command succeeds (associated to a network)
if networksetup -getairportnetwork "$IFACE" >/dev/null 2>&1; then
  # Connected
  sketchybar --set "$NAME" icon="" label=""
else
  # Not connected or Wi-Fi off
  sketchybar --set "$NAME" icon="󰤭" label=""
fi

