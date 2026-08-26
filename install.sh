#!/usr/bin/env bash
# ⚠️ DEV-HELPER, а не официальный установщик.
#
# Официальная установка плагина из GitHub:
#     omarchy plugin add https://github.com/howdeploy/omarchy-home-zone.git --enable
# Официальный установщик install.sh НЕ запускает — он клонирует репозиторий,
# валидирует манифест и кладёт код в ~/.config/omarchy/plugins/<id>/.
#
# Этот скрипт синхронизирует РАБОЧЕЕ ДЕРЕВО репозитория в установочный каталог
# для быстрой итерации при разработке. Отличия от официального пути:
#   - копирует файлы (каталог плагина НЕ становится git-чекаутом);
#   - перед заменой делает бэкап предыдущей установки;
#   - отказывается работать, если плагин установлен через omarchy plugin add
#     (там свой git-чекаут — обновляй через `omarchy plugin update <id>`).
set -euo pipefail

PLUGINS_ROOT="${HOME}/.config/omarchy/plugins"
SRC="$(cd "$(dirname "$0")" && pwd)"

# ID — единственный источник правды: manifest.json
PLUGIN_ID="$(jq -r '.id // empty' "${SRC}/manifest.json")"
if [[ -z "${PLUGIN_ID}" ]]; then
  echo "✗ Не удалось прочитать id из manifest.json" >&2
  exit 1
fi
# Guard от path traversal / мусора в id (dev-only, но дёшево)
if [[ ! "${PLUGIN_ID}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "✗ Некорректный id плагина: ${PLUGIN_ID}" >&2
  exit 1
fi

DEST="${PLUGINS_ROOT}/${PLUGIN_ID}"
# Guard: DEST обязан лежать внутри каталога плагинов
case "${DEST}" in
  "${PLUGINS_ROOT}"/*) ;;
  *) echo "✗ Путь установки вне ${PLUGINS_ROOT}: ${DEST}" >&2; exit 1 ;;
esac

if [[ -d "${DEST}/.git" ]]; then
  echo "✗ ${DEST} — git-чекаут (установлен через 'omarchy plugin add')." >&2
  echo "  Для обновления используй: omarchy plugin update ${PLUGIN_ID}" >&2
  exit 1
fi

CONFIG_DEST="${HOME}/.config/omarchy/home-zone.json"
SHELL_JSON="${HOME}/.config/omarchy/shell.json"

# Полезная нагрузка плагина. Новые корневые .qml добавляй сюда; widgets/ копируется целиком.
PAYLOAD=(
  "${SRC}/manifest.json"
  "${SRC}/HomeZone.qml"
  "${SRC}/SettingsOverlay.qml"
  "${SRC}/widgets"
)

echo "→ Синхронизирую плагин ${PLUGIN_ID} в ${DEST}"
mkdir -p "${PLUGINS_ROOT}"

if [[ -d "${DEST}" ]]; then
  # Бэкап предыдущей установки (без rm -rf: каталог не теряется)
  rm -rf "${DEST}.bak" 2>/dev/null || true
  mv "${DEST}" "${DEST}.bak"
  echo "  (предыдущая установка сохранена в ${DEST}.bak)"
fi
mkdir -p "${DEST}"

for item in "${PAYLOAD[@]}"; do
  if [[ -e "${item}" ]]; then
    cp -r "${item}" "${DEST}/"
  else
    echo "  (пропущен отсутствующий файл: ${item})"
  fi
done

if [[ ! -f "${CONFIG_DEST}" ]]; then
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
