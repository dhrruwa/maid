# Colour palette: Saffron Glass

Both apps use **Saffron Glass**: frosted (Liquid Glass-style) surfaces over a warm saffron and peach glow. The main buttons are saffron-tinted glass with dark espresso text.

## Tokens

| Token | Hex | Used for |
|---|---|---|
| `accent` (saffron) | `#E8731F` | Icons, glass rims, progress bars, the background glow, the "now" line. **Never for text.** |
| `saffronFill` | `#EB873E` | Filled buttons (saffron glass), with `saffronRim` `#C9621A` as the outline |
| `espresso` | `#2A1B12` | Body text, and text on saffron buttons (6.4:1) |
| `ink` (burnt saffron) | `#9A4A12` | Text buttons, links, selected text (5.8:1 on the background) |
| `tint` | `#FFE0C7` | Selected chips, tonal buttons, selected states |
| `glowBase` | `#FFF6EE` | Page background under the glow |
| Dark mode (owner app) | `#140E0B` background, `#FFB27A` accent | Accent text is 9:1 on the dark background |

Status colours are fixed in both apps and always shown with an icon and a label:

| Status | Hex |
|---|---|
| Done | `#2E9E5B` |
| Waiting / partial | `#E0A100` |
| Missed | `#D64545` |
| Holiday | `#3B7DDD` |
| Leave | `#8E5BD8` |

## Glass

- **Owner app (full glass):**
  - Cards blur and saturate what's behind them. They share one backdrop blur per list (`BackdropGroup`), so it stays fast.
  - Cards have a light-catching rim and a soft warm shadow.
  - The bottom tab bar is frosted glass in the style of Blinkit: pinned full width, a short bar sliding along the top edge of the selected tab, and a two-tone selected icon (saffron fill, espresso outline).
- **Maid app (light glass):** the same translucent surfaces, rim and shadow, but **no live blur**. That keeps it smooth on low-end Android phones, and over the smooth background glow a blur would look the same anyway.

## Why this palette

Nine palettes were scored on:
- button-text contrast (WCAG)
- how far the brand colour is from each status colour (ΔE2000)
- the same distance after simulating red-blind and green-blind vision

**Espresso & Saffron** scored highest, with **Kitchen Teal** as runner-up. **Saffron Glass** was chosen for the Liquid Glass look because it is warmer and brighter.

Its trade-off: for colour-blind users, the saffron buttons sit close to the amber "Waiting" status. That's acceptable because statuses are small chips that always carry an icon and a word, while saffron is only used for large labelled buttons and decoration.

To switch palettes, change the constants at the top of `owner_app/lib/core/theme.dart` and `maid_app/lib/core/theme.dart`.
