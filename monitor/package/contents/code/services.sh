#!/usr/bin/env bash
# Service state, one line per service: "key|field|field…" — numbers and states, not
# phrases. QML turns them into text through the translation catalog, so plural forms and
# the language are its business; a service this machine does not have prints nothing.
# One process instead of several: the widget calls the script once every 15 s.
#
# ⚠️ What matters here is the price of a run, not the count of lines: every 15 s adds up.
# Measured on s1dPC 2026-09-22: 615 ms of CPU per run — 4.1% of a core around the clock —
# of which `pacman -Qu` alone took 362 ms and the three docker calls 180 ms. Hence the
# cache for the package counts below, and one call per container engine.

# Containers: docker and podman alike. Membership in the docker group only takes effect
# after a re-login, so "no containers" is told apart from "no access to the socket".
# One call instead of `info` + `ps -q` + `ps -aq` (45 ms of CPU against 180). `ps -a`
# with the state column lists every container; running, paused and restarting count as up.
containers() {
    local engine=$1 states
    command -v "$engine" >/dev/null || return 0
    if states=$(timeout 5 "$engine" ps -a --format '{{.State}}' 2>/dev/null); then
        printf '%s|%s|%s\n' "$engine" "$(grep -cE '^(running|paused|restarting)$' <<<"$states")" \
            "$(grep -c . <<<"$states")"
    else
        printf '%s|noaccess\n' "$engine"
    fi
}
containers docker
containers podman

# Virtual machines under libvirt: the system instance when this user may see it, else
# the session one. "libvirt|running|total|names of the running ones".
if command -v virsh >/dev/null; then
    for uri in qemu:///system qemu:///session; do
        all=$(timeout 3 virsh -c "$uri" list --all --name 2>/dev/null) || continue
        total=$(grep -c . <<<"$all")
        [ "$total" -gt 0 ] || continue
        up=$(timeout 3 virsh -c "$uri" list --state-running --name 2>/dev/null | grep .)
        printf 'libvirt|%s|%s|%s\n' "$(grep -c . <<<"$up")" "$total" "$(paste -sd ',' <<<"$up" | sed 's/,/, /g')"
        break
    done
fi

# ollama: what is actually loaded into VRAM right now.
# The HTTP API answers "anything loaded?" and "how many models?" for 9 ms of CPU against
# 35 for each start of the CLI. The CLI still prints a loaded model, so the line reads
# the same as before; with no answer from the API, everything goes through the CLI.
host=${OLLAMA_HOST:-127.0.0.1:11434}
[[ $host == http* ]] || host="http://$host"
if loaded=$(curl -sf --max-time 2 "$host/api/ps" 2>/dev/null) && [[ $loaded != *'"name":'* ]]; then
    cnt=$(curl -sf --max-time 2 "$host/api/tags" 2>/dev/null | grep -o '"name":' | wc -l)
    printf 'ollama|idle|%s\n' "${cnt:-0}"
elif command -v ollama >/dev/null; then
    mdl=$(timeout 3 ollama ps 2>/dev/null | awk 'NR==2{print $1" "$3$4}')
    if [ -n "$mdl" ]; then
        printf 'ollama|model|%s\n' "$mdl"
    else
        cnt=$(timeout 3 ollama list 2>/dev/null | tail -n +2 | grep -c .)
        printf 'ollama|idle|%s\n' "${cnt:-0}"
    fi
fi

# Updates, from the LOCAL databases, without a network sync — checkupdates and its kin
# are more honest but hit the network on every call, too much for a widget. A manager
# the machine does not have prints no line at all rather than a false "0". The count is
# kept until its key changes: for pacman and apt the database's own times, for the rest
# a half-hour slot. Two hosts may run this at once: written aside, then renamed.
cache=${XDG_CACHE_HOME:-$HOME/.cache}/plaintop
slot=$(( $(date +%s) / 1800 ))

# cached NAME KEY COMMAND…: the stored count while the key holds, else COMMAND's output,
# stored. ⚠️ No trailing space in the key: `read` strips it, and the cache never matched.
cached() {
    local name=$1 key=$2 old_key old_val val
    shift 2
    if [ -n "$key" ] && [ -f "$cache/$name" ]; then
        { read -r old_key; read -r old_val; } < "$cache/$name"
        if [ "$old_key" = "$key" ]; then printf '%s\n' "$old_val"; return 0; fi
    fi
    val=$("$@") || return 1
    if [ -n "$key" ] && mkdir -p "$cache" 2>/dev/null; then
        printf '%s\n%s\n' "$key" "${val:-0}" > "$cache/$name.$$" && mv -f "$cache/$name.$$" "$cache/$name"
    fi
    printf '%s\n' "${val:-0}"
}

# Each counter prints a number and succeeds, or fails and prints nothing — then no line.
# `grep -c .` on the filtered text: a here-string of nothing is one empty line, which it
# does not count, where `grep -vc` would have counted it as one.
pacman_updates() {
    # pacman -Qu exits 1 with nothing to list: that is an answer, zero.
    local out; out=$(LC_ALL=C pacman -Qu 2>/dev/null)
    grep -v '\[ignored\]' <<<"$out" | grep -c .; return 0
}
apt_updates() {
    local out; out=$(LC_ALL=C apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null) || return 1
    grep -c '^Inst ' <<<"$out"; return 0
}
dnf_updates() {
    # -C: cached metadata only. Exit 100 means "updates available", 0 none, 1 an error.
    local out rc; out=$(LC_ALL=C dnf -q -C check-update 2>/dev/null); rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 100 ] || return 1
    grep -cE '^[[:alnum:]][^[:space:]]*\.[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+$' <<<"$out"; return 0
}
zypper_updates() {
    local out; out=$(LC_ALL=C zypper --no-refresh -q lu 2>/dev/null) || return 1
    grep -c '^v ' <<<"$out"; return 0
}
flatpak_updates() {
    local out; out=$(LC_ALL=C flatpak remote-ls --updates --cached 2>/dev/null) || return 1
    grep -c . <<<"$out"; return 0
}

if command -v pacman >/dev/null; then
    key=$(stat -c %Y /etc/pacman.conf /var/lib/pacman/local /var/lib/pacman/sync/*.db 2>/dev/null | paste -sd ' ')
    n=$(cached pacman "$key" pacman_updates) && printf 'pacman|%s\n' "$n"
fi
if command -v apt-get >/dev/null && [ -d /var/lib/apt/lists ]; then
    key=$(stat -c %Y /var/lib/apt/lists /var/lib/dpkg/status 2>/dev/null | paste -sd ' ')
    n=$(cached apt "$key" apt_updates) && printf 'apt|%s\n' "$n"
fi
if command -v dnf >/dev/null; then
    n=$(cached dnf "$slot" dnf_updates) && printf 'dnf|%s\n' "$n"
fi
if command -v zypper >/dev/null; then
    n=$(cached zypper "$slot" zypper_updates) && printf 'zypper|%s\n' "$n"
fi
if command -v flatpak >/dev/null; then
    n=$(cached flatpak "$slot" flatpak_updates) && printf 'flatpak|%s\n' "$n"
fi
exit 0
