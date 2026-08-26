#!/usr/bin/env bash
# Установка плагина Home Zone в omarchy-shell.
# Копирует код в ~/.config/omarchy/plugins/<id>/, создаёт пользовательский
# конфиг (если нет) и включает плагин.
set -euo pipefail

PLUGIN_ID="howdeploy.home-zone"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
CONFIG_DEST="${HOME}/.config/omarchy/home-zone.json"
SHELL_JSON="${HOME}/.config/omarchy/shell.json"

echo "→ Копирую плагин в ${DEST}"
mkdir -p "$(dirname "${DEST}")"
rm -rf "${DEST}"
mkdir -p "${DEST}"
cp "${SRC}/manifest.json" "${SRC}/HomeZone.qml" "${DEST}/"
cp -r "${SRC}/widgets" "${DEST}/"

if [ ! -f "${CONFIG_DEST}" ]; then
  echo "→ Создаю пользовательский конфиг ${CONFIG_DEST}"
  mkdir -p "$(dirname "${CONFIG_DEST}")"
  cp "${SRC}/config/home-zone.json" "${CONFIG_DEST}"
fi

echo "→ Валидация манифеста"
omarchy plugin validate "${DEST}"

echo "→ Включение плагина (добавление id в shell.json plugins[])"
if ! omarchy plugin enable "${PLUGIN_ID}" >/dev/null 2>&1; then
  python3 - "${PLUGIN_ID}" "${SHELL_JSON}" <<'PYEOF'
import json, sys
plugin_id, path = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
plugins = cfg.setdefault("plugins", [])
if not any(p.get("id") == plugin_id for p in plugins if isinstance(p, dict)):
    plugins.append({"id": plugin_id})
    with open(path, "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"добавлен {plugin_id} в {path}")
else:
    print(f"{plugin_id} уже включён")
PYEOF
fi

echo "→ Пересканирование плагинов"
omarchy-shell shell rescanPlugins || omarchy restart shell

echo "✅ Готово. Конфиг: ${CONFIG_DEST}"
