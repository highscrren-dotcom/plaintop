#!/usr/bin/env bash
# The default output — and, with "input" as $1, the default input — of PipeWire through
# WirePlumber's wpctl: "sink|name|volume%|muted" and "source|name|volume%|muted". A
# machine without wpctl prints nothing. `wpctl get-volume` answers "Volume: 0.45 [MUTED]";
# `inspect` lists the node's properties, the description marked with an asterisk.
command -v wpctl >/dev/null || exit 0
describe() {
    local kind=$1 node=$2 vol pct muted name
    vol=$(wpctl get-volume "$node" 2>/dev/null) || return 0
    [ -n "$vol" ] || return 0
    pct=$(awk '{printf "%d", $2 * 100 + 0.5}' <<<"$vol")
    muted=0; [[ $vol == *MUTED* ]] && muted=1
    name=$(wpctl inspect "$node" 2>/dev/null | sed -n 's/^[ *]*node\.description = "\(.*\)"$/\1/p' | head -n 1)
    printf '%s|%s|%s|%s\n' "$kind" "${name//|/ }" "$pct" "$muted"
}
describe sink @DEFAULT_AUDIO_SINK@
[ "${1:-}" = "input" ] && describe source @DEFAULT_AUDIO_SOURCE@
exit 0
