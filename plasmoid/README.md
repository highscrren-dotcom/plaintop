# plasmoid — целевая реализация

Собственный плазмоид Plasma 6 на QML. Почему именно он — `../docs/DECISIONS.md`.

Ожидаемая раскладка пакета:

```
package/
  metadata.json              идентификатор, имя, версия, категория
  contents/
    ui/main.qml              сам виджет: текстовые строки, полоски из слешей
    ui/configGeneral.qml     страница настроек «Общее»
    ui/configBlocks.qml      страница настроек «Блоки»
    config/main.xml          схема значений — Plasma строит диалог по ней
    config/config.qml        список страниц настроек
  code/                      источники данных на JS
```

Ставится в `~/.local/share/plasma/plasmoids/` (или `kpackagetool6 --install`),
добавляется на рабочий стол как обычный виджет.

## Что предстоит сделать самим

У conky источники данных были встроенными, здесь их нет. Нужны:

- загрузка CPU общая и по узлам NUMA — читается из `/proc/stat`, логика уже написана
  в `../conky/plainext.lua`, переносится почти как есть;
- топ процессов по CPU и по памяти — `/proc/*/stat`, `/proc/*/statm`;
- температуры и обороты — `sensors -u` по ИМЕНИ чипа, не по индексу `hwmon`
  (см. `../docs/GOTCHAS.md`);
- GPU — `nvidia-smi --query-gpu`;
- файловые системы, сеть, аптайм;
- docker / ollama / ожидающие обновления — логика уже есть в `../conky/services.sh`.

Пока пусто.
