# Notae Sans 0.2.0

Notae Sans is a screen-first neo-grotesk with a relaxed upright and a genuinely drawn italic companion. Both styles cover a continuous 100–900 weight range in the variable files. The desktop package also supplies nine named upright weights and nine matching italics.

## Contents

- `desktop/static/` — 18 installable TTFs: Thin, ExtraLight, Light, Regular, Medium, SemiBold, Bold, ExtraBold and Black, each upright and italic.
- `desktop/variable/` — upright and italic variable TTFs for software that explicitly supports variable fonts.
- `web/` — upright and italic variable WOFF2 files, one request per style.
- `notae-sans.css` — ready-to-copy self-hosted web declarations.
- `OFL.txt` — SIL Open Font License 1.1 and upstream copyright notices.

## Desktop installation

Install the 18 files in `desktop/static/` through Font Book, or copy them into the current user's font folder on macOS:

```sh
cp desktop/static/NotaeSans-*.ttf "$HOME/Library/Fonts/"
```

The static family is the most compatible choice for office applications, Adobe applications and document export. Do not install the two variable TTFs at the same time as the static family; some applications show duplicate menu entries or choose an unpredictable face when both sets are active.

Applications that were open during installation may need to be restarted before Notae Sans appears in their font menu.

## Web installation

Keep `notae-sans.css` beside the `web/` folder, then include the stylesheet and use `font-family: "Notae Sans", sans-serif`. The two WOFF2 files contain every integer weight from 100 through 900. Upright and italic are separate downloads, so pages that never use italic do not pay for it.

## Coverage and limitations

The family covers 470 encoded codepoints across Basic Latin, Latin-1, Latin Extended and Cyrillic. Greek and the currency signs ₸, ₹, ₺, ₼, ₾ and ₿ are not included in 0.2.0 and will fall back to the next family in the font stack.

Upright and italic use matching 1,000-unit vertical metrics: cap height 718, typographic ascender 985, descender -315 and zero line gap. Upright x-height is 535; italic x-height is 539.

## License

Notae Sans is a renamed and custom-tuned derivative of Onest and Inter Italic. It is distributed under the SIL Open Font License 1.1. See `OFL.txt` for the complete terms and source notices.
