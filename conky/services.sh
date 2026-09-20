#!/usr/bin/env bash
# One process instead of five ${execi}: conky calls this script and prints its output
# as is. conky substitutes the colors itself — we only emit ${colorN}, and ${execpi}
# expands them.
C2='${color2}'; C0='${color}'

# Docker: membership in the docker group takes effect only after a re-login,
# so we tell "no containers" apart from "no access to the socket".
if docker info >/dev/null 2>&1; then
    run=$(docker ps -q 2>/dev/null | wc -l)
    all=$(docker ps -aq 2>/dev/null | wc -l)
    printf '%sdocker${goto 230}|%s %s из %s\n' "$C2" "$C0" "$run" "$all"
else
    printf '%sdocker${goto 230}|%s нужен перелогин\n' "$C2" "$C0"
fi

# ollama: what is actually loaded into VRAM right now
mdl=$(timeout 3 ollama ps 2>/dev/null | awk 'NR==2{print $1" "$3$4}')
if [ -n "$mdl" ]; then
    printf '%sollama${goto 230}|%s %s\n' "$C2" "$C0" "$mdl"
else
    cnt=$(timeout 3 ollama list 2>/dev/null | tail -n +2 | grep -c .)
    printf '%sollama${goto 230}|%s простаивает, моделей %s\n' "$C2" "$C0" "${cnt:-0}"
fi

# Updates: from the LOCAL database (pacman -Qu), with no network sync.
# checkupdates is more honest but hits the network on every call — too much for a widget.
upd=$(pacman -Qu 2>/dev/null | grep -vc '\[ignored\]')
printf '%spacman${goto 230}|%s %s обновлений\n' "$C2" "$C0" "${upd:-0}"
