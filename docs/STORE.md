# KDE Store listings

The text for the widget pages on [store.kde.org](https://store.kde.org), kept here so
the pages can be updated along with the code. A store page has one description field,
so each description carries both languages — English first, Russian below — and this file
is not split into an `.ru.md` pair.

The files to upload are built by:

```bash
./install.sh --pack     # → dist/{plaintop,plainspectrum,plainplayer,plainweather,plaincalendar}-<version>.plasmoid
```

`--pack` installs each archive into a throwaway package root before reporting success,
so what it builds is known to install. The version in the file name comes from each
widget's `metadata.json`; bump it there before building a new upload.

⚠️ Updated to 0.2 on 2026-09-22 (13:54 and 13:55 UTC in the store's API): the pages carry the
text below, `plaintop-0.2.plasmoid` and `plainspectrum-0.2.plasmoid` (MD5 equal to the
built files); the 0.1 files are still listed beside them.

⚠️ Uploaded 2026-09-24 (06:09–06:17 UTC by the store's `changed` fields), verified over the
store's API at 07:09 UTC: plaintop 0.3 and plainspectrum 0.3 updated, plainplayer 0.1
(https://store.kde.org/p/2373633/, Plasma 6 Multimedia) and plainweather 0.1
(https://store.kde.org/p/2373634/, Plasma 6 Weather) created; every listed file's MD5 equals
the file in the Desktop kit, whose unpacked content equals the current build. ⚠️ The API lagged
the site by about an hour this time (at 06:48 UTC it still showed the old versions) — Plasma's
*Download New Widgets* reads the API, so an update shows up there with that delay. The CDN
answered 429 to downloads through the tunnel, so the check went by MD5 fields, not downloads.
GitHub release v0.3 carries all four packages, verified by download (sha256).

## Uploading

The store is run by Pling, not by KDE; there is no review before a product goes live.

- **Account:** an opendesktop.org (Pling) account; KDE Identity is not used.
- **Add Product:** https://store.kde.org/product/add.
- **Category matters:** Plasma 6's *Get New Widgets…* reads *Plasma 6 Extensions*
  (`Categories=Plasma 6 Extensions` in `/usr/share/knsrcfiles/plasmoids.knsrc`) — a Plasma 5
  category or *System Monitor 6 Applets* never shows up there.
- **Title:** letters, digits and a few signs only — `plaintop`, `plainspectrum`.
- **Description:** plain text works; BBCode (`[b]`, `[url]`, `[list]`…) is supported.
- **Images:** a logo and gallery pictures; the gallery is shown at 770×540, so a landscape
  picture fits better than the tall widget.
- **An update:** bump `Version` in `metadata.json`, run `--pack`, upload the new file and
  bump the product's version. Plasma offers the update when the store version changes,
  and kpackage refuses to install a `Version` that is not newer.

## plaintop — text system monitor

Published 2026-09-22: https://store.kde.org/p/2372814/

**0.3 — uploaded 2026-09-24.** What's new: three block types — pressure stall information
(PSI) for CPU, memory and I/O; the battery, shown only where one exists; system health —
failed systemd units, errors since boot and the last error lines of the journal. Separators
collapse where a block hides, so no double rules. The description below already says so.
And a small one: in the disks block the root mount is labelled `root` instead of `/` —
beside a bar made of slashes, `/` read as part of the bar.

**0.4 — uploaded 2026-10-04** (06:38 UTC by the store's `changed` field; the listed file's
MD5 equals the Desktop kit's). What's new: thresholds — a bar past its "alert from" turns red,
the model line too by temperature; sparklines after the bars (the "history" parameter);
new blocks — swap, load average, disk I/O, temperatures of any sensors, systemd units,
peripheral batteries (upower), sound (wpctl), git repositories, text and blank lines; the
network block's address, totals and Wi-Fi signal; the CPU's average frequency; podman,
libvirt and the apt, dnf, zypper and flatpak update counts beside pacman; a pending reboot
in system health; every GPU, and none on a machine without one; the clock in 12 or 24 hours;
the bars' width and characters and the separator as settings; a second column; on the
Blocks page the machine's own sensors, interfaces and mount points to pick from, a
duplicate button, a name per block, and the layout as JSON to edit or paste. Fixed: the
model line's "62/0°C" on a one-node machine and the redundant node line there; the GPU's
power on AMD cards, which read "pwr 0W"; sparkline glyphs half a step too high.

**0.5 — not uploaded yet.** What's new: active lines — a left click runs what a line is
about (a bar opens System Monitor, a disk its folder, a systemd unit its status, a process
asks before it is terminated, the sound line toggles mute, the uptime line locks, logs out,
reboots or powers off after a question, the header opens the settings), a right click lists
every action in a menu framed with characters in the widget's own font; the line under the
pointer gets a frame; a block's lines can be switched off or given a command of your own
with the row's values filled in; while clicks pass through, only the active lines take the
mouse. Settings for the terminal and the editor the actions use, the menu's frame and paper.
Checked on the desktop 2026-10-04; the gallery picture shows the menu.

- **File:** `dist/plaintop-<version>.plasmoid`
- **Category:** Plasma 6 Extensions → Monitoring
- **License:** GPL-2.0-or-later
- **Source / homepage:** https://github.com/highscrren-dotcom/plaintop
- **Tags:** system monitor, conky, rainmeter, text, sensors, cpu, gpu, numa, battery, systemd, psi
- **Images:** a square logo of the clock and a landscape gallery picture of the whole
  monitor, both rendered offscreen by the real renderer in an English session

**Summary:** A text system monitor for the desktop, in the spirit of the PlainExt Rainmeter skin.

**Description:**

```
A monospace, text-only system monitor for the Plasma 6 desktop, in the spirit of the
PlainExt skin for Rainmeter: clock and date, system, CPU load overall and per NUMA node,
the processor with temperatures and fan speeds, pressure stall information (PSI), top
processes by CPU and by memory, RAM, GPU with VRAM, disks with NVMe temperature, uptime,
network, the battery where there is one, docker/ollama/updates, system health — failed
systemd units, errors since boot, the last journal errors — and a hardware spec sheet.

Also on offer: swap, load average, disk I/O, temperatures of any sensors, systemd units,
batteries of wireless devices (upower), the sound device's volume, git repositories, plain text
and blank lines. A bar can turn red past a threshold and draw a sparkline of its recent
values after it, and blocks can go into a second column.

The blocks, their order and their parameters are set on the Blocks page of the
settings, where the machine's own sensors, interfaces and mount points are offered in
lists, a block can be duplicated and named, and the whole layout can be edited or pasted
as JSON; a block can also be any ksystemstats sensor or any command. Sensors specific to
a machine — fans, NVMe, the network interface — are found on the machine itself.
Data comes from ksystemstats, the same service as Plasma's System Monitor.

The interface follows Plasma's language: English, Russian, Ukrainian, German, French,
Spanish, Brazilian Portuguese, Polish, Simplified Chinese, Japanese — all but English and
Russian machine-translated, corrections welcome. The updates line reads pacman and
flatpak; apt, dnf and zypper are read too but not yet tried on those systems.

The lines are active: a left click runs what a line is about — a bar opens System
Monitor, a disk its folder, a process asks before it is terminated, the sound line toggles
mute, the header opens the settings — and a right click lists every action of the line in
a menu framed with characters, in the widget's own font. A block's lines can be switched
off or given a command of your own. Out of the box the widget takes clicks like any other;
General → Mouse lets both buttons through to the desktop everywhere but on the active
lines, and the widget moves and resizes in the desktop's edit mode. Source and details:
https://github.com/highscrren-dotcom/plaintop, devlog: https://t.me/s1dd1_logs

———

Текстовый монитор системы для рабочего стола Plasma 6 в духе скина PlainExt для
Rainmeter: часы и дата, система, загрузка CPU общая и по узлам NUMA, процессор с
температурами и оборотами, данные о простоях (PSI), топ процессов по CPU и памяти, ОЗУ,
GPU с VRAM, диски с температурой NVMe, аптайм, сеть, батарея, если она есть,
docker/ollama/обновления, здоровье системы — упавшие юниты systemd, ошибки с загрузки,
последние ошибки журнала — и паспорт железа.

Ещё есть своп, средняя нагрузка, ввод-вывод дисков, температуры любых датчиков, юниты
systemd, батареи беспроводных устройств (upower), громкость звукового устройства, репозитории git, просто
текст и пустые строки. Полоска может краснеть за порогом и рисовать после себя спарклайн
недавних значений, а блоки — уходить во вторую колонку.

Набор блоков, порядок и параметры — на странице «Блоки» в настройках: там датчики,
интерфейсы и точки монтирования этой машины предлагаются списками, блок можно
продублировать и назвать, а всю раскладку — править или вставить как JSON; блоком может быть
любой датчик ksystemstats или любая команда. Привязанные к машине датчики — вентиляторы,
NVMe, сетевой интерфейс — находятся на самой машине. Данные берутся у ksystemstats — той
же службы, что у «Системного монитора» Plasma. Интерфейс говорит на языке Plasma: английский,
русский, украинский, немецкий, французский, испанский, португальский (Бразилия), польский,
китайский и японский — всё, кроме английского и русского, переведено машинно, исправления
приветствуются. Строка обновлений читает pacman и flatpak; apt, dnf и zypper тоже
читаются, но на этих системах ещё не опробованы.

Строки активны: левый клик делает то, о чём строка, — полоска открывает «Системный
монитор», диск — свою папку, процесс спрашивает, прежде чем его завершить, строка звука
переключает тишину, заголовок открывает настройки, — а правый клик показывает все действия
строки в меню в рамке из символов, шрифтом виджета. Строки блока можно выключить или дать им
свою команду. Сразу после установки виджет ловит клики, как любой другой; «Общее → Мышь»
пропускает на рабочий стол обе кнопки везде, кроме активных строк, а двигается и меняет
размер виджет в режиме правки рабочего стола. Исходники и подробности:
https://github.com/highscrren-dotcom/plaintop, дневник разработки: https://t.me/s1dd1_logs
```

## plainspectrum — audio visualizer

Published 2026-09-22: https://store.kde.org/p/2372815/

**0.3 — uploaded 2026-09-24.** What's new: the player in the centre of the ring — the
plainplayer view on a new *Player* page, off by default, with the player's own font, width
and colours; on a line it goes along the edge the bars reach last. With *Mouse* on, only
the player's controls row takes clicks, the rest of the widget lets them through. The
description below already says so.

**0.4 — uploaded 2026-10-04** (06:40 UTC; MD5 equal to the Desktop kit's). What's new: a
*Channels* switch on the *Ring* page, on by
default — one spectrum around the whole ring, both channels averaged by the relay; off
keeps cava's stereo frame, which is mirrored about its middle. Needs the relay from this
version (`./install.sh --spectrum`): an older relay ignores the request and serves the
mirrored frame.

- **File:** `dist/plainspectrum-<version>.plasmoid`
- **Category:** Plasma 6 Extensions → Multimedia
- **License:** GPL-2.0-or-later
- **Source / homepage:** https://github.com/highscrren-dotcom/plaintop
- **Tags:** audio, visualizer, spectrum, cava, music
- **Images:** the ring while music plays — it dissolves in silence, so a picture needs sound

**Summary:** An audio visualizer in the spirit of PlainExt: a ring, an arc or a line. Needs its cava relay.

**Description:**

```
plainspectrum — an audio visualizer for the Plasma 6 desktop, in the plain style of the
PlainExt Rainmeter skin: one colour, square ends, no gradients, no glow. It draws the
spectrum of whatever is playing as bars around a ring, along an arc or on a line, right
on the wallpaper.

What you can set (right-click → Configure):
• Shape — ring or line (a ring with a span under 360° is an arc), number of bars, radius,
  span and start angle, bar thickness and gaps, length at silence and at maximum, growth
  outward / inward / both ways (up / down on a line), mirrored or reversed band order,
  and Channels — one spectrum around the whole ring, or cava's stereo frame, mirrored
  about its middle.
• Appearance — solid bars or a ladder of blocks, rounded ends, colour, a second colour
  for the high frequencies, opacity, a thin guide circle.
• Behaviour — data frames per second and smoothing. In silence the ring dissolves and
  grows back out of itself when the sound returns; while hidden it polls four times a
  second instead of thirty.
• Player — the "now playing" lines of plainplayer in the centre of the ring (along the
  edge on a line): player, artist — title, album, a slash bar with the position, and the
  <<  >  >> controls, in their own font and colours. Off by default; the ring keeps its
  size, and with no player on the bus the centre stays empty.

Light by design: the bars are ready-made rectangles moved by the scene graph and nothing
is rasterized per frame, so the graphics card stays almost idle. Out of the box the
widget takes clicks like any other; Behaviour → Mouse lets both buttons through to the
desktop — except on the player's controls, when the player is shown: those stay
clickable — and the widget takes the mouse only in the desktop's edit mode — where its
settings are.

⚠️ The widget alone draws nothing. The spectrum is computed by cava in a small relay
service (Python, a systemd user unit) that a widget cannot install by itself:

  git clone https://github.com/highscrren-dotcom/plaintop
  cd plaintop
  ./install.sh --spectrum      (install cava first)

Without the relay the widget says so instead of staying blank. The audio device and the
frequency range are set in ~/.config/plainspectrum/relay.env.

The interface follows Plasma's language — ten languages, all but English and Russian
machine-translated, corrections welcome.

Source, issues, details: https://github.com/highscrren-dotcom/plaintop,
devlog: https://t.me/s1dd1_logs

———

plainspectrum — визуализатор звука для рабочего стола Plasma 6 в простом стиле скина
PlainExt для Rainmeter: один цвет, прямые концы, без градиентов и свечения. Рисует спектр
того, что играет, штрихами по кольцу, по дуге или по линии — прямо на обоях.

Что настраивается (правый клик → Настроить):
• Форма — кольцо или линия (кольцо с охватом меньше 360° — дуга), число штрихов, радиус,
  охват и начальный угол, толщина штрихов и зазоры, длина в тишине и на максимуме, рост
  наружу / внутрь / в обе стороны (у линии — вверх / вниз), зеркальный или обратный
  порядок полос и «Каналы» — один спектр по всему кольцу или стереокадр cava, зеркальный
  относительно середины.
• Вид — сплошные штрихи или лесенка из блоков, скруглённые концы, цвет, второй цвет для
  высоких частот, непрозрачность, тонкая направляющая окружность.
• Поведение — кадров данных в секунду и сглаживание. В тишине кольцо растворяется и
  вырастает из самого себя, когда звук возвращается; пока оно скрыто, опрос идёт четыре
  раза в секунду вместо тридцати.
• Плеер — строки «сейчас играет» из plainplayer в центре кольца (у линии — вдоль края):
  плеер, исполнитель — название, альбом, полоса из косых с позицией и кнопки <<  >  >>,
  своим шрифтом и цветами. По умолчанию выключен; кольцо размера не меняет, а без плеера
  на шине центр остаётся пустым.

Лёгкий по устройству: штрихи — готовые прямоугольники, их двигает граф сцены, покадровой
растеризации нет, и видеокарта почти не нагружается. Сразу после установки виджет ловит
клики, как любой другой; «Поведение → Мышь» пропускает на рабочий стол обе кнопки — кроме
кнопок плеера, когда он показан: они остаются нажимаемыми, — а мышь виджет берёт только в
режиме правки рабочего стола — там же и его настройки.

⚠️ Сам по себе виджет ничего не рисует. Спектр считает cava в маленькой службе-реле
(Python, пользовательский юнит systemd), которую виджет поставить не может:

  git clone https://github.com/highscrren-dotcom/plaintop
  cd plaintop
  ./install.sh --spectrum      (сначала поставьте cava)

Без реле виджет прямо об этом пишет, а не остаётся пустым. Звуковое устройство и диапазон
частот задаются в ~/.config/plainspectrum/relay.env.

Интерфейс говорит на языке Plasma — десять языков, всё, кроме английского и русского,
переведено машинно, исправления приветствуются.

Исходники, вопросы, подробности: https://github.com/highscrren-dotcom/plaintop,
дневник разработки: https://t.me/s1dd1_logs
```

## plainplayer — now playing

Published 2026-09-24: https://store.kde.org/p/2373633/ (category Plasma 6 Multimedia)

- **File:** `dist/plainplayer-<version>.plasmoid`
- **Category:** Plasma 6 Extensions → Multimedia
- **License:** GPL-2.0-or-later
- **Source / homepage:** https://github.com/highscrren-dotcom/plaintop
- **Tags:** mpris, now playing, music, player, media, text
- **Images:** the five lines while a track plays — without a player it says "no player",
  so a picture needs music

**Summary:** What is playing, as plain text: track, a slash position bar and text controls, in the plaintop style.

**Description:**

```
plainplayer — "now playing" for the Plasma 6 desktop as plain monospace text, in the
style of the plaintop monitor: no frames, no cover art. Five lines: a header with the
player's name, artist — title, the album, a slash bar with the position and the time,
and the controls <<  >  >> — text with a mouse area under each glyph. Previous,
play/pause and next work with a click; a control the player cannot do is dimmed.

It reads MPRIS through the module behind Plasma's own media controller, so whatever
Plasma's controller sees, it sees: VLC, Spotify, a browser. Nothing to install beyond
the widget. The Player setting pins it to one player by name (vlc, spotify,
strawberry); empty means whoever is playing.

Settings (right-click → Configure): font, size, width in characters, three colours,
the album line and the controls row on or off, the player filter. The Mouse page lets
both buttons through to the desktop like the other plaintop widgets — except on the
controls row: <<  >  >> stay clickable, and a click anywhere else on the widget lands
on the desktop. The same lines can be shown in the centre of the plainspectrum ring,
as an option there.

The interface follows Plasma's language — ten languages, all but English and Russian
machine-translated, corrections welcome.

Source, issues, details: https://github.com/highscrren-dotcom/plaintop,
devlog: https://t.me/s1dd1_logs

———

plainplayer — «сейчас играет» для рабочего стола Plasma 6 простым моноширинным текстом,
в стиле монитора plaintop: без рамок и обложек. Пять строк: заголовок с именем плеера,
исполнитель — название, альбом, полоса из косых с позицией и временем и кнопки
<<  >  >> — текст с областью мыши под каждым знаком. Назад, пуск/пауза и вперёд
работают по клику; то, чего плеер не умеет, показано приглушённо.

MPRIS он читает через модуль штатного медиаконтроллера Plasma, так что видит всё, что
видит контроллер Plasma: VLC, Spotify, браузер. Ставить сверх виджета ничего не нужно.
Настройка «Плеер» привязывает его к одному плееру по имени (vlc, spotify, strawberry);
пустая — показан тот, кто играет.

Настройки (правый клик → Настроить): шрифт, кегль, ширина в знаках, три цвета, строка
альбома и строка кнопок вкл/выкл, фильтр плеера. Страница «Мышь» пропускает на стол обе
кнопки, как у других виджетов plaintop, — кроме строки кнопок: <<  >  >> остаются
нажимаемыми, а клик в любом другом месте виджета попадает на стол. Те же строки можно
показать в центре кольца plainspectrum — там это настройка.

Интерфейс говорит на языке Plasma — десять языков, всё, кроме английского и русского,
переведено машинно, исправления приветствуются.

Исходники, вопросы, подробности: https://github.com/highscrren-dotcom/plaintop,
дневник разработки: https://t.me/s1dd1_logs
```

## plainweather — weather

Published 2026-09-24: https://store.kde.org/p/2373634/ (category Plasma 6 Weather)

- **File:** `dist/plainweather-<version>.plasmoid`
- **Category:** Plasma 6 Extensions → Online Services
- **License:** GPL-2.0-or-later
- **Source / homepage:** https://github.com/highscrren-dotcom/plaintop
- **Tags:** weather, forecast, open-meteo, met.no, weatherapi, text
- **Images:** the header, the current line and three forecast rows — needs a location set
  or guessed, and a network

**Summary:** The weather as plain text — now and the next days — from Open-Meteo, in the plaintop style. Weather data by Open-Meteo.com.

**Description:**

```
plainweather — the weather for the Plasma 6 desktop as plain monospace text, in the
style of the plaintop monitor: no frames, no graphics. A header with the place, the
current conditions — temperature, a word for the sky, what it feels like, wind and
humidity — and one row per forecast day, 0 to 7, with the low, the high, the sky and
the chance of rain. Left of those, the current sky as a picture made of characters in
the widget's own font — sun, cloud, rain, snow, fog, lightning; it can be turned off.

The data comes from one of four sources, chosen in the settings: Open-Meteo (the
default) and MET Norway need no key; WeatherAPI.com and Visual Crossing take a free key
from your own account, pasted into the widget. The widget asks the source itself over
https, every 15 minutes (30 for Visual Crossing), one request — no service of its own,
nothing to install beyond the widget, and it needs network access to that source's host;
if one host is unreachable from your network, switch the source. The last answer is kept,
so the widget draws at once after a shell restart and stays through an outage, marked
"offline"; a key the source refuses is marked "bad key". The place: search a city on the
Location page (a click stores it) or type "latitude, longitude"; until one is set, the
widget guesses the city from the time zone and says so in the header. It never asks a
geolocation service where you are. Units follow the locale (°F and mph in the US) or are
chosen by hand.

Every source's terms ask for attribution — the last line of the widget names the source
in use, on by default: Weather data by Open-Meteo.com (free for non-commercial use, CC BY
4.0); Weather data from MET Norway (CC BY 4.0); Powered by WeatherAPI.com; Weather data
provided by Visual Crossing.

Right-click → Configure: font, size, width, three colours; source and key, location,
units, days, the attribution line; the Mouse page lets both buttons through to the
desktop like the other plaintop widgets. The interface follows Plasma's language — ten
languages, all but English and Russian machine-translated, corrections welcome.

Source, issues, details: https://github.com/highscrren-dotcom/plaintop,
devlog: https://t.me/s1dd1_logs

———

plainweather — погода для рабочего стола Plasma 6 простым моноширинным текстом, в стиле
монитора plaintop: без рамок и графики. Заголовок с местом, текущие условия —
температура, слово про небо, «ощущается», ветер и влажность — и по строке на день
прогноза, от 0 до 7: минимум, максимум, небо и вероятность осадков. Слева от строк —
текущее небо картинкой из символов шрифта самого виджета: солнце, облако, дождь, снег,
туман, молния; её можно выключить.

Данные — из одного из четырёх источников, выбранного в настройках: Open-Meteo (по
умолчанию) и MET Norway без ключа; WeatherAPI.com и Visual Crossing — с бесплатным ключом
из вашей учётной записи, вписанным в виджет. Виджет сам запрашивает источник по https раз
в 15 минут (у Visual Crossing — раз в 30), одним запросом — своей службы нет, ставить
сверх виджета ничего не нужно, нужен лишь доступ по сети к хосту этого источника; если
один хост из вашей сети недостижим, переключите источник. Последний ответ хранится, так
что после перезапуска оболочки виджет рисуется сразу и переживает обрыв сети с пометкой
«офлайн»; ключ, который источник отверг, помечается «неверный ключ». Место: поиск города
на странице «Место» (клик сохраняет) или введённые «широта, долгота»; пока оно не задано,
виджет угадывает город по часовому поясу и говорит об этом в заголовке. Где вы
находитесь, у служб геолокации он не спрашивает. Единицы — по локали (в США °F и mph)
или вручную.

Условия каждого источника просят указывать его — последняя строка виджета называет тот,
что используется, включена по умолчанию: «Данные о погоде: Open-Meteo.com» (бесплатно
для некоммерческого использования, CC BY 4.0); «Данные о погоде: MET Norway» (CC BY 4.0);
«При поддержке WeatherAPI.com»; «Данные о погоде: Visual Crossing».

Правый клик → Настроить: шрифт, кегль, ширина, три цвета; источник и ключ, место,
единицы, дни, строка источника; страница «Мышь» пропускает на стол обе кнопки, как у
других виджетов plaintop. Интерфейс говорит на языке Plasma — десять языков, всё, кроме
английского и русского, переведено машинно, исправления приветствуются.

Исходники, вопросы, подробности: https://github.com/highscrren-dotcom/plaintop,
дневник разработки: https://t.me/s1dd1_logs
```

## plaincalendar — calendar

Published 2026-10-04: https://store.kde.org/p/2377077/ (category Plasma 6 Extensions → Date and Time);
0.1 listed at 06:43 UTC, MD5 equal to the Desktop kit's.

**0.2 — not uploaded yet.** What's new: notes by day and calendars. A day with an entry
takes its own colour; a click on it (the cell is framed under the pointer) opens a sticker
framed with characters, with the day's events and tasks from the accounts and a note of
yours; the next entries are printed under the months. Notes are iCalendar files, or go to
an account's calendar. Accounts on a new page, any number: Yandex and iCloud (CalDAV, app
password), Google (CalDAV, OAuth login once), any CalDAV server, read-only ICS links. The
description below says so; Yandex was tried end to end, the others not yet.

- **File:** `dist/plaincalendar-<version>.plasmoid`
- **Category:** Plasma 6 Extensions → Date and Time
- **License:** GPL-2.0-or-later
- **Source / homepage:** https://github.com/highscrren-dotcom/plaintop
- **Tags:** calendar, month, week numbers, text, monospace
- **Images:** three months one under another, the week numbers, a weekend in red, today
  in brackets — needs no data, any machine renders it. Rendered 2026-10-04: a logo (the
  October block) and a gallery picture (three months), English locale, stock colours

**Summary:** A wall calendar as plain text — one month or three, week numbers, the weekends and today marked — in the plaintop style.

**Description:**

```
plaincalendar — a wall calendar for the Plasma 6 desktop as plain monospace text, in the
style of the plaintop monitor: no frames, no graphics. The month's name and year, a row
of weekday names, the days in seven columns with the ISO week number in front of every
row — one month, or three one under another, the previous, the current and the next, as
a quarterly calendar on an office wall. Weekends in their own colour, today in brackets
in another. The names, the first day of the week and the weekend come from your locale;
the first day can be forced to Monday or Sunday, and the empty cells can show the
neighbouring months' days.

Notes and calendars: a click on a day opens a sticker by the cell — a sheet framed with
characters with the day's events and tasks and a note of yours; a day with an entry takes
its own colour, and the next entries are listed under the months. Notes are iCalendar
files on your disk, or go to an account's calendar. Accounts, any number: Yandex and iCloud
over CalDAV with an app password, Google over CalDAV with a one-time OAuth login, any CalDAV
server, read-only ICS links; passwords stay in a file only you can read. Yandex has been
tried end to end, the others not yet — reports welcome. The notes run a small helper in
Python 3 (the standard library only) from the widget's package; without notes the calendar
fetches nothing.

Right-click → Configure: months (one or three), week numbers, the first day of the
week, the weekends' colour, the neighbouring months; font, size, cell width, the colours;
the Notes page — on or off, where a note goes, how often accounts are read, the sticker's
frame and paper; the Accounts page; the Mouse page lets clicks through to the desktop
everywhere but on the days, like the other plaintop widgets. The default font is JetBrainsMono Nerd Font Mono; any monospace font works. The
interface follows Plasma's language — ten languages, all but English and Russian
machine-translated, corrections welcome.

Source, issues, details: https://github.com/highscrren-dotcom/plaintop,
devlog: https://t.me/s1dd1_logs

———

plaincalendar — настенный календарь для рабочего стола Plasma 6 простым моноширинным
текстом, в стиле монитора plaintop: без рамок и графики. Название месяца и год, строка
дней недели, дни в семь столбцов с номером недели по ISO перед каждой строкой — один
месяц либо три столбиком, прошлый, текущий и следующий, как квартальный календарь на
стене кабинета. Выходные своим цветом, сегодняшний день в скобках другим. Названия,
первый день недели и выходные берутся из вашей локали; первый день можно принудительно
сделать понедельником или воскресеньем, а в пустых ячейках показать дни соседних
месяцев.

Заметки и календари: клик по дню открывает стикер у ячейки — лист в рамке из символов с
событиями и задачами дня и вашей заметкой; день с записью красится своим цветом, а
ближайшие записи перечислены под месяцами. Заметки — файлы iCalendar на вашем диске или
записи в календаре аккаунта. Аккаунтов сколько угодно: Яндекс и iCloud по CalDAV с паролем
приложения, Google по CalDAV с однократным входом OAuth, любой сервер CalDAV, ссылки ICS на
чтение; пароли лежат в файле, который читаете только вы. Яндекс проверен полностью,
остальные пока нет — сообщения приветствуются. Заметки запускают небольшой помощник на
Python 3 (только стандартная библиотека) из пакета виджета; без заметок календарь ничего не
запрашивает.

Правый клик → Настроить: месяцы (один или три), номера недель, первый день недели, цвет
выходных, соседние месяцы; шрифт, кегль, ширина ячейки, цвета; страница «Заметки» —
включить или выключить, куда писать заметку, как часто читать аккаунты, рамка и бумага
стикера; страница «Аккаунты»; страница «Мышь» пропускает клики на стол везде, кроме дней,
как у других виджетов plaintop. Шрифт по умолчанию —
JetBrainsMono Nerd Font Mono; подойдёт любой моноширинный. Интерфейс говорит на языке
Plasma — десять языков, всё, кроме английского и русского, переведено машинно,
исправления приветствуются.

Исходники, вопросы, подробности: https://github.com/highscrren-dotcom/plaintop,
дневник разработки: https://t.me/s1dd1_logs
```
