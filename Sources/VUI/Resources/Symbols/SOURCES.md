# Portable Symbol Sources

The SVG assets in this directory are derived from the shared canonical
Material Design Icons source trees:

`External/google/material-design-icons/src/<category>/<source-name>/<style>/24px.svg`

`External/google/material-design-icons/symbols/web/<source-name>/<style>/<source-name>_24px.svg`

The bundled copies are covered by `NOTICE` and `LICENSE-APACHE-2.0.txt`.

## Naming and variant rules

- Resource names use neutral, dot-separated semantic names.
- A regular symbol normally uses `materialiconsoutlined`; its `.fill` variant
  uses `materialicons`.
- A `.fill` variant is included only when it has meaningfully different visible
  geometry. Linear action symbols remain single resources.
- State names such as `.off`, `.open`, `.low`, `.charging`, and `.alert`
  describe semantic states rather than fill variants.
- Duplicate aliases are not bundled. For example, the trash-can pair is
  exposed as `trash` and `trash.fill`, not as an additional `delete` pair.
- When the ordinary outlined style does not produce distinct regular geometry,
  an explicit alternate source icon is selected and recorded below.

## Renamed and alternate source mappings

| Bundled resource | Canonical Material source |
| --- | --- |
| `arrow.left.svg` | `navigation/arrow_back/materialicons/24px.svg` |
| `arrow.right.svg` | `navigation/arrow_forward/materialicons/24px.svg` |
| `battery.alert.svg` | `device/battery_alert/materialicons/24px.svg` |
| `battery.charging.svg` | `device/battery_charging_full/materialicons/24px.svg` |
| `battery.full.svg` | `device/battery_full/materialicons/24px.svg` |
| `battery.low.svg` | `device/battery_1_bar/materialicons/24px.svg` |
| `bell.svg` | `social/notifications/materialiconsoutlined/24px.svg` |
| `bell.fill.svg` | `social/notifications/materialicons/24px.svg` |
| `chevron.down.svg` | `navigation/expand_more/materialicons/24px.svg` |
| `chevron.up.svg` | `navigation/expand_less/materialicons/24px.svg` |
| `copy.svg` | `content/content_copy/materialicons/24px.svg` |
| `download.svg` | `file/download/materialicons/24px.svg` |
| `error.svg` | `alert/error_outline/materialicons/24px.svg` |
| `error.fill.svg` | `alert/error/materialicons/24px.svg` |
| `file.svg` | `editor/insert_drive_file/materialiconsoutlined/24px.svg` |
| `file.fill.svg` | `editor/insert_drive_file/materialicons/24px.svg` |
| `filter.svg` | `content/filter_list/materialicons/24px.svg` |
| `help.svg` | `action/help_outline/materialicons/24px.svg` |
| `help.fill.svg` | `action/help/materialicons/24px.svg` |
| `heart.svg` | `action/favorite_border/materialicons/24px.svg` |
| `heart.fill.svg` | `action/favorite/materialicons/24px.svg` |
| `keyboard.command.svg` | `symbols/web/keyboard_command_key/materialsymbolsoutlined/keyboard_command_key_24px.svg` |
| `keyboard.control.svg` | `symbols/web/keyboard_control_key/materialsymbolsoutlined/keyboard_control_key_24px.svg` |
| `keyboard.option.svg` | `symbols/web/keyboard_option_key/materialsymbolsoutlined/keyboard_option_key_24px.svg` |
| `keyboard.shift.svg` | `symbols/web/shift/materialsymbolsoutlined/shift_24px.svg` |
| `lock.open.svg` | `action/lock_open/materialiconsoutlined/24px.svg` |
| `lock.open.fill.svg` | `action/lock_open/materialicons/24px.svg` |
| `more.horizontal.svg` | `navigation/more_horiz/materialicons/24px.svg` |
| `more.vertical.svg` | `navigation/more_vert/materialicons/24px.svg` |
| `play.svg` | `av/play_arrow/materialicons/24px.svg` |
| `recycle.svg` | `social/recycling/materialicons/24px.svg` |
| `trash.svg` | `action/delete/materialiconsoutlined/24px.svg` |
| `trash.fill.svg` | `action/delete/materialicons/24px.svg` |
| `visibility.off.svg` | `action/visibility_off/materialiconsoutlined/24px.svg` |
| `visibility.off.fill.svg` | `action/visibility_off/materialicons/24px.svg` |
| `volume.svg` | `av/volume_up/materialicons/24px.svg` |
| `volume.off.svg` | `av/volume_off/materialicons/24px.svg` |
| `warning.svg` | `alert/warning_amber/materialiconsoutlined/24px.svg` |
| `warning.fill.svg` | `alert/warning/materialicons/24px.svg` |

Names not listed in this table retain the Material source name, with underscores
converted to dots only where a state or variant boundary is intended.

## Layer metadata

Files named `*.layers.json` are runtime layer and effect metadata. They do not
record asset provenance or regular-to-fill aliases. Human-readable source
selection and rename decisions belong in this document.
