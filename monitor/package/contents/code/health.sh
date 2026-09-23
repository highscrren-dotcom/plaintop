#!/usr/bin/env bash
# System health, one line per key: "key|field|field…" — numbers and states, not phrases.
# QML turns them into text through the translation catalog. Called once every 15 s with
# the number of error lines wanted as $1.
#
#   failed|<system>|<user>     failed units of the system and of the user manager
#                              ("?" when a manager did not answer)
#   err|<system>|<user>        journal entries of priority err or worse since boot
#   err|noaccess               the system journal cannot be read — this user is in
#                              neither systemd-journal, adm nor wheel; no errline follows
#   errline|<ident>|<message>  the last distinct system errors, newest first, at most $1
#                              of them, each cut at 120 characters
#
# ⚠️ The price of a run, as with services.sh: measured on s1dPC 2026-09-23, 34 ms wall
# for two systemctl and three journalctl calls, with 34 system and 81 user errors since
# boot. Nothing here touches the network.

set -o pipefail
n=${1:-3}

sf=$(systemctl show -p NFailedUnits --value 2>/dev/null)
uf=$(systemctl --user show -p NFailedUnits --value 2>/dev/null)
printf 'failed|%s|%s\n' "${sf:-?}" "${uf:-?}"

# ⚠️ --output-fields=PRIORITY is what makes `wc -l` count entries: `-o cat` alone prints
# each MESSAGE, and a multi-line message counts as several. Without access to the system
# journal journalctl exits 1 — by systemd's source (journal_access_check_and_warn →
# -EACCES), not measured here: this user is in wheel — and pipefail carries that through.
if ! se=$(journalctl --system -p err -b -q -o cat --output-fields=PRIORITY 2>/dev/null | wc -l); then
    printf 'err|noaccess\n'
    exit 0
fi
ue=$(journalctl --user -p err -b -q -o cat --output-fields=PRIORITY 2>/dev/null | wc -l)
printf 'err|%s|%s\n' "$se" "${ue:-0}"

[ "$n" -gt 0 ] 2>/dev/null || exit 0

# The last distinct errors, newest first. Under LC_ALL=C short-iso is a fixed 25-character
# stamp, so a line is "STAMP IDENT[PID]: MESSAGE": the stamp goes, the pid goes, and the
# ident becomes the first field. The same message repeats (23 times here, one docker
# start failure after another), hence the dedup before the cut. The cut itself runs under
# C.UTF-8 so -c counts characters: under C it counts bytes and can split a multibyte one.
LC_ALL=C journalctl --system -p err -b -q -r -n 40 -o short-iso --no-hostname 2>/dev/null \
    | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' | cut -d' ' -f2- \
    | sed -E 's/^([^ :[]+)(\[[0-9]+\])?: /\1|/' | awk '!seen[$0]++' | head -n "$n" \
    | LC_ALL=C.UTF-8 cut -c1-120 | sed 's/^/errline|/'
