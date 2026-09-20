#!/usr/bin/env bash
# Один процесс вместо пяти ${execi}: conky зовёт этот скрипт и печатает вывод как есть.
# Цвета подставляет сам conky — здесь только ${colorN}, их развернёт ${execpi}.
C2='${color2}'; C0='${color}'

# Docker: членство в группе docker подхватывается только после перелогина,
# поэтому отличаем «нет контейнеров» от «нет доступа к сокету».
if docker info >/dev/null 2>&1; then
    run=$(docker ps -q 2>/dev/null | wc -l)
    all=$(docker ps -aq 2>/dev/null | wc -l)
    printf '%sdocker${goto 230}|%s %s из %s\n' "$C2" "$C0" "$run" "$all"
else
    printf '%sdocker${goto 230}|%s нужен перелогин\n' "$C2" "$C0"
fi

# ollama: что реально загружено в видеопамять прямо сейчас
mdl=$(timeout 3 ollama ps 2>/dev/null | awk 'NR==2{print $1" "$3$4}')
if [ -n "$mdl" ]; then
    printf '%sollama${goto 230}|%s %s\n' "$C2" "$C0" "$mdl"
else
    cnt=$(timeout 3 ollama list 2>/dev/null | tail -n +2 | grep -c .)
    printf '%sollama${goto 230}|%s простаивает, моделей %s\n' "$C2" "$C0" "${cnt:-0}"
fi

# Обновления: по ЛОКАЛЬНОЙ базе (pacman -Qu), без сетевой синхронизации.
# checkupdates честнее, но лезет в сеть на каждый вызов — для виджета это перебор.
upd=$(pacman -Qu 2>/dev/null | grep -vc '\[ignored\]')
printf '%spacman${goto 230}|%s %s обновлений\n' "$C2" "$C0" "${upd:-0}"
