# Home Zone

[English](README.md) · [Русский](README.ru.md)

![Home Zone в Omarchy](preview.png)

Десктопные виджеты поверх обоев для **Omarchy** (Arch + Hyprland, quickshell).
Плитки: часы, компактный лаунчер выбранных приложений, системное меню Omarchy
и обязательная кнопка настроек Home Zone. Встроенное окно настроек позволяет
выбрать от нуля до четырёх приложений, перемещать плитки и менять их размер
за любую грань или угол внутри фиксированной сетки `10 × 4`. Выбор приложений
применяется сразу; Save/Cancel управляют черновиком раскладки. Подсетка повышает
точность resize, но сохраняет установленный внешний размер `842 × 350`.

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

`install.sh` — **dev-helper, официальный установщик его не запускает**. Он
синхронизирует рабочее дерево репозитория в установочный каталог для быстрой
итерации (бэкапит предыдущую установку, не трогает git-чекауты, установленные
через `omarchy plugin add`):

```bash
./install.sh
```

## Конфиг

`~/.config/omarchy/home-zone.json` — перечитывается на лету (без рестарта):

| Ключ | Что делает |
|---|---|
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
- плитка `menu` вызывает системное меню Omarchy через
  `omarchy-shell shell summon omarchy.menu`.

## Лицензия

MIT — см. [LICENSE](LICENSE).

## Документация

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — как устроен плагин
- [docs/widget-authoring.md](docs/widget-authoring.md) — как добавить свой виджет (в т.ч. агенту)
