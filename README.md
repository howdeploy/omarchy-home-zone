# Home Zone

Десктопные виджеты поверх обоев для **Omarchy** (Arch + Hyprland, quickshell).
Плитки: часы, лаунчер приложений, кнопка настроек. Сеточная раскладка,
тематика из omarchy (catppuccin и др.), горячая перезагрузка конфига,
расширяемость виджетами (QML) — вручную или агентом.

## Установка

```bash
./install.sh
```

Что делает: копирует код в `~/.config/omarchy/plugins/howdeploy.home-zone/`,
создаёт пользовательский конфиг `~/.config/omarchy/home-zone.json` (если нет),
включает плагин и пересканирует шелл.

## Конфиг

`~/.config/omarchy/home-zone.json` — перечитывается на лету (без рестарта):

| Ключ | Что делает |
|---|---|
| `grid.columns / cellWidth / cellHeight / gap` | сетка |
| `card.visible / backgroundAlpha / radius / padding` | внешняя карточка |
| `colors.tileBackground / text / cardBackground` | оверрайды цветов поверх темы |
| `tiles[]` | плитки: `widget`, `col`, `row`, `colspan`, `rowspan`, `settings` |

Документация:
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — как устроен плагин
- [docs/widget-authoring.md](docs/widget-authoring.md) — как добавить свой виджет (в т.ч. агенту)
