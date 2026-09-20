#!/usr/bin/env sh
# Единая точка запуска монитора рабочего стола.
#
# Почему не просто «запустить conky»:
#   * пакет conky ставит /usr/share/applications/conky.desktop с Exec=conky --daemonize,
#     и KWin при восстановлении сессии поднимает ИМЕННО его — с дефолтным конфигом.
#     Поэтому чужие экземпляры гасим, а не отступаем перед ними (ранняя версия скрипта
#     делала ровно наоборот и после перезагрузки на экране оставался чужой виджет);
#   * у conky нет настройки click-through — гасим область ввода отдельным скриптом,
#     иначе монитор перехватывает клики по рабочему столу.
set -u
CONF="$HOME/.config/conky/plainext.conf"

mine() {   # выводит pid'ы conky, запущенных с НАШИМ конфигом
    for pid in $(pgrep -x conky 2>/dev/null); do
        if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "$CONF"; then
            echo "$pid"
        fi
    done
}

others() { # выводит pid'ы всех прочих conky
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

# Запустить conky может не только этот скрипт: восстановление сессии KDE поднимает его
# напрямую по сохранённой команде, минуя нас. Поэтому запуск — условный, а вот
# click-through применяется ВСЕГДА, кем бы conky ни был запущен. Ранняя версия скрипта
# при виде работающего conky просто выходила — и окно оставалось ловящим клики.
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
