#!/usr/bin/env bash
# Batteries of peripherals — mice, keyboards, headsets, phones over Bluetooth — one line
# each: "model|percentage|state". The system battery (upower's "power supply: yes") is
# the battery block's business and is skipped. Needs upower, which powerdevil brings to
# every Plasma desktop; without it nothing is printed, and the block stays empty.
command -v upower >/dev/null || exit 0
for d in $(upower -e 2>/dev/null | grep -v -e DisplayDevice -e line_power); do
    info=$(upower -i "$d" 2>/dev/null) || continue
    grep -q 'power supply: *yes' <<<"$info" && continue
    pct=$(sed -n 's/^ *percentage: *\([0-9]*\).*/\1/p' <<<"$info" | head -n 1)
    [ -n "$pct" ] || continue
    model=$(sed -n 's/^ *model: *//p' <<<"$info" | head -n 1)
    [ -n "$model" ] || model=$(sed -n 's/^ *native-path: *//p' <<<"$info" | head -n 1)
    state=$(sed -n 's/^ *state: *//p' <<<"$info" | head -n 1)
    printf '%s|%s|%s\n' "${model//|/ }" "$pct" "$state"
done
