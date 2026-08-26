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

Цвета по умолчанию берутся из живых ролей темы Omarchy (`qs.Commons` →
`Color.*`, `Style.*`). CanvasTTY-композиция отображается системной палитрой:
clock = `Color.accent`, launcher = `Color.bar.*`, menu = `Color.muted`,
settings = `Color.urgent`, карточка = `Color.background`. Оверрайды — только
необязательный слой `colors.*` в конфиге.

## Настройки

`SettingsOverlay.qml` — отдельное overlay-окно на `WlrLayer.Overlay`.
Переключатели launcher применяют набор приложений сразу. Геометрия `tiles[]`
остаётся черновиком до Save: окно позволяет переносить плитки и менять размер
за любую из восьми граней/углов, проверяет границы и пересечения, а затем
атомарно пишет конфиг через `FileView.setText()`. Cancel отбрасывает только
черновик раскладки. Фиксированная сетка `10 × 4` не редактируется; при переносе
между заполненными рядами их содержимое меняется местами, внутри ряда плитки
перепаковываются без пересечений.

Сетка `10 × 4` использует cell `68 × 68` и gap `14`: каждые две новые ячейки
с промежутком точно равны старой ячейке `150 px`. Legacy-раскладка `5 × 2`
мигрирует удвоением координат/spans, поэтому внешний размер и геометрия по
пикселям не меняются.

Настройки launcher пересекают динамический `Loader` как JSON-строка: так QML
не превращает вложенный `appIds` в неоднозначный QVariant. Отсутствующий ключ
выбирает дефолтные четыре приложения, а явный `[]` сохраняет `0/4`.

## Жизненный цикл виджета

1. Repeater над `tiles[]` создаёт плитку (Item + BorderSurface-фон).
2. Внутри — `Loader { source: "widgets/<widget>.qml" }` (путь относительно
   HomeZone.qml).
3. `onLoaded` инжектит в виджет: `shell`, `appLibrary` (если есть),
   `tileConfig` (settings плитки), `tileColors` (разрешённые цвета).

## Потоки данных

- **Лаунчер**: `shell.appLibrary` (AppLibrary — база .desktop-записей, та же,
  что у меню Omarchy). Настройки сохраняют до четырёх ID в
  `tileConfig.appIds`; виджет разрешает их обратно в записи и запускает через
  `launch(desktopId, name)`.
- **Menu**: прямой `shell.summon("omarchy.menu", ...)` с CLI-fallback.
- **Settings**: прямой вызов `HomeZone.openSettings()`, без произвольной
  shell-команды из конфига.
- **Часы**: `Qt.formatTime/formatDate` + таймер 1с.

## Безопасность

- Плагин работает внутри omarchy-shell (непривилегированный пользователь).
- Виджеты исполняют только то, что написано в их QML/конфиге.
- Третьесторонние виджеты из недоверенных источников — только после ревью.
