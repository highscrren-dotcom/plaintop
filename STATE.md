# Состояние проекта

Обновлено: **2026-10-05**, облако (Linux-контейнер, без Windows): **порт на Windows 11** —
пять виджетов на голом Qt за QML-шимами модулей Plasma и одна служба на Python (решение 17,
`win/PROTOCOL.md`). Под конец сессии — **первый запуск zip на столе пользователя**: `plaintop.exe`
упал окном `FileNotFoundError: …\spectrum\relay.py` (пути от `__file__` замороженного модуля);
починено `win/service/paths.py`, CI теперь сам запускает exe из zip. **Второй zip дошёл до окон**:
монитор живой, календарь и погода на столе; по пяти жалобам пользователя сделаны перетаскивание
(DragHandler), моноширинный запасной шрифт, `CPU(s)` для гибридных процессоров, GPU без LHM
(`gpu_win.py`), `soundcard`/`winsdk` внутри exe — всё ждёт третьего запуска. До того ночью на s1dPC:
релиз v0.5, стенды на настоящем Qt, первый CI.
Файл перезаписывается целиком в конце каждой сессии. История — в `docs/JOURNAL.md`.

## Задача следующей сессии — Windows на настоящем столе

- **Нужен пользователь (машина с Windows 11).** Путь короткий: артефакт `plaintop-win` зелёного
  прогона → распаковать → `plaintop.exe` (Defender: «Подробнее → Выполнить в любом случае»); путь из
  репозитория: `python win\build.py --qt C:\Qt\6.10.3\msvc2022_64`, `python win\plaintop.py` —
  см. `win/README.ru.md`. Второй запуск (05.10, ~03:30 UTC) показал окна; **третий** должен показать:
  перетаскивание за любую точку (клик по ячейке/кнопке остаётся им), ровные колонки без Nerd-шрифта
  (Cascadia Mono/Consolas), «20c/28t», блок GPU (имя из реестра, загрузка как в диспетчере задач,
  память; температура только у NVIDIA), спектр под музыку (`/state` → `backend: soundcard`,
  `libraries`), плеер с Яндекс Музыкой (SMTC через winsdk/winrt — если Electron её публикует). Если
  погода остаётся «offline» — спросить про прокси (XHR `qml.exe` и системный прокси). Что увидит
  только стол: окна (прозрачность,
  «под всеми», переключение `WindowTransparentForInput` на ходу, перетаскивание, меню правой
  кнопки), трей (`qml -a widget`), «за значками» (SetParent под WorkerW — в т.ч. 24H2), захват WASAPI
  (`pip install soundcard`), SMTC (`pip install winsdk`, Spotify/браузер), LHM JSON на 8085,
  `winget`/`wevtutil`/`route print`/`netsh wlan` на живом выводе, уведомление-тост и `winsound`,
  шрифт JetBrainsMono Nerd Font Mono, DPI. Записать в «Окружение» версию Windows, масштаб, Python, Qt.
- **CI `windows` зелёный** (run 37232848468 на `1c7bb06`): на настоящей Windows (Qt 6.10.3 msvc2022,
  Python 3.12) прошли `win_service` 165, `win_bands` 51, `win_media` 94, `notes.py` 145, стенд хостов
  через шимы против настоящей службы (`qml.exe`!), стенды Plasma `weather`/`monitor` на голом Qt, и
  шаг zip (windeployqt + PyInstaller) собрал `plaintop-win.zip` 58 MiB — артефакт `plaintop-win`
  (хранится до 02.01.2027). Четыре прогона до зелёного: aqt без 6.11 для Windows → 6.10; Python
  агента Qt затирал pip → Qt раньше Python; cp1252 → UTF-8; POSIX-биты в стенде заметок.
  **Новый шаг** (после падения на столе): распаковать zip и запустить сам `plaintop.exe` из чужой
  рабочей папки с `PLAINTOP_NO_HOSTS=1`, спросить `/state /monitor /bands /settings/monitor /holidays
  /time /notes /player`, убить по pid — он блокирующий, когда zip собрался. Первый прогон (run
  37258004575): exe поднялся, `/monitor /bands /state /settings` ответили — падение закрыто; `/holidays`
  упал без каталогов gettext пакета `holidays` → `--collect-data holidays`/`tzdata` в `package.py`,
  откат без перевода в `holidays_win.py`. **Второй прогон 37258346318 зелёный целиком**: exe из zip
  ответил на все восемь маршрутов (`/holidays` → 2026-07-03, 2026-07-04; `/notes dump` exit 0;
  `/time` Berlin). Артефакт для стола: run 37258346318 → `plaintop-win` (id 11323242997, 59 MiB).
- **Окно настроек готово**: `win/host/settings.qml` + 22 файла страниц (QtQuick.Controls, Fusion),
  те же поля и строки, что у диалога Plasma; `tests/win_settings.qml` 16/16 на Linux и **на Windows
  в CI** (run 37234851096 зелёный целиком). Каталоги: `extract.py` перечисляет страницы по доменам,
  +25/15/14/13/20 строк, русские переведены, fuzzy нет, 45 × `msgfmt --check`.
- **Ресерч (слово пользователя) — `docs/research/windows-widgets.ru.md`**, 64 источника. Выводы:
  Windows для виджетов на столе не даёт ничего (Widgets — только доска Win+W, MSIX); Rainmeter — не
  WorkerW, а слоистое окно на `HWND_BOTTOM` + `WS_EX_TRANSPARENT` — ровно наши флаги Qt; не хватает
  обработки Win+D (нижнее окно скрыто, пока стол показан). Принято: WorkerW — экспериментально
  (24H2, гибель с Explorer); тост — под AUMID PowerShell (иначе не покажется); **кандидат второго
  этапа мыши — `QT_QUICK_BACKEND=software`** (слоистое окно, попиксельный hit-test по альфе —
  клики проходят сквозь прозрачное, текст ловит) — настройка `softwareRender` в ini, измерить на
  столе первой; запасной — опрос курсора через службу, крайний — C++-хост с `WM_NCHITTEST`.
  Действия активных строк (`kill`, `systemctl`, `konsole`) — таблица замен в `/exec`.

## Где мы

**Plasma — без изменений по поведению**: правки общих файлов — `MonitorData.qml` (+`case "winget"`),
`CalendarView.qml`/`Sticker.qml` (`h.public` → `h["public"]`, то же по смыслу), `notes.py` (пути на
Windows, `webbrowser`). Стенды Plasma: `--check-notes` 145, `--check-relay` 21 зелёные; job `no-qt`
зелёный на `755776f`. **Впервые вне Plasma**: `tests/monitor.qml` (23) и `tests/weather.qml` (10)
проходят на голом Qt с `-import win/host/imports` — контейнер Arch для них больше не единственный путь.

**Windows (ветка `claude/eloquent-goldberg-6g14t9`):**
- `win/host/` — `monitor|spectrum|player|weather|calendar.qml` на `WidgetWindow` (модуль `plaintop`:
  `Service` — XHR с токеном, `I18n.js` — `qsTranslate("", text, ctx, n)` + `%1`), `tray.qml`,
  `calendar/Holidays.qml` (своя: `/holidays`), `imports/org/kde/*` — шимы. Общие файлы копирует
  `win/build.py` (gitignored), он же собирает 45 `.qm` (`lconvert -target-language`).
- `win/service/` — `server.py` (маршруты, токен, Origin → 403), `monitor_win.py` (psutil + LHM →
  id ksystemstats), `exec_win.py` (эмуляция команд монитора), `bands.py` (WASAPI loopback → FFT,
  кадр в порядке cava), `player_win.py` (SMTC), `notes_bridge.py`, `holidays_win.py`, `timezones.py`,
  `settings_store.py` (ini по `main.xml` + `shown/winX/winY/screen/behindIcons/softwareRender`,
  умолчания Windows: `actions=false`), `ui.py` (qml.exe, `--transparent`, `-a widget` для трея,
  WorkerW, `QT_QUICK_BACKEND=software` по `softwareRender`), `notify_win.py` (тост под AUMID
  PowerShell, `winsound`), **`paths.py`** — обе раскладки файлов (дерево / рядом с exe), корень по
  `PLAINTOP_ROOT` → `sys.frozen` → дерево; через него ходят все модули; **`gpu_win.py`** — GPU без
  LHM: `GPU Engine`/`GPU Adapter Memory` через pdh.dll (ctypes, `PdhAddEnglishCounter`), имя и
  qwMemorySize из реестра, `nvidia-smi`; `Sampler(gpu=)` сливает под LHM. `win/plaintop.py` — запуск;
  `win/package.py` — zip (`paths`, `soundcard` с данными, `winsdk`/`winrt-*` — что установлено при
  сборке; CI ставит их отдельным необязательным шагом).
- `WidgetWindow`: `fixedFace(key)` — настроенный шрифт или первый моноширинный из списка Windows
  («monospace» там не семейство); `DragHandler` в `Window` — протяжка за любую точку поверх MouseArea
  вида (в элементе над видом глотает нажатие — грабля). Спектр при `backend: none` пишет «нет захвата».
- `exec_win.lscpu` печатает `CPU(s)`; `MonitorData.parseLscpu` (общий файл) берёт его вместо
  произведения — на гибридных Intel произведение врёт и на Plasma (20c/40t).
- Стенды: `tests/win_hosts.py`+`.qml` 9/9 (6.8.3, 6.10.1, 6.11.3, настоящая служба на Linux),
  `win_service.py` 167, `win_bands.py` 51, `win_media.py` 94.
- Документы: решение 17 EN/RU, GOTCHAS часть III (10 записей, EN/RU, оглавление; последняя —
  `__file__` замороженного модуля), `win/README` пара, README пара (раздел Windows), CONTRIBUTING
  пара, `win/PROTOCOL.md` (EN, в т.ч. `/notify`).

**Проверено на столе пользователя (второй zip)**: окна рисуются, монитор на настоящих данных
(процессы, winget, службы, журнал), календарь, погода («offline» — см. вопрос), плеер («no player»
без WinRT). **Проверено на Windows только в CI (offscreen, без стола)**: служба целиком на
psutil/winreg/`wevtutil`, `qml.exe` грузит хосты и шимы, zip собирается, exe из zip отвечает. **Раскладка zip проверена на Linux**:
служба с `PLAINTOP_ROOT=<папка как zip>` из `/` отвечает на `/monitor`, `/bands` (реле из папки),
`/settings/monitor` (xml из `service/config`), `/holidays`, `/notes set/dump` (notes.py из
`calendar/`). **Не проверено нигде**: всё, что перечислено в задаче сессии выше (стол), плюс
`CREATE_NO_WINDOW`, pycaw, PowerShell-зонды батареи и Bluetooth, стоимость
`psutil.win_service_iter()`; pdh.dll/реестр/`nvidia-smi` (`gpu_win.py`) — только CI, у runner'а
карты может не быть; `soundcard`/`winsdk` внутри exe — CI печатает `libraries` и `/player`;
DragHandler и шрифты — на столе.

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
  `windows` job блокирующий, кроме шага zip; прогон exe из zip блокирующий, когда zip собрался.

## Открытые вопросы

- Google в календаре: свои client id/secret у каждого — приемлемо ли для магазина.
- Умолчание «Каналы: включено» у спектра для тех, кто обновится.
- Windows: `QtCore.Settings` против ini у службы — задача называла QSettings; выбран один владелец
  (решение 5), ключи те же; пересмотреть, если пользователь захочет реестр.
- Windows: имена праздников пакета `holidays` против KHolidays (21 из 29) — показывать как есть?
- Windows: погода «offline» на столе пользователя — `qml.exe` и системный прокси (корпоративная
  сеть?); если да — погоду через службу (`urllib` читает прокси из реестра) или `QT_...`-переменная.
- Windows: GPU — порядок карт у счётчиков (LUID), реестра и `nvidia-smi` свой у каждого; с одной
  картой совпадает, с двумя может назвать не ту; точнее — DXGI через ctypes (LUID + имя + память).

## Окружение

s1dPC: CachyOS, Plasma 6.7.5, KDE Frameworks 6.30, KWin Wayland, Qt 6.11.2, Python 3.14; два экрана
(DP-1 3440×1440, HDMI-A-1 1080×1920); `cava` 1.0.0, `lm_sensors`, gettext. Подробности прежних сессий —
`docs/JOURNAL.md` (04–05.10). Windows-машина пользователя: Windows 11 Enterprise 10.0.22631 (23H2), Dell (плата 0H1DC6, BIOS
1.18.0), i7-14700 (20c/28t, 2,1 GHz), 31,7 GiB, два сетевых адаптера; LHM нет, Nerd-шрифта нет,
Яндекс Музыка (десктоп), Firefox, Fusion 360; масштаб DPI и видеокарта — пока неизвестны.
Облако: Ubuntu 24.04, Python 3.11, Qt через aqtinstall в `/opt/qt`, сеть через прокси (XHR из `qml`
дошёл до Open-Meteo).

⚠️ Метод работы — `docs/WORKFLOW.md`, грабли — `docs/GOTCHAS.md` (часть III — Windows).
