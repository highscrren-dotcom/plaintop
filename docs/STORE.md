# KDE Store listings

The text for the widget pages on [store.kde.org](https://store.kde.org), kept here so
the pages can be updated along with the code. A store page has one description field,
so each description carries both languages — English first, Russian below — and this file
is not split into an `.ru.md` pair.

The files to upload are built by:

```bash
./install.sh --pack     # → dist/{plaintop,plainspectrum,plainplayer,plainweather}-<version>.plasmoid
```

`--pack` installs each archive into a throwaway package root before reporting success,
so what it builds is known to install. The version in the file name comes from each
widget's `metadata.json`; bump it there before building a new upload.

⚠️ Updated to 0.2 on 2026-09-22 (13:54 and 13:55 UTC in the store's API): the pages carry the
text below, `plaintop-0.2.plasmoid` and `plainspectrum-0.2.plasmoid` (MD5 equal to the
built files); the 0.1 files are still listed beside them.

⚠️ Not yet uploaded, 2026-09-23: plaintop 0.3 and plainspectrum 0.3 (both `metadata.json`
bumped) and the two new products, plainplayer 0.1 and plainweather 0.1 — `--pack` has built
all four into `dist/`, the texts below are ready; publication is paused for now. Each new
product goes through *Add Product* as described under Uploading.

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

**0.3 — not yet uploaded.** What's new: three block types — pressure stall information
(PSI) for CPU, memory and I/O; the battery, shown only where one exists; system health —
failed systemd units, errors since boot and the last error lines of the journal. Separators
collapse where a block hides, so no double rules. The description below already says so.
And a small one: in the disks block the root mount is labelled `root` instead of `/` —
beside a bar made of slashes, `/` read as part of the bar.

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

The blocks, their order and their parameters are set on the Blocks page of the
settings; a block can also be any ksystemstats sensor or any command. Sensors specific to
a machine — fans, NVMe, the network interface — are found on the machine itself.
Data comes from ksystemstats, the same service as Plasma's System Monitor.

The interface follows Plasma's language: English, Russian, Ukrainian, German, French,
Spanish, Brazilian Portuguese, Polish, Simplified Chinese, Japanese — all but English and
Russian machine-translated, corrections welcome. The updates line reads pacman.

Out of the box the widget takes clicks like any other; General → Mouse lets both buttons
through to the desktop, and the widget takes the mouse only in the desktop's edit mode —
which is also where its settings are. Source and details:
https://github.com/highscrren-dotcom/plaintop

———

Текстовый монитор системы для рабочего стола Plasma 6 в духе скина PlainExt для
Rainmeter: часы и дата, система, загрузка CPU общая и по узлам NUMA, процессор с
температурами и оборотами, данные о простоях (PSI), топ процессов по CPU и памяти, ОЗУ,
GPU с VRAM, диски с температурой NVMe, аптайм, сеть, батарея, если она есть,
docker/ollama/обновления, здоровье системы — упавшие юниты systemd, ошибки с загрузки,
последние ошибки журнала — и паспорт железа.

Набор блоков, порядок и параметры — на странице «Блоки» в настройках; блоком может быть
любой датчик ksystemstats или любая команда. Привязанные к машине датчики — вентиляторы,
NVMe, сетевой интерфейс — находятся на самой машине. Данные берутся у ksystemstats — той
же службы, что у «Системного монитора» Plasma. Интерфейс говорит на языке Plasma: английский,
русский, украинский, немецкий, французский, испанский, португальский (Бразилия), польский,
китайский и японский — всё, кроме английского и русского, переведено машинно, исправления
приветствуются. Строка обновлений читает pacman.

Сразу после установки виджет ловит клики, как любой другой; «Общее → Мышь» пропускает
на рабочий стол обе кнопки, а мышь виджет берёт только в режиме правки рабочего стола —
там же и его настройки. Исходники и подробности:
https://github.com/highscrren-dotcom/plaintop
```

## plainspectrum — audio visualizer

Published 2026-09-22: https://store.kde.org/p/2372815/

**0.3 — not yet uploaded.** What's new: the player in the centre of the ring — the
plainplayer view on a new *Player* page, off by default, with the player's own font, width
and colours; on a line it goes along the edge the bars reach last. With *Mouse* on, only
the player's controls row takes clicks, the rest of the widget lets them through. The
description below already says so.

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
  outward / inward / both ways (up / down on a line), mirrored or reversed band order.
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

Source, issues, details: https://github.com/highscrren-dotcom/plaintop

———

plainspectrum — визуализатор звука для рабочего стола Plasma 6 в простом стиле скина
PlainExt для Rainmeter: один цвет, прямые концы, без градиентов и свечения. Рисует спектр
того, что играет, штрихами по кольцу, по дуге или по линии — прямо на обоях.

Что настраивается (правый клик → Настроить):
• Форма — кольцо или линия (кольцо с охватом меньше 360° — дуга), число штрихов, радиус,
  охват и начальный угол, толщина штрихов и зазоры, длина в тишине и на максимуме, рост
  наружу / внутрь / в обе стороны (у линии — вверх / вниз), зеркальный или обратный
  порядок полос.
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

Исходники, вопросы, подробности: https://github.com/highscrren-dotcom/plaintop
```

## plainplayer — now playing

(not yet uploaded)

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

Source, issues, details: https://github.com/highscrren-dotcom/plaintop

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

Исходники, вопросы, подробности: https://github.com/highscrren-dotcom/plaintop
```

## plainweather — weather

(not yet uploaded)

- **File:** `dist/plainweather-<version>.plasmoid`
- **Category:** Plasma 6 Extensions → Online Services
- **License:** GPL-2.0-or-later
- **Source / homepage:** https://github.com/highscrren-dotcom/plaintop
- **Tags:** weather, forecast, open-meteo, text
- **Images:** the header, the current line and three forecast rows — needs a location set
  or guessed, and a network

**Summary:** The weather as plain text — now and the next days — from Open-Meteo, in the plaintop style. Weather data by Open-Meteo.com.

**Description:**

```
plainweather — the weather for the Plasma 6 desktop as plain monospace text, in the
style of the plaintop monitor: no icons, no frames. A header with the place, the
current conditions — temperature, a word for the sky, what it feels like, wind and
humidity — and one row per forecast day, 0 to 7, with the low, the high, the sky and
the chance of rain.

The data is Open-Meteo's: the widget asks api.open-meteo.com itself over https, every
15 minutes, one request — no service of its own, nothing to install beyond the widget,
and it needs network access to that host. The last answer is kept, so the widget draws
at once after a shell restart and stays through an outage, marked "offline". The
place: search a city on the Location page (a click stores it) or type "latitude,
longitude"; until one is set, the widget guesses the city from the time zone and says
so in the header. It never asks a geolocation service where you are. Units follow the
locale (°F and mph in the US) or are chosen by hand.

Weather data by Open-Meteo.com. Open-Meteo is free for non-commercial use under
CC BY 4.0 and asks for attribution — the last line of the widget, on by default.

Right-click → Configure: font, size, width, three colours; location, units, days, the
attribution line; the Mouse page lets both buttons through to the desktop like the
other plaintop widgets. The interface follows Plasma's language — ten languages, all
but English and Russian machine-translated, corrections welcome.

Source, issues, details: https://github.com/highscrren-dotcom/plaintop

———

plainweather — погода для рабочего стола Plasma 6 простым моноширинным текстом, в стиле
монитора plaintop: без значков и рамок. Заголовок с местом, текущие условия —
температура, слово про небо, «ощущается», ветер и влажность — и по строке на день
прогноза, от 0 до 7: минимум, максимум, небо и вероятность осадков.

Данные — Open-Meteo: виджет сам запрашивает api.open-meteo.com по https раз в 15 минут,
одним запросом — своей службы нет, ставить сверх виджета ничего не нужно, нужен лишь
доступ по сети к этому хосту. Последний ответ хранится, так что после перезапуска
оболочки виджет рисуется сразу и переживает обрыв сети с пометкой об этом. Место: поиск
города на странице «Место» (клик сохраняет) или введённые «широта, долгота»; пока оно
не задано, виджет угадывает город по часовому поясу и говорит об этом в заголовке. Где
вы находитесь, у служб геолокации он не спрашивает. Единицы — по локали (в США °F и
mph) или вручную.

Данные о погоде: Open-Meteo.com. Open-Meteo бесплатен для некоммерческого использования
по лицензии CC BY 4.0 и просит указывать источник — последняя строка виджета, включена
по умолчанию.

Правый клик → Настроить: шрифт, кегль, ширина, три цвета; место, единицы, дни, строка
источника; страница «Мышь» пропускает на стол обе кнопки, как у других виджетов
plaintop. Интерфейс говорит на языке Plasma — десять языков, всё, кроме английского и
русского, переведено машинно, исправления приветствуются.

Исходники, вопросы, подробности: https://github.com/highscrren-dotcom/plaintop
```
