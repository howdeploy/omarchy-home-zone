# Архитектура Home Zone

## Как это работает

Home Zone — это **panel-плагин** omarchy-shell (quickshell):

```
manifest.json  →  kinds: ["panel"], keepLoaded: true, entryPoints.panel = HomeZone.qml
```

- `keepLoaded: true` — хост монтирует плагин при старте шелла (Instantiator в
  shell.qml создаёт Loader для каждого enabled panel/overlay/menu плагина).
- Хост инжектит контекст **после** загрузки: `omarchyPath`, `shell`,
  `manifest`, `barWidgetRegistry`, `pluginRegistry` — только если свойство
  объявлено. Поэтому свойства объявляются обычными (НЕ `required`) —
  `required` ломает инстанцирование (Loader создаёт компонент без начальных
  свойств; известный баг-паттерн, см. howdeploy.bar).

## Слои и ввод

- `PanelWindow` на **весь экран**, `WlrLayershell.layer: WlrLayer.Background` —
  поверх обоев, под окнами.
- `exclusionMode: ExclusionMode.Ignore` — не резервирует место.
- `mask: Region { item: card }` — input-регион только на карточке:
  остальная часть экрана кликается насквозь (паттерн notifications/Service.qml).

## Конфиг

`~/.config/omarchy/home-zone.json` (пользовательский, переживает обновления
плагина). Читается `FileView` с `watchChanges: true` — правка файла
перезагружает конфиг на лету. Структура: `grid`, `card`, `colors`, `tiles[]`.

`tiles[]` — массив, заменяется целиком при перезагрузке (Repeater пересоздаёт
плитки). Позиция: `col/row` (0-based), размер: `colspan/rowspan` в ячейках.

## Тема

Цвета по умолчанию берутся из темы omarchy (`qs.Commons` → `Color.*`,
`Style.*`): карточка = `Color.background`, плитки = `Color.bar.background`,
текст = `Color.bar.text`. Оверрайды — `colors.*` в конфиге.

## Жизненный цикл виджета

1. Repeater над `tiles[]` создаёт плитку (Item + BorderSurface-фон).
2. Внутри — `Loader { source: "widgets/<widget>.qml" }` (путь относительно
   HomeZone.qml).
3. `onLoaded` инжектит в виджет: `shell`, `appLibrary` (если есть),
   `tileConfig` (settings плитки), `tileColors` (разрешённые цвета).

## Потоки данных

- **Лаунчер**: `shell.appLibrary` (AppLibrary — база .desktop-записей, та же,
  что у меню omarchy). `sortedEntries("")`, `iconSource(icon)`,
  `entryName(entry)`, `launch(desktopId, name)`.
- **Настройки**: команда из `tileConfig.action` через `Process` (Quickshell.Io).
- **Часы**: `Qt.formatTime/formatDate` + таймер 1с.

## Безопасность

- Плагин работает внутри omarchy-shell (непривилегированный пользователь).
- Виджеты исполняют только то, что написано в их QML/конфиге.
- Третьесторонние виджеты из недоверенных источников — только после ревью.
