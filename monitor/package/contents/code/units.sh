#!/usr/bin/env bash
# systemd units, one line each: "unit|state" — active, inactive, failed, activating,
# deactivating, reloading — from the system manager, or the user's with --user first.
# `is-active` answers for every unit it is asked about, in order, and names an unknown
# one "inactive", so the list always comes back whole; its exit status is ignored.
mgr=()
if [ "${1:-}" = "--user" ]; then mgr=(--user); shift; fi
[ $# -gt 0 ] || exit 0
states=$(systemctl "${mgr[@]}" is-active "$@" 2>/dev/null)
i=0
for u in "$@"; do
    i=$((i + 1))
    printf '%s|%s\n' "$u" "$(sed -n "${i}p" <<<"$states")"
done
