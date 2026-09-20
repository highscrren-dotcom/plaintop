# plasmoid — целевая реализация

Собственный плазмоид Plasma 6 на QML. Почему именно он — `../docs/DECISIONS.md`, решение 1.
Откуда берутся данные — там же, решение 2.

## Что уже есть

Минимальный рабочий пакет: ставится, появляется на рабочем столе, показывает живые
данные, настройки из штатного диалога доезжают до QML.

```
package/
  metadata.json                идентификатор org.s1dd1.plaintop
  contents/
    ui/main.qml                сам виджет: строки, полоски из слешей, подписки на сенсоры
    ui/configGeneral.qml       страница настроек «Общее»
    config/main.xml            схема значений — Plasma строит по ней диалог и хранилище
    config/config.qml          список страниц настроек
```

Показывает: заголовок с именем хоста, часы, загрузку и температуру CPU, занятость ОЗУ,
аптайм. Настраиваются заголовок, шрифт, кегль и интервал обновления.

## Установка

```bash
./install.sh --plasmoid   # поставить/обновить пакет и перезапустить оболочку
./install.sh --status     # в конце — раздел «Плазмоид»
```

⚠️ Перезапуск оболочки в команде не для красоты: plasmashell держит QML пакета в кэше,
и без него виджет остаётся со старой разметкой. Проверено — `../docs/GOTCHAS.md`.

Добавить на рабочий стол — как обычный виджет, либо скриптом:

```bash
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
  'desktops()[0].addWidget("org.s1dd1.plaintop", 60, 800, 420, 220)'
```

## Источники данных

Данные берутся у **ksystemstats** через `org.kde.ksysguard.sensors` — 620 готовых
сенсоров на этой машине, без единого запуска внешней команды. Отвергнутые способы
и цена каждого — `../docs/DECISIONS.md`, решение 2.

Что уже подписано: `cpu/all/usage`, `cpu/all/averageTemperature`,
`memory/physical/usedPercent`, `os/system/uptime`, `os/system/hostname`.

## Что предстоит

- **Топ процессов** — `org.kde.ksysguard.process` (`ProcessDataModel` +
  `KSortFilterProxyModel`, `sortRoleName: "Value"`), без `ps`.
- **Раздельный счёт по узлам NUMA** — логика в `../conky/plainext.lua`; в сенсорах
  есть `cpu/cpuN/usage` по каждому ядру, узлы собираются из них.
- **GPU** — `gpu/gpu0/{usage,temperature,usedVram,power}` уже есть в сенсорах;
  через `nvidia-smi` останутся только обороты вентилятора и encoder/decoder.
- **Диски, сеть** — `disk/*`, `network/*` в сенсорах.
- **docker / ollama / обновления** — своих сенсоров нет, это `DataSource{engine:"executable"}`
  с редким интервалом; логика уже есть в `../conky/services.sh`.
- **Блоки и их порядок из `schema/widget.json`** — сейчас строки зашиты в `main.qml`.
- **Цвета и шрифт под тему**, а не белым по месту.
