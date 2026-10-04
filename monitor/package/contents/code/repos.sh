#!/usr/bin/env bash
# Git repositories, one line per path: "name|branch|dirty|ahead|behind", or "name|notgit"
# for a path that is not one. A leading ~ is expanded here, since the widget quotes the
# paths it passes. `rev-list --left-right --count @{upstream}...HEAD` prints "behind<TAB>ahead";
# without an upstream it fails and both read 0.
for p in "$@"; do
    p=${p/#\~/$HOME}
    name=$(basename "$p")
    if ! branch=$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null); then
        printf '%s|notgit\n' "$name"; continue
    fi
    dirty=$(git -C "$p" status --porcelain 2>/dev/null | grep -c .)
    ab=$(git -C "$p" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
    behind=${ab%%$'\t'*}; ahead=${ab##*$'\t'}
    printf '%s|%s|%s|%s|%s\n' "$name" "$branch" "$dirty" "${ahead:-0}" "${behind:-0}"
done
