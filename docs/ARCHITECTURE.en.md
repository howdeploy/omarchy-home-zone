# Home Zone architecture

[English](ARCHITECTURE.en.md) · [Russian](ARCHITECTURE.md)

## Plugin lifecycle

Home Zone is an Omarchy Shell panel plugin:

```text
manifest.json  →  kinds: ["panel"], keepLoaded: true, entryPoints.panel = HomeZone.qml
```

- `keepLoaded: true` mounts the plugin when Omarchy Shell starts.
- The host injects `omarchyPath`, `shell`, `manifest`, `barWidgetRegistry`, and `pluginRegistry` after the component loads, and only when the corresponding property exists. The root properties are therefore intentionally not `required`; a Loader first creates the component without initial values.

## Layers and input

- A full-screen `PanelWindow` lives on `WlrLayer.Background`, above the wallpaper and below normal windows.
- `ExclusionMode.Ignore` means Home Zone reserves no desktop space.
- `mask: Region { item: cardPlacement }` restricts input to the visible card, leaving the rest of the screen click-through.

## Configuration boundary

`~/.config/omarchy/home-zone.json` is user state and survives plugin updates. `HomeZone.qml` never opens this predictable path directly. Short-lived `Process` instances invoke `/usr/bin/python3 helpers/home_zone_config.py read|write`; the helper resolves the account home from the effective UID and accepts an operation, never a path. A secure read runs every two seconds so an external edit is applied without restarting the shell. The document contains `display`, `grid`, `card`, `colors`, and `tiles[]`.

Built-in defaults keep the panel drawable while the helper reads the file. Settings and writes remain blocked until a safe initial read completes. A missing file on a fresh installation activates defaults; a security failure or the disappearance of an already loaded file keeps the last valid state and blocks writes.

`tiles[]` replaces the complete tile model when configuration changes, so the Repeater rebuilds its delegates. Each tile uses zero-based `col` and `row` coordinates plus `colspan` and `rowspan` sizes.

`display.size` scales the complete card, including tiles, fonts, and spacing: `default = 1.0`, `small = 0.8`, and `mini = 0.6`. `display.placement` centers the card or aligns it to `top`, `right`, `bottom`, or `left` with a 48-pixel margin. The input region follows the scaled card geometry.

## Theme

Default colors come from live Omarchy roles exposed by `qs.Commons`: `Color.*` and `Style.*`. The CanvasTTY-style composition maps clock to `Color.accent`, launcher to `Color.bar.*`, menu to `Color.muted`, settings to `Color.urgent`, and the outer card to `Color.background`. Optional `colors.*` values form only an override layer.

## Settings workflow

`SettingsOverlay.qml` owns a separate overlay window on `WlrLayer.Overlay`. Launcher switches apply immediately. Tile geometry, whole-widget size, and placement remain a draft until Save. The editor supports moving tiles and resizing them from every edge or corner while enforcing the fixed grid boundary and rejecting overlaps, then hands the result to the confined helper for atomic persistence.

Save copies only tile geometry and `display` into the latest loaded configuration, so a stale overlay draft cannot overwrite `appIds` or other settings changed during a reload. Cancel discards the draft. The fixed `10 × 4` grid cannot be resized; dropping onto another occupied slot swaps compatible tiles, while ordinary moves require free cells.

The `10 × 4` grid uses `68 × 68` cells and a 14-pixel gap. Two new cells plus the unchanged gap exactly equal one legacy 150-pixel cell. Migrating a legacy `5 × 2` layout doubles every coordinate and span without changing the outer pixel geometry.

Launcher settings cross the dynamic Loader boundary as a JSON string so QML cannot turn nested `appIds` into an ambiguous QVariant. A missing key selects the first four applications; an explicit empty array preserves `0/4`.

## Widget lifecycle

1. A Repeater over `tiles[]` creates an Item and a BorderSurface for each tile.
2. The tile Loader resolves `widgets/<widget>.qml` relative to `HomeZone.qml`.
3. `onLoaded` injects `shell`, `appLibrary`, `tileConfig`, and `tileColors` when the loaded widget declares them.

## Data flows

- Launcher reads `.desktop` entries from `shell.appLibrary`, stores up to four IDs in `tileConfig.appIds`, resolves those IDs back to application records, and launches through Omarchy's application API.
- Menu calls `shell.summon("omarchy.menu", ...)` with an `omarchy-shell` CLI fallback.
- Settings calls `HomeZone.openSettings()` directly; configuration cannot supply an arbitrary shell command.
- Clock uses `Qt.formatTime`, `Qt.formatDate`, and a one-second timer.

## Security properties

- The plugin runs inside unprivileged `omarchy-shell` and makes no network requests.
- The helper traverses descriptor-relatively from `/` through the account home and `.config/omarchy`, uses `O_NOFOLLOW`, and validates ownership and permissions for every directory.
- The configuration must be a regular file owned by the effective user with one hard link, no group or other write bit, and a maximum size of 64 KiB. A legacy user-owned `0644` file is tightened to `0600`.
- A write creates a fresh `0600` file, synchronizes it, and publishes it with `os.replace` relative to the already verified settings-directory descriptor.
- The repository contains no install hook, daemon, service, package-manager action, compiled binary, or privilege-elevation path.
