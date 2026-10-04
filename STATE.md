# Состояние проекта

Обновлено: **2026-10-05**, облако (Linux-контейнер, без Windows): **порт на Windows 11** —
пять виджетов на голом Qt за QML-шимами модулей Plasma и одна служба на Python (решение 17,
`win/PROTOCOL.md`). До того ночью на s1dPC: релиз v0.5, стенды на настоящем Qt, первый CI.
Файл перезаписывается целиком в конце каждой сессии. История — в `docs/JOURNAL.md`.

## Задача следующей сессии — Windows на настоящем столе

- **Нужен пользователь (машина с Windows 11).** `python win\build.py --qt C:\Qt\6.10.3\msvc2022_64`,
  `python win\plaintop.py` — см. `win/README.ru.md`. Что увидит только стол: окна (прозрачность,
  «под всеми», переключение `WindowTransparentForInput` на ходу, перетаскивание, меню правой
  кнопки), трей (`qml -a widget`), «за значками» (SetParent под WorkerW — в т.ч. 24H2), захват WASAPI
  (`pip install soundcard`), SMTC (`pip install winsdk`, Spotify/браузер), LHM JSON на 8085,
  `winget`/`wevtutil`/`route print`/`netsh wlan` на живом выводе, уведомление-тост и `winsound`,
  шрифт JetBrainsMono Nerd Font Mono, DPI. Записать в «Окружение» версию Windows, масштаб, Python, Qt.
- **CI `windows`**: первый прогон упал на `install-qt-action` (aqt не видит архивов 6.11 для
  Windows), второй — на Qt 6.10 — запущен пушем `d335735`; проверить итог и логи
  (`Actions → checks`). Шаг «the zip (advisory)» (windeployqt + PyInstaller) совещательный, артефакт
  `plaintop-win`.
- **Окно настроек** `win/host/settings.qml` (+ `tests/win_settings.qml`) делал агент — проверить,
  что доехало, прогнать стенд, закоммитить; затем `python3 po/extract.py` (новые строки хостов, трея,
  окна настроек — источники уже перечислены в `DOMAINS`), русские переводы к ним, `msgfmt --check`.
- **Второй этап мыши**: активные строки, кнопки плеера и ячейки календаря при сквозных кликах.
  Кандидат без C++: служба отдаёт `GetCursorPos`, хост опрашивает и снимает
  `TransparentForInput` над активным прямоугольником; иначе — маленький C++-хост с `WM_NCHITTEST`.
  Действия активных строк (`kill`, `systemctl`, `konsole`) — таблица замен в `/exec`.

## Где мы

**Plasma — без изменений по поведению**: правки общих файлов — `MonitorData.qml` (+`case "winget"`),
`CalendarView.qml`/`Sticker.qml` (`h.public` → `h["public"]`, то же по смыслу), `notes.py` (пути на
Windows, `webbrowser`). Стенды Plasma: `--check-notes` 145, `--check-relay` 21 зелёные; job `no-qt`
зелёный на `755776f`. **Впервые вне Plasma**: `tests/monitor.qml` (23) и `tests/weather.qml` (10)
проходят на голом Qt с `-import win/host/imports` — контейнер Arch для них больше не единственный путь.

**Windows (ветка `claude/eloquent-goldberg-6g14t9`, 3 коммита):**
- `win/host/` — `monitor|spectrum|player|weather|calendar.qml` на `WidgetWindow` (модуль `plaintop`:
  `Service` — XHR с токеном, `I18n.js` — `qsTranslate("", text, ctx, n)` + `%1`), `tray.qml`,
  `calendar/Holidays.qml` (своя: `/holidays`), `imports/org/kde/*` — шимы. Общие файлы копирует
  `win/build.py` (gitignored), он же собирает 45 `.qm` (`lconvert -target-language`).
- `win/service/` — `server.py` (маршруты, токен, Origin → 403), `monitor_win.py` (psutil + LHM →
  id ksystemstats), `exec_win.py` (эмуляция команд монитора), `bands.py` (WASAPI loopback → FFT,
  кадр в порядке cava), `player_win.py` (SMTC), `notes_bridge.py`, `holidays_win.py`, `timezones.py`,
  `settings_store.py` (ini по `main.xml` + `shown/winX/winY/screen/behindIcons`, умолчания Windows:
  `actions=false`), `ui.py` (qml.exe, `--transparent`, `-a widget` для трея, WorkerW), `notify_win.py`.
  `win/plaintop.py` — запуск; `win/package.py` — zip (не запускался).
- Стенды: `tests/win_hosts.py`+`.qml` 9/9 (6.8.3, 6.10.1, 6.11.3, настоящая служба на Linux),
  `win_service.py` 167, `win_bands.py` 51, `win_media.py` 94.
- Документы: решение 17 EN/RU, GOTCHAS часть III (9 записей, EN/RU, оглавление), `win/README` пара,
  README пара (раздел Windows), CONTRIBUTING пара, `win/PROTOCOL.md` (EN).

**Не проверено нигде** (нет Windows): всё, что перечислено в задаче сессии выше, плюс
`windeployqt`/PyInstaller в `package.py`, `CREATE_NO_WINDOW`, `platform.win32_edition()`, pycaw,
PowerShell-зонды батареи и Bluetooth, PnP-батареи, `psutil.win_service_iter()` стоимость.

⚠️ Qt локально в контейнере: `/opt/qt/{6.8.3,6.10.1,6.11.3}/gcc_64`; стенды — `QT_QPA_PLATFORM=offscreen
LC_ALL=C.UTF-8 QT_FORCE_STDERR_LOGGING=1`. Заменитель службы для стендов без Python-службы остался в
scratchpad сессии (не в репозитории). Никогда `pkill -f` — убил собственную оболочку.

## Потом

- Прежние пункты Plasma: менеджер дизайнов, активные строки дальше (часы → календарь), заметки (todo),
  напоминания (клавиатура у листа), праздники (переносы выходных), погода (`timezone`, строка «сейчас»),
  общий `Sheet.qml`/`Passthrough.qml`, магазин по `docs/STORE.md` (plaintop 0.5, plaincalendar 0.3).
- Windows дальше: пакеты в zip по релизу; палитры (`palettes/palette.py` → ini через `/settings`);
  второй экземпляр виджета; `qml-stands.yml` можно заменить прогоном на голом Qt через шимы для
  `monitor.qml`/`weather.qml` (`passthrough.qml` требует Plasma).

## Что уже решено, не пересматривать без причины

- Движок — плазмоид (1). Данные — ksystemstats (2). Визуализатор свой (4). Датчики находятся сами (6).
  Переводы — ki18n (7). Сквозные клики — самим плазмоидом (8), окна погашены (9) — **на Plasma**.
- Погода — прямые запросы из QML (10), источники за абстракцией, Яндекс нет (13). Плеер: маска по
  кнопкам (11), в спектре опцией и отдельным виджетом (12). Активные строки (14). Заметки и напоминания
  (15). Праздники (16).
- **Windows (17)**: общие файлы не трогать — шимы `org.kde.*` на чистом QML; одна служба, она же
  владелец настроек и процессов; без C++, пока хит-тест не докажет обратное; Qt 6.8+; службе —
  токен и отказ по `Origin`; общие строки хостов — во всех пяти каталогах (`po/extract.py`).
- Чужие ветки вливаются слиянием, локальные коммиты не переписываются. Никогда не `pkill -f`.
  Звук для проверок — только через null-sink. Один ключ `install.sh` за вызов. CI без Qt блокирующий;
  `windows` job блокирующий, кроме шага zip.

## Открытые вопросы

- Google в календаре: свои client id/secret у каждого — приемлемо ли для магазина.
- Умолчание «Каналы: включено» у спектра для тех, кто обновится.
- Windows: `QtCore.Settings` против ini у службы — задача называла QSettings; выбран один владелец
  (решение 5), ключи те же; пересмотреть, если пользователь захочет реестр.
- Windows: имена праздников пакета `holidays` против KHolidays (21 из 29) — показывать как есть?

## Окружение

s1dPC: CachyOS, Plasma 6.7.5, KDE Frameworks 6.30, KWin Wayland, Qt 6.11.2, Python 3.14; два экрана
(DP-1 3440×1440, HDMI-A-1 1080×1920); `cava` 1.0.0, `lm_sensors`, gettext. Подробности прежних сессий —
`docs/JOURNAL.md` (04–05.10). Windows-машина: **нет данных** — заполнить при первом запуске (версия,
масштаб DPI, Python, Qt, LHM, шрифт).
Облако: Ubuntu 24.04, Python 3.11, Qt через aqtinstall в `/opt/qt`, сеть через прокси (XHR из `qml`
дошёл до Open-Meteo).

⚠️ Метод работы — `docs/WORKFLOW.md`, грабли — `docs/GOTCHAS.md` (часть III — Windows).
