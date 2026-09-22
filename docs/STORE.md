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
- **Tags:** audio, visualizer, spectrum, cava, ring, music
- **Images:** the ring while music plays — it dissolves in silence, so a picture needs sound

**Summary:** An audio visualizer in the spirit of PlainExt: a ring, an arc or a line. Needs its cava relay.

**Description:**

```
An audio visualizer for the Plasma 6 desktop, in the spirit of PlainExt: bars around a
ring, along an arc or on a line. In silence the ring fades away and the widget polls
four times a second instead of thirty.

⚠️ The widget alone draws nothing. The bands come from cava through a small relay
service (Python, a systemd user unit) that the widget cannot install by itself. Clone
the repository, install cava and run ./install.sh --spectrum — it installs the widget
and the relay:
https://github.com/highscrren-dotcom/plaintop
Without the relay the widget says so instead of staying blank.

The repository also has a click-through window host for the ring, with its own editor.

———

Визуализатор звука для рабочего стола Plasma 6 в духе PlainExt: штрихи по кольцу, по дуге
или по линии. В тишине кольцо растворяется, а опрос падает с тридцати до четырёх раз в
секунду.

⚠️ Сам по себе виджет ничего не рисует. Полосы приходят от cava через маленькую
службу-реле (Python, пользовательский юнит systemd), которую виджет поставить не может.
Склонируйте репозиторий, поставьте cava и запустите ./install.sh --spectrum — он
поставит и виджет, и реле: https://github.com/highscrren-dotcom/plaintop
Без реле виджет прямо об этом пишет, а не остаётся пустым.

В репозитории есть и оконный хост кольца со сквозными кликами и своим редактором.
```
