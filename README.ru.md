# Home Zone

[English](README.md) · [Русский](README.ru.md)

![Home Zone в Omarchy](preview.png)

Десктопные виджеты поверх обоев для **Omarchy** (Arch + Hyprland, quickshell).
Плитки: часы, компактный лаунчер выбранных приложений, системное меню Omarchy
и обязательная кнопка настроек Home Zone. Встроенное окно настроек позволяет
выбрать от нуля до четырёх приложений, перемещать плитки и менять их размер
за любую грань или угол внутри фиксированной сетки `10 × 4`, масштабировать весь
Home Zone до 100%, 80% или 60% и располагать его по центру либо у любого края
экрана. Выбор приложений применяется сразу; Save/Cancel управляют черновиком
раскладки и отображения. Подсетка повышает точность resize, но сохраняет
установленный внешний размер по умолчанию `842 × 350`.

Все поверхности по умолчанию получают живые роли активной темы Omarchy:
`Color.accent`, `Color.bar.*`, `Color.muted`, `Color.urgent` и
`Color.background`. Жёсткой палитры CanvasTTY в плагине нет.

ID плагина: `io.github.howdeploy.home-zone`

## Установка

```bash
omarchy plugin add https://github.com/howdeploy/omarchy-home-zone.git --enable
```

Установщик клонирует репозиторий в `~/.config/omarchy/plugins/io.github.howdeploy.home-zone/`,
проверяет манифест и включает плагин. Конфиг создаётся автоматически при первом
сохранении настроек; до этого Home Zone использует встроенные значения.

## Обновление

```bash
omarchy plugin update io.github.howdeploy.home-zone
```

Обновление — проверяемый fast-forward: при локальных правках внутри установленного
каталога плагина обновление будет отклонено (сначала удали или закоммить свои
изменения).

## Удаление

```bash
omarchy plugin remove io.github.howdeploy.home-zone
```

Пользовательский конфиг `~/.config/omarchy/home-zone.json` при этом остаётся —
удалить его можно вручную.

## Разработка

Клонируй репозиторий и запусти те же проверки без внешних зависимостей, которые используются перед релизом:

```bash
git clone https://github.com/howdeploy/omarchy-home-zone.git
cd omarchy-home-zone
npm test
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" HomeZone.qml SettingsOverlay.qml widgets/*.qml
```

## Конфиг

Home Zone безопасно опрашивает `~/.config/omarchy/home-zone.json` раз в две секунды и применяет внешние правки без рестарта shell:

| Ключ | Что делает |
|---|---|
| `display.size / placement` | масштаб всего Home Zone (`default`, `small`, `mini`) и расположение на экране (`center`, `top`, `right`, `bottom`, `left`) |
| `grid.columns / cellWidth / cellHeight / gap` | сетка |
| `card.visible / backgroundAlpha / radius / padding` | внешняя карточка |
| `colors.<widget>Background / <widget>Text` | оверрайд роли конкретной плитки (`clock`, `launcher`, `menu`, `settings`) |
| `colors.tileBackground / text / cardBackground` | общий совместимый оверрайд поверх системной темы |
| `colors.launcherTile / border` | оверрайд внутренних кнопок launcher и границ |
| `tiles[]` | плитки: `widget`, `col`, `row`, `colspan`, `rowspan`, `settings` |

У launcher в `settings.appIds` хранится упорядоченный список desktop ID.
Если ключ отсутствует, показываются первые четыре приложения из
`shell.appLibrary`. Явный пустой массив `appIds: []` означает пустой launcher;
это не fallback.

## Зависимости

- Omarchy с шеллом на quickshell (`omarchy-shell`);
- Python 3 для небольшого helper-процесса на границе настроек;
- плитка `menu` вызывает системное меню Omarchy через `omarchy-shell shell summon omarchy.menu`.

## Безопасность и приватность

Как и любой сторонний плагин Omarchy Shell, Home Zone работает без sandbox внутри долгоживущего процесса `omarchy-shell` с правами пользователя. Перед включением проверь исходники.

- Плагин не обращается к сети и не содержит install hook, daemon, service, скомпилированных бинарников, действий с package manager или повышения привилегий.
- Он читает и пишет только `~/.config/omarchy/home-zone.json` через короткоживущий Python-helper, CLI которого принимает операцию, но никогда не принимает путь.
- Helper определяет home по effective UID, открывает каждый каталог без перехода по ссылкам и отклоняет небезопасного владельца или права, symlink, не-regular файлы, несколько hard link и настройки больше 64 KiB.
- Запись атомарно публикуется относительно уже проверенного descriptor каталога с режимом `0600`; старый пользовательский конфиг `0644` автоматически ужесточается.

## Лицензия

MIT — см. [LICENSE](LICENSE).

## Документация

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — как устроен плагин
- [docs/widget-authoring.md](docs/widget-authoring.md) — как добавить свой виджет (в т.ч. агенту)
