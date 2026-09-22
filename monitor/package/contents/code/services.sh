#!/usr/bin/env bash
# Service state, one line per service: "label|value".
# QML does the colors and the column layout — only the text is made here.
# One process instead of three: the widget calls the script once every 15 s.
#
# ⚠️ What matters here is the price of a run, not the count of lines: every 15 s adds up.
# Measured on s1dPC 2026-09-22: 615 ms of CPU per run — 4.1% of a core around the clock —
# of which `pacman -Qu` alone took 362 ms and the three docker calls 180 ms.

# Docker: membership in the docker group only takes effect after a re-login,
# so tell "no containers" apart from "no access to the socket".
# One call instead of `docker info` + `docker ps -q` + `docker ps -aq` (45 ms of CPU against
# 180). `docker ps` lists the containers whose State.Running is true, and that includes
# the paused and the restarting ones.
if states=$(docker ps -a --format '{{.State}}' 2>/dev/null); then
    printf 'docker|%s из %s\n' "$(grep -cE '^(running|paused|restarting)$' <<<"$states")" \
        "$(grep -c . <<<"$states")"
else
    printf 'docker|нужен перелогин\n'
fi

# ollama: what is actually loaded into VRAM right now.
# The HTTP API answers "anything loaded?" and "how many models?" for 9 ms of CPU against
# 35 for each start of the CLI. The CLI still prints a loaded model, so the line reads
# the same as before; with no answer from the API, everything goes through the CLI.
host=${OLLAMA_HOST:-127.0.0.1:11434}
[[ $host == http* ]] || host="http://$host"
if loaded=$(curl -sf --max-time 2 "$host/api/ps" 2>/dev/null) && [[ $loaded != *'"name":'* ]]; then
    cnt=$(curl -sf --max-time 2 "$host/api/tags" 2>/dev/null | grep -o '"name":' | wc -l)
    printf 'ollama|простаивает, моделей %s\n' "${cnt:-0}"
else
    mdl=$(timeout 3 ollama ps 2>/dev/null | awk 'NR==2{print $1" "$3$4}')
    if [ -n "$mdl" ]; then
        printf 'ollama|%s\n' "$mdl"
    else
        cnt=$(timeout 3 ollama list 2>/dev/null | tail -n +2 | grep -c .)
        printf 'ollama|простаивает, моделей %s\n' "${cnt:-0}"
    fi
fi

# Updates: from the LOCAL database (pacman -Qu), without a network sync.
# checkupdates is more honest, but hits the network on every call — too much for a widget.
# The answer only changes when the database does — a sync rewrites sync/*.db, an install
# or an upgrade rewrites local/ — so it is kept until one of their times moves.
cache=${XDG_CACHE_HOME:-$HOME/.cache}/plaintop
# ⚠️ No trailing space in the key: `read` strips it, and the cache then never matched.
key=$(stat -c %Y /etc/pacman.conf /var/lib/pacman/local /var/lib/pacman/sync/*.db 2>/dev/null | paste -sd ' ')
upd=
if [ -n "$key" ] && [ -f "$cache/pacman" ]; then
    { read -r old_key; read -r old_upd; } < "$cache/pacman"
    [ "$old_key" = "$key" ] && upd=$old_upd
fi
if [ -z "$upd" ]; then
    upd=$(pacman -Qu 2>/dev/null | grep -vc '\[ignored\]')
    # Two hosts may run this at once: write aside, then rename.
    if [ -n "$key" ] && mkdir -p "$cache" 2>/dev/null; then
        printf '%s\n%s\n' "$key" "${upd:-0}" > "$cache/pacman.$$" && mv -f "$cache/pacman.$$" "$cache/pacman"
    fi
fi
printf 'pacman|%s обновлений\n' "${upd:-0}"
