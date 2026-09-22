# KDE Store listings

The text for the two widget pages on [store.kde.org](https://store.kde.org), kept here so
the pages can be updated along with the code. A store page has one description field,
so each description carries both languages — English first, Russian below — and this file
is not split into an `.ru.md` pair.

The files to upload are built by:

```bash
./install.sh --pack     # → dist/plaintop-<version>.plasmoid, dist/plainspectrum-<version>.plasmoid
```

`--pack` installs each archive into a throwaway package root before reporting success,
so what it builds is known to install. The version in the file name comes from each
widget's `metadata.json`; bump it there before building a new upload.

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

- **File:** `dist/plaintop-<version>.plasmoid`
- **Category:** Plasma 6 Extensions → Monitoring
- **License:** GPL-2.0-or-later
- **Source / homepage:** https://github.com/highscrren-dotcom/plaintop
- **Tags:** system monitor, conky, rainmeter, text, sensors, cpu, gpu, numa
- **Images:** a square logo of the clock and a landscape gallery picture of the whole
  monitor, both rendered offscreen by the real renderer in an English session

**Summary:** A text system monitor for the desktop, in the spirit of the PlainExt Rainmeter skin.

**Description:**

```
A monospace, text-only system monitor for the Plasma 6 desktop, in the spirit of the
PlainExt skin for Rainmeter: clock and date, system, CPU load overall and per NUMA node,
the processor with temperatures and fan speeds, top processes by CPU and by memory, RAM,
GPU with VRAM, disks with NVMe temperature, uptime, network, docker/ollama/updates and a
hardware spec sheet.

The blocks, their order and their parameters are set on the Blocks page of the
settings; a block can also be any ksystemstats sensor or any command. Sensors specific to
a machine — fans, NVMe, the network interface — are found on the machine itself.
Data comes from ksystemstats, the same service as Plasma's System Monitor.

The interface follows Plasma's language: English, Russian, Ukrainian, German, French,
Spanish, Brazilian Portuguese, Polish, Simplified Chinese, Japanese — all but English and
Russian machine-translated, corrections welcome. The updates line reads pacman.

Out of the box the widget takes clicks like any other; General → Mouse lets the right
button through to the desktop. A plasmoid can never pass the left one — for full
click-through the repository has a window host, plus an editor with a live preview:
https://github.com/highscrren-dotcom/plaintop

———

Текстовый монитор системы для рабочего стола Plasma 6 в духе скина PlainExt для
Rainmeter: часы и дата, система, загрузка CPU общая и по узлам NUMA, процессор с
температурами и оборотами, топ процессов по CPU и памяти, ОЗУ, GPU с VRAM, диски с
температурой NVMe, аптайм, сеть, docker/ollama/обновления и паспорт железа.

Набор блоков, порядок и параметры — на странице «Блоки» в настройках; блоком может быть
любой датчик ksystemstats или любая команда. Привязанные к машине датчики — вентиляторы,
NVMe, сетевой интерфейс — находятся на самой машине. Данные берутся у ksystemstats — той
же службы, что у «Системного монитора» Plasma. Интерфейс говорит на языке Plasma: английский,
русский, украинский, немецкий, французский, испанский, португальский (Бразилия), польский,
китайский и японский — всё, кроме английского и русского, переведено машинно, исправления
приветствуются. Строка обновлений читает pacman.

Сразу после установки виджет ловит клики, как любой другой; «Общее → Мышь» пропускает
на рабочий стол правую кнопку. Левую плазмоид не отдаёт никогда — для настоящих сквозных
кликов в репозитории есть оконный хост и редактор с живым просмотром:
https://github.com/highscrren-dotcom/plaintop
```

## plainspectrum — audio visualizer

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

Light by design: the bars are ready-made rectangles moved by the scene graph and nothing
is rasterized per frame, so the graphics card stays almost idle. Out of the box the
widget takes clicks like any other; Behaviour → Mouse lets the right button through.

⚠️ The widget alone draws nothing. The spectrum is computed by cava in a small relay
service (Python, a systemd user unit) that a widget cannot install by itself:

  git clone https://github.com/highscrren-dotcom/plaintop
  cd plaintop
  ./install.sh --spectrum      (install cava first)

Without the relay the widget says so instead of staying blank. The audio device and the
frequency range are set in ~/.config/plainspectrum/relay.env.

The interface follows Plasma's language — ten languages, all but English and Russian
machine-translated, corrections welcome. The repository also has a click-through window
host for the ring, with its own editor and a live preview.

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

Лёгкий по устройству: штрихи — готовые прямоугольники, их двигает граф сцены, покадровой
растеризации нет, и видеокарта почти не нагружается. Сразу после установки виджет ловит
клики, как любой другой; «Поведение → Мышь» пропускает правую кнопку на рабочий стол.

⚠️ Сам по себе виджет ничего не рисует. Спектр считает cava в маленькой службе-реле
(Python, пользовательский юнит systemd), которую виджет поставить не может:

  git clone https://github.com/highscrren-dotcom/plaintop
  cd plaintop
  ./install.sh --spectrum      (сначала поставьте cava)

Без реле виджет прямо об этом пишет, а не остаётся пустым. Звуковое устройство и диапазон
частот задаются в ~/.config/plainspectrum/relay.env.

Интерфейс говорит на языке Plasma — десять языков, всё, кроме английского и русского,
переведено машинно, исправления приветствуются. В репозитории есть и оконный хост кольца
со сквозными кликами, своим редактором и живым просмотром.

Исходники, вопросы, подробности: https://github.com/highscrren-dotcom/plaintop
```
