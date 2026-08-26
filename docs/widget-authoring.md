# Создание виджета Home Zone

Виджет — это QML-файл в `widgets/<имя>.qml` + запись в конфиге. Home Zone
грузит его через `Loader` и инжектит контекст.

## Контракт виджета

Объявите эти свойства на корневом Item (необязательные — что нужно):

```qml
Item {
  property var shell: null          // контекст omarchy-shell
  property var appLibrary: null     // база приложений (для лаунчера)
  property var tileConfig: ({})     // settings плитки из конфига
  property var tileColors: ({})     // { background, text } — разрешённые цвета
}
```

Корневой Item должен заполнять родителя (`anchors.fill: parent` не обязателен —
Loader сам даёт размер; используйте `width/height` или якоря).

## Регистрация в конфиге

```json
{ "widget": "my-widget", "col": 0, "row": 2, "colspan": 2, "rowspan": 1,
  "settings": { "любой": "параметр", "для": "виджета" } }
```

Правка конфига перезагружает плитки на лету.

## Пример: виджет «Погода» (заглушка данных)

```qml
import QtQuick
import qs.Commons

Item {
  property var shell: null
  property var appLibrary: null
  property var tileConfig: ({})
  property var tileColors: ({})

  Text {
    anchors.centerIn: parent
    text: tileConfig.temperature !== undefined
      ? tileConfig.temperature + "°C"
      : "нет данных"
    color: tileColors.text || "#cdd6f4"
    font.family: Style.font.family
    font.pixelSize: Style.font.display
  }
}
```

```json
{ "widget": "weather", "col": 0, "row": 2, "colspan": 2, "rowspan": 1,
  "settings": { "temperature": 21 } }
```

## Полезное

- Цвета темы: `Color.*`, `Style.*` из `qs.Commons` (см. `docs/ARCHITECTURE.md`).
- Иконки: Nerd Font через `Style.font.family` (например `"\uf013"` — шестерёнка).
- Команды оболочки: `Process { command: ["sh", "-c", "..."] }` из `Quickshell.Io`.
- Приложения: `appLibrary.sortedEntries("")`, `iconSource(icon)`,
  `entryName(entry)`, `launch(id, name)`.

## Бриф для ИИ-агента

Скопируйте это в задачу агента:

```text
Добавь виджет [НАЗВАНИЕ] в плагин Home Zone (Omarchy, quickshell, QML).
Путь: ~/Projects/omarchy-home-zone/widgets/<имя>.qml.
Контракт: корневой Item со свойствами shell / appLibrary / tileConfig / tileColors
(см. docs/widget-authoring.md и docs/ARCHITECTURE.md).
Настройки виджета — из tileConfig (ключи задокументируй в README виджета).
Цвета: по умолчанию из темы (Color.*, Style.* из qs.Commons); оверрайды — tileColors.
Данные: если нужен системный источник, предпочти shell.appLibrary; для внешних
данных — отдельный сервис или скрипт, не парси терминальный вывод.
Обрабатывай состояния: нет данных / ошибка / загрузка.
Стиль: крупная плоская плитка, мягкий радиус, короткие подписи, читаемость с расстояния.
Зарегистрируй виджет в ~/.config/omarchy/home-zone.json (tiles[]).
Проверь: omarchy-shell shell rescanPlugins (или рестарт), скриншот экрана.
Не добавляй сторонние пакеты без необходимости.
```
