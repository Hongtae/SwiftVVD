# Portable Symbol Sources

The SVG assets in this directory are derived from the official
[Material Design Icons](https://github.com/google/material-design-icons)
repository. Source paths are written relative to that repository using the
logical `material-design-icons/` root:

`material-design-icons/src/<category>/<source-name>/<style>/24px.svg`

`material-design-icons/symbols/web/<source-name>/<style>/<source-name>_24px.svg`

The bundled copies are covered by `NOTICE` and `LICENSE-APACHE-2.0.txt`.

## Naming and variant rules

- Resource names prefer established system-symbol names when a semantically
  matching glyph exists, and otherwise use neutral, dot-separated names.
- Material source slugs are provenance, not a requirement to retain redundant
  words such as `key`; every deliberate difference is recorded below.
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
| `arrow.left.svg` | `material-design-icons/src/navigation/arrow_back/materialicons/24px.svg` |
| `arrow.right.svg` | `material-design-icons/src/navigation/arrow_forward/materialicons/24px.svg` |
| `arrowtriangle.down.fill.svg` | `material-design-icons/symbols/web/arrow_drop_down/materialsymbolsoutlined/arrow_drop_down_24px.svg` |
| `arrowtriangle.left.fill.svg` | `material-design-icons/symbols/web/arrow_left/materialsymbolsoutlined/arrow_left_24px.svg` |
| `arrowtriangle.right.fill.svg` | `material-design-icons/symbols/web/arrow_right/materialsymbolsoutlined/arrow_right_24px.svg` |
| `arrowtriangle.up.fill.svg` | `material-design-icons/symbols/web/arrow_drop_up/materialsymbolsoutlined/arrow_drop_up_24px.svg` |
| `battery.alert.svg` | `material-design-icons/src/device/battery_alert/materialicons/24px.svg` |
| `battery.charging.svg` | `material-design-icons/src/device/battery_charging_full/materialicons/24px.svg` |
| `battery.full.svg` | `material-design-icons/src/device/battery_full/materialicons/24px.svg` |
| `battery.low.svg` | `material-design-icons/src/device/battery_1_bar/materialicons/24px.svg` |
| `bell.svg` | `material-design-icons/src/social/notifications/materialiconsoutlined/24px.svg` |
| `bell.fill.svg` | `material-design-icons/src/social/notifications/materialicons/24px.svg` |
| `checkmark.square.svg` | `material-design-icons/symbols/web/check_box/materialsymbolsoutlined/check_box_24px.svg` |
| `chevron.down.svg` | `material-design-icons/src/navigation/expand_more/materialicons/24px.svg` |
| `chevron.up.svg` | `material-design-icons/src/navigation/expand_less/materialicons/24px.svg` |
| `copy.svg` | `material-design-icons/src/content/content_copy/materialicons/24px.svg` |
| `download.svg` | `material-design-icons/src/file/download/materialicons/24px.svg` |
| `error.svg` | `material-design-icons/src/alert/error_outline/materialicons/24px.svg` |
| `error.fill.svg` | `material-design-icons/src/alert/error/materialicons/24px.svg` |
| `file.svg` | `material-design-icons/src/editor/insert_drive_file/materialiconsoutlined/24px.svg` |
| `file.fill.svg` | `material-design-icons/src/editor/insert_drive_file/materialicons/24px.svg` |
| `filter.svg` | `material-design-icons/src/content/filter_list/materialicons/24px.svg` |
| `help.svg` | `material-design-icons/src/action/help_outline/materialicons/24px.svg` |
| `help.fill.svg` | `material-design-icons/src/action/help/materialicons/24px.svg` |
| `heart.svg` | `material-design-icons/src/action/favorite_border/materialicons/24px.svg` |
| `heart.fill.svg` | `material-design-icons/src/action/favorite/materialicons/24px.svg` |
| `keyboard.command.svg` | `material-design-icons/symbols/web/keyboard_command_key/materialsymbolsoutlined/keyboard_command_key_24px.svg` |
| `keyboard.control.svg` | `material-design-icons/symbols/web/keyboard_control_key/materialsymbolsoutlined/keyboard_control_key_24px.svg` |
| `keyboard.option.svg` | `material-design-icons/symbols/web/keyboard_option_key/materialsymbolsoutlined/keyboard_option_key_24px.svg` |
| `keyboard.shift.svg` | `material-design-icons/symbols/web/shift/materialsymbolsoutlined/shift_24px.svg` |
| `lock.open.svg` | `material-design-icons/src/action/lock_open/materialiconsoutlined/24px.svg` |
| `lock.open.fill.svg` | `material-design-icons/src/action/lock_open/materialicons/24px.svg` |
| `more.horizontal.svg` | `material-design-icons/src/navigation/more_horiz/materialicons/24px.svg` |
| `more.vertical.svg` | `material-design-icons/src/navigation/more_vert/materialicons/24px.svg` |
| `minus.square.svg` | `material-design-icons/symbols/web/indeterminate_check_box/materialsymbolsoutlined/indeterminate_check_box_24px.svg` |
| `play.svg` | `material-design-icons/src/av/play_arrow/materialicons/24px.svg` |
| `recycle.svg` | `material-design-icons/src/social/recycling/materialicons/24px.svg` |
| `square.svg` | `material-design-icons/symbols/web/check_box_outline_blank/materialsymbolsoutlined/check_box_outline_blank_24px.svg` |
| `trash.svg` | `material-design-icons/src/action/delete/materialiconsoutlined/24px.svg` |
| `trash.fill.svg` | `material-design-icons/src/action/delete/materialicons/24px.svg` |
| `visibility.off.svg` | `material-design-icons/src/action/visibility_off/materialiconsoutlined/24px.svg` |
| `visibility.off.fill.svg` | `material-design-icons/src/action/visibility_off/materialicons/24px.svg` |
| `volume.svg` | `material-design-icons/src/av/volume_up/materialicons/24px.svg` |
| `volume.off.svg` | `material-design-icons/src/av/volume_off/materialicons/24px.svg` |
| `warning.svg` | `material-design-icons/src/alert/warning_amber/materialiconsoutlined/24px.svg` |
| `warning.fill.svg` | `material-design-icons/src/alert/warning/materialicons/24px.svg` |

Names not listed in this table retain the Material source name, with underscores
converted to dots only where a state or variant boundary is intended.

## Layer metadata

Files named `*.layers.json` are runtime layer and effect metadata. They do not
record asset provenance or regular-to-fill aliases. Human-readable source
selection and rename decisions belong in this document.
