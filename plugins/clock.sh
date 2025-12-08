#!/usr/bin/env bash

MODE="$1"

if [ "$MODE" = "click" ]; then
  # Week number (ISO)
  week="$(date +%V)"

  # Quarter (1–4)
  month="$(date +%m | sed 's/^0//')"   # strip leading zero
  quarter=$(( ( (month - 1) / 3 ) + 1 ))

  # Days remaining in year
  year="$(date +%Y)"
  doy_now="$(date +%j)"  # day of year today
  # Day-of-year for Dec 31 (handles leap years)
  doy_last="$(date -jf "%Y-%m-%d" "${year}-12-31" +%j 2>/dev/null)"
  [ -z "$doy_last" ] && doy_last=365
  days_left=$((doy_last - doy_now))

  label="Week ${week} • Q${quarter} • ${days_left} days left"
  sketchybar --set "$NAME" label="$label"
else
  # Normal display: MMM dd yyyy HH:mm (24h)
  label="$(date '+%b %d %Y %H:%M')"
  sketchybar --set "$NAME" label="$label"
fi
