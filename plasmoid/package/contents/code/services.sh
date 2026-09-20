#!/usr/bin/env bash
# Состояние служб одной строкой на службу: «метка|значение».
# Цвета и раскладку по колонкам делает QML — здесь только текст.
# Один процесс вместо трёх: виджет зовёт скрипт раз в 15 с.

# Docker: членство в группе docker подхватывается только после перелогина,
# поэтому отличаем «нет контейнеров» от «нет доступа к сокету».
if docker info >/dev/null 2>&1; then
    printf 'docker|%s из %s\n' "$(docker ps -q 2>/dev/null | wc -l)" "$(docker ps -aq 2>/dev/null | wc -l)"
else
    printf 'docker|нужен перелогин\n'
fi

# ollama: что реально загружено в видеопамять прямо сейчас.
mdl=$(timeout 3 ollama ps 2>/dev/null | awk 'NR==2{print $1" "$3$4}')
if [ -n "$mdl" ]; then
    printf 'ollama|%s\n' "$mdl"
else
    cnt=$(timeout 3 ollama list 2>/dev/null | tail -n +2 | grep -c .)
    printf 'ollama|простаивает, моделей %s\n' "${cnt:-0}"
fi

# Обновления: по ЛОКАЛЬНОЙ базе (pacman -Qu), без сетевой синхронизации.
# checkupdates честнее, но лезет в сеть на каждый вызов — для виджета это перебор.
upd=$(pacman -Qu 2>/dev/null | grep -vc '\[ignored\]')
printf 'pacman|%s обновлений\n' "${upd:-0}"
