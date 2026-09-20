#!/usr/bin/env bash
# Service state, one line per service: "label|value".
# QML does the colors and the column layout — only the text is made here.
# One process instead of three: the widget calls the script once every 15 s.

# Docker: membership in the docker group only takes effect after a re-login,
# so tell "no containers" apart from "no access to the socket".
if docker info >/dev/null 2>&1; then
    printf 'docker|%s из %s\n' "$(docker ps -q 2>/dev/null | wc -l)" "$(docker ps -aq 2>/dev/null | wc -l)"
else
    printf 'docker|нужен перелогин\n'
fi

# ollama: what is actually loaded into VRAM right now.
mdl=$(timeout 3 ollama ps 2>/dev/null | awk 'NR==2{print $1" "$3$4}')
if [ -n "$mdl" ]; then
    printf 'ollama|%s\n' "$mdl"
else
    cnt=$(timeout 3 ollama list 2>/dev/null | tail -n +2 | grep -c .)
    printf 'ollama|простаивает, моделей %s\n' "${cnt:-0}"
fi

# Updates: from the LOCAL database (pacman -Qu), without a network sync.
# checkupdates is more honest, but hits the network on every call — too much for a widget.
upd=$(pacman -Qu 2>/dev/null | grep -vc '\[ignored\]')
printf 'pacman|%s обновлений\n' "${upd:-0}"
