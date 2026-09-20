#!/usr/bin/env sh
# Single entry point for starting the desktop monitor.
#
# Why not just "run conky":
#   * the conky package installs /usr/share/applications/conky.desktop with
#     Exec=conky --daemonize, and on session restore KWin starts EXACTLY that one —
#     with the default config. So we kill foreign instances instead of yielding to
#     them (an early version of this script did the opposite, and after a reboot a
#     foreign widget stayed on screen);
#   * conky has no click-through setting — we clear the input region with a separate
#     script, or the monitor intercepts clicks on the desktop.
set -u
CONF="$HOME/.config/conky/plainext.conf"

mine() {   # prints the pids of conky instances started with OUR config
    for pid in $(pgrep -x conky 2>/dev/null); do
        if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "$CONF"; then
            echo "$pid"
        fi
    done
}

others() { # prints the pids of all other conky instances
    for pid in $(pgrep -x conky 2>/dev/null); do
        if ! tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "$CONF"; then
            echo "$pid"
        fi
    done
}

for pid in $(others); do
    echo "гашу чужой conky: pid $pid ($(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null))" >&2
    kill "$pid" 2>/dev/null
done
[ -n "$(others)" ] && sleep 1
for pid in $(others); do kill -9 "$pid" 2>/dev/null; done

# This script is not the only thing that starts conky: KDE session restore launches it
# directly from the saved command, bypassing us. So the start is conditional, but
# click-through is applied ALWAYS, whoever started conky. An early version of this
# script simply exited when it saw conky running — and the window kept catching clicks.
CONKY_PID=""
if [ -z "$(mine)" ]; then
    conky -c "$CONF" &
    CONKY_PID=$!
else
    echo "наш conky уже работает (поднят не нами) — только гасим область ввода" >&2
fi

python3 "$HOME/.config/conky/clickthrough.py" 30 || \
    echo "click-through применить не удалось — монитор будет ловить клики" >&2

[ -n "$CONKY_PID" ] && wait "$CONKY_PID"
exit 0
